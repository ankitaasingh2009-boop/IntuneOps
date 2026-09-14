<#
.SYNOPSIS
    Collects Windows Autopilot diagnostic data from Microsoft Intune via Microsoft Graph.

.DESCRIPTION
    Connects to Microsoft Graph and retrieves:
    - Autopilot device identities and registration state
    - Deployment profile assignments
    - Enrollment Status Page (ESP) configuration
    - Recent Autopilot enrollment failures
    Exports a consolidated report as HTML and/or CSV.

.PARAMETER TenantId
    Azure AD tenant ID. If omitted, uses the default tenant for the signed-in account.

.PARAMETER OutputPath
    Directory for the report output. Defaults to current directory.

.PARAMETER OutputFormat
    Report format: HTML, CSV, or Both. Default: Both.

.PARAMETER DeviceSerial
    Optional. Filter diagnostics to a single device by serial number.

.PARAMETER DaysBack
    Number of days to look back for enrollment failures. Default: 7.

.EXAMPLE
    .\Get-AutopilotDiagnostics.ps1 -OutputFormat HTML

.EXAMPLE
    .\Get-AutopilotDiagnostics.ps1 -DeviceSerial "1234-5678-ABCD" -DaysBack 30

.NOTES
    Requires Microsoft.Graph PowerShell SDK.
    Permissions needed: DeviceManagementServiceConfig.Read.All,
                        DeviceManagementManagedDevices.Read.All
    Author: Ankita Singh | https://github.com/intuneopstoolkit
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$OutputPath = ".",

    [Parameter()]
    [ValidateSet("HTML", "CSV", "Both")]
    [string]$OutputFormat = "Both",

    [Parameter()]
    [string]$DeviceSerial,

    [Parameter()]
    [int]$DaysBack = 7
)

#region --- Module Check ---
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.DeviceManagement',
    'Microsoft.Graph.DeviceManagement.Enrollment'
)

foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Error "Required module '$mod' not found. Install with: Install-Module $mod"
        return
    }
}
#endregion

#region --- Connect to Graph ---
function Connect-ToGraph {
    param([string]$TenantId)

    $scopes = @(
        "DeviceManagementServiceConfig.Read.All",
        "DeviceManagementManagedDevices.Read.All"
    )

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

#region --- Data Collection Functions ---
function Get-AutopilotDevices {
    [CmdletBinding()]
    param([string]$Serial)

    Write-Host "  Fetching Autopilot device identities..." -ForegroundColor Yellow
    try {
        if ($Serial) {
            $devices = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$Serial')"
        } else {
            $devices = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -All
        }

        $devices | ForEach-Object {
            [PSCustomObject]@{
                SerialNumber        = $_.SerialNumber
                Model               = $_.Model
                Manufacturer        = $_.Manufacturer
                GroupTag            = $_.GroupTag
                PurchaseOrderId     = $_.PurchaseOrderIdentifier
                EnrollmentState     = $_.EnrollmentState
                LastContactedAt     = $_.LastContactedDateTime
                DeploymentProfileStatus = $_.DeploymentProfileAssignmentStatus
                DeploymentProfile   = $_.DeploymentProfileAssignedDateTime
            }
        }
    } catch {
        Write-Warning "Failed to fetch Autopilot devices: $_"
        return @()
    }
}

function Get-DeploymentProfiles {
    [CmdletBinding()]
    param()

    Write-Host "  Fetching deployment profiles..." -ForegroundColor Yellow
    try {
        $profiles = Get-MgDeviceManagementWindowsAutopilotDeploymentProfile -All
        $profiles | ForEach-Object {
            [PSCustomObject]@{
                ProfileName          = $_.DisplayName
                Description          = $_.Description
                Language             = $_.Language
                OutOfBoxExperienceSettings = ($_.OutOfBoxExperienceSetting | ConvertTo-Json -Compress)
                ExtractHardwareHash  = $_.ExtractHardwareHash
                DeviceNameTemplate   = $_.DeviceNameTemplate
                DeviceType           = $_.DeviceType
                CreatedDateTime      = $_.CreatedDateTime
                LastModifiedDateTime = $_.LastModifiedDateTime
            }
        }
    } catch {
        Write-Warning "Failed to fetch deployment profiles: $_"
        return @()
    }
}

function Get-EnrollmentStatusPage {
    [CmdletBinding()]
    param()

    Write-Host "  Fetching Enrollment Status Page configs..." -ForegroundColor Yellow
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=deviceEnrollmentConfigurationType eq 'windowsEnrollmentStatusPage'"
        $espConfigs = Invoke-MgGraphRequest -Method GET -Uri $uri

        $espConfigs.value | ForEach-Object {
            [PSCustomObject]@{
                Name                      = $_.displayName
                ShowInstallationProgress  = $_.showInstallationProgress
                BlockDeviceUntilComplete  = $_.blockDeviceSetupRetiredUntilComplete
                AllowDeviceUseOnFailure   = $_.allowDeviceUseOnInstallFailure
                AllowLogCollection        = $_.allowLogCollectionOnInstallFailure
                CustomErrorMessage        = $_.customErrorMessage
                InstallProgressTimeout    = $_.installProgressTimeoutInMinutes
                AllowDeviceUseBeforeProfileAndAppInstall = $_.allowDeviceUseBeforeProfileAndAppInstallComplete
                Priority                  = $_.priority
            }
        }
    } catch {
        Write-Warning "Failed to fetch ESP configurations: $_"
        return @()
    }
}

function Get-EnrollmentFailures {
    [CmdletBinding()]
    param([int]$DaysBack)

    Write-Host "  Fetching enrollment failures (last $DaysBack days)..." -ForegroundColor Yellow
    try {
        $startDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $uri = "https://graph.microsoft.com/beta/deviceManagement/importedDeviceIdentities?`$filter=importedDeviceIdentityType eq 'autopilot'"

        # Use troubleshooting events for enrollment failures
        $troubleUri = "https://graph.microsoft.com/beta/deviceManagement/troubleshootingEvents?`$filter=eventDateTime ge $startDate"
        $events = Invoke-MgGraphRequest -Method GET -Uri $troubleUri

        $events.value | Where-Object {
            $_.additionalInformation -and
            ($_ | ConvertTo-Json -Depth 5) -match "autopilot|enrollment"
        } | ForEach-Object {
            [PSCustomObject]@{
                EventDateTime  = $_.eventDateTime
                EventName      = $_.eventName
                CorrelationId  = $_.correlationId
                FailureCategory = $_.failureCategory
                FailureReason  = $_.failureReason
            }
        }
    } catch {
        Write-Warning "Failed to fetch enrollment failures: $_"
        return @()
    }
}
#endregion

#region --- Report Generation ---
function Export-HtmlReport {
    param(
        [object[]]$Devices,
        [object[]]$Profiles,
        [object[]]$EspConfigs,
        [object[]]$Failures,
        [string]$Path
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $deviceRows = $Devices | ForEach-Object {
        "<tr><td>$($_.SerialNumber)</td><td>$($_.Manufacturer)</td><td>$($_.Model)</td><td>$($_.GroupTag)</td><td>$($_.EnrollmentState)</td><td>$($_.DeploymentProfileStatus)</td><td>$($_.LastContactedAt)</td></tr>"
    }

    $profileRows = $Profiles | ForEach-Object {
        "<tr><td>$($_.ProfileName)</td><td>$($_.DeviceNameTemplate)</td><td>$($_.DeviceType)</td><td>$($_.ExtractHardwareHash)</td><td>$($_.LastModifiedDateTime)</td></tr>"
    }

    $espRows = $EspConfigs | ForEach-Object {
        "<tr><td>$($_.Name)</td><td>$($_.ShowInstallationProgress)</td><td>$($_.BlockDeviceUntilComplete)</td><td>$($_.AllowDeviceUseOnFailure)</td><td>$($_.InstallProgressTimeout) min</td></tr>"
    }

    $failureRows = $Failures | ForEach-Object {
        "<tr><td>$($_.EventDateTime)</td><td>$($_.FailureCategory)</td><td>$($_.FailureReason)</td><td>$($_.CorrelationId)</td></tr>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Autopilot Diagnostics Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 2rem; background: #f5f5f5; color: #333; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 0.5rem; }
        h2 { color: #106ebe; margin-top: 2rem; }
        table { border-collapse: collapse; width: 100%; margin: 1rem 0; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 10px 14px; text-align: left; font-size: 0.9rem; }
        th { background: #0078d4; color: #fff; }
        tr:nth-child(even) { background: #f9f9f9; }
        tr:hover { background: #e8f0fe; }
        .summary { background: #fff; padding: 1rem 1.5rem; border-left: 4px solid #0078d4; margin: 1rem 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .timestamp { color: #888; font-size: 0.85rem; }
        .warning { border-left-color: #ff8c00; }
        .count { font-size: 1.8rem; font-weight: bold; color: #0078d4; }
    </style>
</head>
<body>
    <h1>Autopilot Diagnostics Report</h1>
    <p class="timestamp">Generated: $timestamp</p>

    <div style="display: flex; gap: 1rem; flex-wrap: wrap;">
        <div class="summary"><div class="count">$($Devices.Count)</div>Autopilot Devices</div>
        <div class="summary"><div class="count">$($Profiles.Count)</div>Deployment Profiles</div>
        <div class="summary"><div class="count">$($EspConfigs.Count)</div>ESP Configs</div>
        <div class="summary $(if($Failures.Count -gt 0){'warning'})"><div class="count">$($Failures.Count)</div>Recent Failures</div>
    </div>

    <h2>Autopilot Device Identities</h2>
    <table>
        <tr><th>Serial Number</th><th>Manufacturer</th><th>Model</th><th>Group Tag</th><th>Enrollment State</th><th>Profile Status</th><th>Last Contact</th></tr>
        $($deviceRows -join "`n        ")
    </table>

    <h2>Deployment Profiles</h2>
    <table>
        <tr><th>Profile Name</th><th>Device Name Template</th><th>Device Type</th><th>Extract Hardware Hash</th><th>Last Modified</th></tr>
        $($profileRows -join "`n        ")
    </table>

    <h2>Enrollment Status Page Configuration</h2>
    <table>
        <tr><th>Name</th><th>Show Progress</th><th>Block Until Complete</th><th>Allow Use on Failure</th><th>Timeout</th></tr>
        $($espRows -join "`n        ")
    </table>

    <h2>Recent Enrollment Failures</h2>
    $(if ($Failures.Count -eq 0) {
        '<p style="color: #107c10; font-weight: bold;">No enrollment failures in the selected period.</p>'
    } else {
        "<table><tr><th>Date/Time</th><th>Failure Category</th><th>Reason</th><th>Correlation ID</th></tr>`n        $($failureRows -join "`n        ")</table>"
    })

    <hr style="margin-top: 3rem; border: none; border-top: 1px solid #ddd;">
    <p class="timestamp">IntuneOps &mdash; Autopilot Diagnostics Collector v1.0.0</p>
</body>
</html>
"@

    $html | Out-File -FilePath $Path -Encoding utf8
    Write-Host "  HTML report: $Path" -ForegroundColor Green
}

function Export-CsvReport {
    param(
        [object[]]$Devices,
        [string]$Path
    )

    $Devices | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
    Write-Host "  CSV report: $Path" -ForegroundColor Green
}
#endregion

#region --- Main Execution ---
function Invoke-AutopilotDiagnostics {
    Write-Host "`n=== IntuneOps: Autopilot Diagnostics Collector ===" -ForegroundColor Cyan
    Write-Host ""

    # Connect
    if (-not (Connect-ToGraph -TenantId $TenantId)) { return }

    # Collect data
    Write-Host "`nCollecting data..." -ForegroundColor Cyan
    $devices    = Get-AutopilotDevices -Serial $DeviceSerial
    $profiles   = Get-DeploymentProfiles
    $espConfigs = Get-EnrollmentStatusPage
    $failures   = Get-EnrollmentFailures -DaysBack $DaysBack

    # Summary
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host "  Autopilot devices : $($devices.Count)"
    Write-Host "  Deployment profiles: $($profiles.Count)"
    Write-Host "  ESP configs        : $($espConfigs.Count)"
    Write-Host "  Enrollment failures: $($failures.Count)"

    # Ensure output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    # Export
    if ($OutputFormat -in @("HTML", "Both")) {
        $htmlPath = Join-Path $OutputPath "AutopilotDiagnostics_$timestamp.html"
        Export-HtmlReport -Devices $devices -Profiles $profiles -EspConfigs $espConfigs -Failures $failures -Path $htmlPath
    }

    if ($OutputFormat -in @("CSV", "Both")) {
        $csvPath = Join-Path $OutputPath "AutopilotDevices_$timestamp.csv"
        Export-CsvReport -Devices $devices -Path $csvPath
    }

    Write-Host "`nDone." -ForegroundColor Green
}

# Run
Invoke-AutopilotDiagnostics
#endregion
