<#
.SYNOPSIS
    Detects configuration drift in Intune device configuration profiles by comparing live
    settings against a saved baseline.

.DESCRIPTION
    Connects to Microsoft Graph, pulls all device configuration profiles (or a specific one),
    and compares each setting against a previously exported JSON baseline. Reports:
    - Added settings (in live but not in baseline)
    - Removed settings (in baseline but not in live)
    - Modified settings (value changed)
    Can also export the current state as a new baseline.

.PARAMETER TenantId
    Azure AD tenant ID. Optional.

.PARAMETER BaselinePath
    Path to the baseline JSON file. Required for drift detection.

.PARAMETER ExportBaseline
    Switch. Export current live config as a new baseline instead of comparing.

.PARAMETER OutputPath
    Directory for drift report output. Defaults to current directory.

.PARAMETER OutputFormat
    Report format: HTML, CSV, JSON, or Console. Default: HTML.

.PARAMETER ProfileName
    Optional. Filter to a specific configuration profile by display name (supports wildcards).

.EXAMPLE
    # Export current state as baseline
    .\Find-IntuneDrift.ps1 -ExportBaseline -OutputPath ./baselines

.EXAMPLE
    # Detect drift against saved baseline
    .\Find-IntuneDrift.ps1 -BaselinePath ./baselines/baseline_20260901.json

.EXAMPLE
    # Check a single profile
    .\Find-IntuneDrift.ps1 -BaselinePath ./baselines/baseline.json -ProfileName "Wi-Fi*"

.NOTES
    Requires Microsoft.Graph PowerShell SDK.
    Permissions needed: DeviceManagementConfiguration.Read.All
    Author: Ankita Singh | https://github.com/intuneopstoolkit
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$BaselinePath,

    [Parameter()]
    [switch]$ExportBaseline,

    [Parameter()]
    [string]$OutputPath = ".",

    [Parameter()]
    [ValidateSet("HTML", "CSV", "JSON", "Console")]
    [string]$OutputFormat = "HTML",

    [Parameter()]
    [string]$ProfileName
)

#region --- Module Check ---
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.DeviceManagement'
)

foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Error "Required module '$mod' not found. Install with: Install-Module $mod"
        return
    }
}
#endregion

#region --- Connect ---
function Connect-ToGraph {
    param([string]$TenantId)

    $scopes = @("DeviceManagementConfiguration.Read.All")
    $connectParams = @{ Scopes = $scopes }
    if ($TenantId) { $connectParams['TenantId'] = $TenantId }

    try {
        $context = Get-MgContext
        if (-not $context) {
            Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
            Connect-MgGraph @connectParams
        } else {
            Write-Host "Already connected as $($context.Account)" -ForegroundColor Green
        }
    } catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        return $false
    }
    return $true
}
#endregion

#region --- Live Config Retrieval ---
function Get-LiveConfigProfiles {
    [CmdletBinding()]
    param([string]$ProfileName)

    Write-Host "  Fetching device configuration profiles..." -ForegroundColor Yellow

    try {
        $profiles = Get-MgDeviceManagementDeviceConfiguration -All

        if ($ProfileName) {
            $profiles = $profiles | Where-Object { $_.DisplayName -like $ProfileName }
        }

        $result = @{}

        foreach ($profile in $profiles) {
            $profileData = @{
                Id                   = $profile.Id
                DisplayName          = $profile.DisplayName
                Description          = $profile.Description
                ODataType            = $profile.AdditionalProperties.'@odata.type'
                CreatedDateTime      = $profile.CreatedDateTime
                LastModifiedDateTime = $profile.LastModifiedDateTime
                Version              = $profile.Version
                Settings             = @{}
            }

            # Get the full profile with all settings via direct Graph call
            $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($profile.Id)"
            $fullProfile = Invoke-MgGraphRequest -Method GET -Uri $uri

            # Extract all settings (skip metadata keys)
            $skipKeys = @('@odata.type', '@odata.context', 'id', 'displayName', 'description',
                          'createdDateTime', 'lastModifiedDateTime', 'version',
                          'roleScopeTagIds', 'supportsScopeTags', 'deviceManagementApplicabilityRuleOsEdition',
                          'deviceManagementApplicabilityRuleOsVersion', 'deviceManagementApplicabilityRuleDeviceMode')

            foreach ($key in $fullProfile.Keys) {
                if ($key -notin $skipKeys) {
                    $profileData.Settings[$key] = $fullProfile[$key]
                }
            }

            $result[$profile.DisplayName] = $profileData
        }

        return $result
    } catch {
        Write-Warning "Failed to fetch configuration profiles: $_"
        return @{}
    }
}
#endregion

#region --- Baseline Operations ---
function Export-Baseline {
    param(
        [hashtable]$LiveConfig,
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $filePath = Join-Path $Path "baseline_$timestamp.json"

    $LiveConfig | ConvertTo-Json -Depth 20 | Out-File -FilePath $filePath -Encoding utf8
    Write-Host "`n  Baseline exported: $filePath" -ForegroundColor Green
    Write-Host "  Profiles captured: $($LiveConfig.Count)" -ForegroundColor Green
    return $filePath
}

function Import-Baseline {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Error "Baseline file not found: $Path"
        return $null
    }

    try {
        $content = Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable
        Write-Host "  Baseline loaded: $($content.Count) profiles" -ForegroundColor Green
        return $content
    } catch {
        Write-Error "Failed to parse baseline file: $_"
        return $null
    }
}
#endregion

#region --- Drift Detection ---
function Compare-Configurations {
    param(
        [hashtable]$Baseline,
        [hashtable]$Live
    )

    $drifts = @()

    # Profiles in live but not in baseline (added)
    foreach ($profileName in $Live.Keys) {
        if (-not $Baseline.ContainsKey($profileName)) {
            $drifts += [PSCustomObject]@{
                ProfileName = $profileName
                DriftType   = "ProfileAdded"
                Setting     = "N/A"
                BaselineVal = "N/A"
                LiveVal     = "New profile"
                Severity    = "Info"
            }
            continue
        }

        $baseSettings = $Baseline[$profileName].Settings
        $liveSettings = $Live[$profileName].Settings

        # Settings added in live
        foreach ($key in $liveSettings.Keys) {
            if (-not $baseSettings.ContainsKey($key)) {
                $drifts += [PSCustomObject]@{
                    ProfileName = $profileName
                    DriftType   = "SettingAdded"
                    Setting     = $key
                    BaselineVal = "N/A"
                    LiveVal     = ($liveSettings[$key] | ConvertTo-Json -Compress -Depth 5)
                    Severity    = "Warning"
                }
            }
        }

        # Settings removed from live
        foreach ($key in $baseSettings.Keys) {
            if (-not $liveSettings.ContainsKey($key)) {
                $drifts += [PSCustomObject]@{
                    ProfileName = $profileName
                    DriftType   = "SettingRemoved"
                    Setting     = $key
                    BaselineVal = ($baseSettings[$key] | ConvertTo-Json -Compress -Depth 5)
                    LiveVal     = "N/A"
                    Severity    = "Warning"
                }
            }
        }

        # Settings modified
        foreach ($key in $liveSettings.Keys) {
            if ($baseSettings.ContainsKey($key)) {
                $baseJson = $baseSettings[$key] | ConvertTo-Json -Compress -Depth 10
                $liveJson = $liveSettings[$key] | ConvertTo-Json -Compress -Depth 10

                if ($baseJson -ne $liveJson) {
                    $drifts += [PSCustomObject]@{
                        ProfileName = $profileName
                        DriftType   = "SettingModified"
                        Setting     = $key
                        BaselineVal = $baseJson
                        LiveVal     = $liveJson
                        Severity    = "Critical"
                    }
                }
            }
        }
    }

    # Profiles in baseline but not in live (removed)
    foreach ($profileName in $Baseline.Keys) {
        if (-not $Live.ContainsKey($profileName)) {
            $drifts += [PSCustomObject]@{
                ProfileName = $profileName
                DriftType   = "ProfileRemoved"
                Setting     = "N/A"
                BaselineVal = "Existed in baseline"
                LiveVal     = "N/A"
                Severity    = "Critical"
            }
        }
    }

    return $drifts
}
#endregion

#region --- Report Export ---
function Export-DriftHtml {
    param(
        [object[]]$Drifts,
        [string]$Path
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $critCount = ($Drifts | Where-Object Severity -eq "Critical").Count
    $warnCount = ($Drifts | Where-Object Severity -eq "Warning").Count
    $infoCount = ($Drifts | Where-Object Severity -eq "Info").Count

    $rows = $Drifts | ForEach-Object {
        $severityClass = switch ($_.Severity) {
            "Critical" { "severity-critical" }
            "Warning"  { "severity-warning" }
            default    { "severity-info" }
        }
        "<tr class='$severityClass'><td>$($_.ProfileName)</td><td>$($_.DriftType)</td><td>$($_.Setting)</td><td><code>$($_.BaselineVal)</code></td><td><code>$($_.LiveVal)</code></td><td>$($_.Severity)</td></tr>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Intune Config Drift Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 2rem; background: #f5f5f5; color: #333; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 0.5rem; }
        table { border-collapse: collapse; width: 100%; margin: 1rem 0; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 10px 14px; text-align: left; font-size: 0.85rem; }
        th { background: #0078d4; color: #fff; }
        code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 0.8rem; word-break: break-all; }
        .severity-critical { border-left: 4px solid #d13438; }
        .severity-warning  { border-left: 4px solid #ff8c00; }
        .severity-info     { border-left: 4px solid #0078d4; }
        .cards { display: flex; gap: 1rem; flex-wrap: wrap; margin: 1rem 0; }
        .card { background: #fff; padding: 1rem 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); min-width: 140px; }
        .card .num { font-size: 2rem; font-weight: bold; }
        .card.critical .num { color: #d13438; }
        .card.warning .num  { color: #ff8c00; }
        .card.info .num     { color: #0078d4; }
        .timestamp { color: #888; font-size: 0.85rem; }
    </style>
</head>
<body>
    <h1>Intune Configuration Drift Report</h1>
    <p class="timestamp">Generated: $timestamp</p>

    <div class="cards">
        <div class="card critical"><div class="num">$critCount</div>Critical</div>
        <div class="card warning"><div class="num">$warnCount</div>Warning</div>
        <div class="card info"><div class="num">$infoCount</div>Info</div>
        <div class="card"><div class="num">$($Drifts.Count)</div>Total Drifts</div>
    </div>

    $(if ($Drifts.Count -eq 0) {
        '<div class="card info" style="border-left: 4px solid #107c10;"><p style="color: #107c10; font-weight: bold; margin: 0;">No drift detected. Live configuration matches the baseline.</p></div>'
    } else {
        "<table><tr><th>Profile</th><th>Drift Type</th><th>Setting</th><th>Baseline Value</th><th>Live Value</th><th>Severity</th></tr>`n$($rows -join "`n")</table>"
    })

    <hr style="margin-top: 3rem; border: none; border-top: 1px solid #ddd;">
    <p class="timestamp">IntuneOps &mdash; Config Drift Detector v1.0.0</p>
</body>
</html>
"@

    $html | Out-File -FilePath $Path -Encoding utf8
    Write-Host "  HTML report: $Path" -ForegroundColor Green
}

function Export-DriftConsole {
    param([object[]]$Drifts)

    if ($Drifts.Count -eq 0) {
        Write-Host "`n  No drift detected." -ForegroundColor Green
        return
    }

    Write-Host "`n  Drifts Found: $($Drifts.Count)" -ForegroundColor Yellow
    Write-Host ("  " + "-" * 90)

    $Drifts | ForEach-Object {
        $color = switch ($_.Severity) {
            "Critical" { "Red" }
            "Warning"  { "Yellow" }
            default    { "Cyan" }
        }
        Write-Host "  [$($_.Severity.ToUpper().PadRight(8))] $($_.ProfileName) | $($_.DriftType) | $($_.Setting)" -ForegroundColor $color
        if ($_.BaselineVal -ne "N/A") { Write-Host "             Baseline: $($_.BaselineVal)" -ForegroundColor DarkGray }
        if ($_.LiveVal -ne "N/A")     { Write-Host "             Live    : $($_.LiveVal)" -ForegroundColor DarkGray }
    }
}
#endregion

#region --- Main ---
function Invoke-DriftDetection {
    Write-Host "`n=== IntuneOps: Config Drift Detector ===" -ForegroundColor Cyan
    Write-Host ""

    if (-not $ExportBaseline -and -not $BaselinePath) {
        Write-Error "Specify -BaselinePath for drift detection or -ExportBaseline to save current state."
        return
    }

    # Connect
    if (-not (Connect-ToGraph -TenantId $TenantId)) { return }

    # Get live config
    Write-Host "`nCollecting live configuration..." -ForegroundColor Cyan
    $liveConfig = Get-LiveConfigProfiles -ProfileName $ProfileName

    if ($liveConfig.Count -eq 0) {
        Write-Warning "No configuration profiles found."
        return
    }

    Write-Host "  Found $($liveConfig.Count) profiles" -ForegroundColor Green

    # Export baseline mode
    if ($ExportBaseline) {
        Export-Baseline -LiveConfig $liveConfig -Path $OutputPath
        return
    }

    # Drift detection mode
    Write-Host "`nLoading baseline..." -ForegroundColor Cyan
    $baseline = Import-Baseline -Path $BaselinePath
    if (-not $baseline) { return }

    Write-Host "`nComparing configurations..." -ForegroundColor Cyan
    $drifts = Compare-Configurations -Baseline $baseline -Live $liveConfig

    # Ensure output dir
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    # Output
    switch ($OutputFormat) {
        "HTML" {
            $htmlPath = Join-Path $OutputPath "DriftReport_$timestamp.html"
            Export-DriftHtml -Drifts $drifts -Path $htmlPath
        }
        "CSV" {
            $csvPath = Join-Path $OutputPath "DriftReport_$timestamp.csv"
            $drifts | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
            Write-Host "  CSV report: $csvPath" -ForegroundColor Green
        }
        "JSON" {
            $jsonPath = Join-Path $OutputPath "DriftReport_$timestamp.json"
            $drifts | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8
            Write-Host "  JSON report: $jsonPath" -ForegroundColor Green
        }
        "Console" {
            Export-DriftConsole -Drifts $drifts
        }
    }

    # Summary
    $critCount = ($drifts | Where-Object Severity -eq "Critical").Count
    if ($critCount -gt 0) {
        Write-Host "`n  CRITICAL drifts detected: $critCount" -ForegroundColor Red
    } else {
        Write-Host "`n  No critical drifts." -ForegroundColor Green
    }

    Write-Host "Done.`n" -ForegroundColor Green
}

# Run
Invoke-DriftDetection
#endregion
