<#
.SYNOPSIS
    Generates an Intune device compliance report via Microsoft Graph.

.DESCRIPTION
    Connects to Microsoft Graph and collects:
    - All managed devices with their compliance state
    - Compliance policy assignments and evaluation details
    - Non-compliant setting details per device
    - Summary statistics by OS, compliance state, and policy
    Exports as HTML dashboard and/or CSV.

.PARAMETER TenantId
    Azure AD tenant ID. Optional.

.PARAMETER OutputPath
    Directory for report output. Defaults to current directory.

.PARAMETER OutputFormat
    Report format: HTML, CSV, or Both. Default: Both.

.PARAMETER Filter
    Filter devices: All, Compliant, NonCompliant, InGracePeriod, Unknown. Default: All.

.PARAMETER OS
    Filter by OS platform: Windows, iOS, Android, macOS, or All. Default: All.

.PARAMETER Top
    Maximum number of devices to process. Default: all devices.

.EXAMPLE
    .\Get-ComplianceReport.ps1 -Filter NonCompliant -OutputFormat HTML

.EXAMPLE
    .\Get-ComplianceReport.ps1 -OS Windows -Top 100

.NOTES
    Requires Microsoft.Graph PowerShell SDK.
    Permissions needed: DeviceManagementManagedDevices.Read.All,
                        DeviceManagementConfiguration.Read.All
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
    [ValidateSet("All", "Compliant", "NonCompliant", "InGracePeriod", "Unknown")]
    [string]$Filter = "All",

    [Parameter()]
    [ValidateSet("All", "Windows", "iOS", "Android", "macOS")]
    [string]$OS = "All",

    [Parameter()]
    [int]$Top = 0
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

    $scopes = @(
        "DeviceManagementManagedDevices.Read.All",
        "DeviceManagementConfiguration.Read.All"
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

#region --- Data Collection ---
function Get-ManagedDevicesCompliance {
    [CmdletBinding()]
    param(
        [string]$Filter,
        [string]$OS,
        [int]$Top
    )

    Write-Host "  Fetching managed devices..." -ForegroundColor Yellow

    try {
        $graphFilter = @()
        if ($Filter -ne "All") {
            $stateMap = @{
                "Compliant"     = "compliant"
                "NonCompliant"  = "noncompliant"
                "InGracePeriod" = "inGracePeriod"
                "Unknown"       = "unknown"
            }
            $graphFilter += "complianceState eq '$($stateMap[$Filter])'"
        }

        if ($OS -ne "All") {
            $osMap = @{
                "Windows" = "windows"
                "iOS"     = "iOS"
                "Android" = "android"
                "macOS"   = "macOS"
            }
            $graphFilter += "operatingSystem eq '$($osMap[$OS])'"
        }

        $params = @{ All = $true }
        if ($graphFilter.Count -gt 0) {
            $params['Filter'] = $graphFilter -join " and "
        }
        if ($Top -gt 0) {
            $params.Remove('All')
            $params['Top'] = $Top
        }

        $devices = Get-MgDeviceManagementManagedDevice @params

        $devices | ForEach-Object {
            [PSCustomObject]@{
                DeviceName         = $_.DeviceName
                UserPrincipalName  = $_.UserPrincipalName
                OperatingSystem    = $_.OperatingSystem
                OSVersion          = $_.OsVersion
                ComplianceState    = $_.ComplianceState
                LastSyncDateTime   = $_.LastSyncDateTime
                Model              = $_.Model
                Manufacturer       = $_.Manufacturer
                SerialNumber       = $_.SerialNumber
                EnrolledDateTime   = $_.EnrolledDateTime
                ManagementAgent    = $_.ManagementAgent
                DeviceId           = $_.Id
                IsEncrypted        = $_.IsEncrypted
                JailBroken         = $_.JailBroken
            }
        }
    } catch {
        Write-Warning "Failed to fetch managed devices: $_"
        return @()
    }
}

function Get-CompliancePolicies {
    [CmdletBinding()]
    param()

    Write-Host "  Fetching compliance policies..." -ForegroundColor Yellow
    try {
        $policies = Get-MgDeviceManagementDeviceCompliancePolicy -All
        $policies | ForEach-Object {
            [PSCustomObject]@{
                PolicyName           = $_.DisplayName
                PolicyId             = $_.Id
                Description          = $_.Description
                CreatedDateTime      = $_.CreatedDateTime
                LastModifiedDateTime = $_.LastModifiedDateTime
                Version              = $_.Version
            }
        }
    } catch {
        Write-Warning "Failed to fetch compliance policies: $_"
        return @()
    }
}

function Get-NonCompliantDetails {
    [CmdletBinding()]
    param([string]$DeviceId)

    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$DeviceId/deviceCompliancePolicyStates"
        $states = Invoke-MgGraphRequest -Method GET -Uri $uri

        $states.value | Where-Object { $_.state -ne "compliant" } | ForEach-Object {
            [PSCustomObject]@{
                PolicyName   = $_.displayName
                State        = $_.state
                SettingCount = $_.settingCount
            }
        }
    } catch {
        return @()
    }
}
#endregion

#region --- Statistics ---
function Get-ComplianceStats {
    param([object[]]$Devices)

    $total = $Devices.Count
    $compliant    = ($Devices | Where-Object ComplianceState -eq "compliant").Count
    $nonCompliant = ($Devices | Where-Object ComplianceState -eq "noncompliant").Count
    $gracePeriod  = ($Devices | Where-Object ComplianceState -eq "inGracePeriod").Count
    $unknown      = ($Devices | Where-Object ComplianceState -eq "unknown").Count

    $byOS = $Devices | Group-Object OperatingSystem | ForEach-Object {
        $osDevices = $_.Group
        [PSCustomObject]@{
            OS              = $_.Name
            Total           = $_.Count
            Compliant       = ($osDevices | Where-Object ComplianceState -eq "compliant").Count
            NonCompliant    = ($osDevices | Where-Object ComplianceState -eq "noncompliant").Count
            ComplianceRate  = if ($_.Count -gt 0) { [math]::Round(($osDevices | Where-Object ComplianceState -eq "compliant").Count / $_.Count * 100, 1) } else { 0 }
        }
    }

    return @{
        Total        = $total
        Compliant    = $compliant
        NonCompliant = $nonCompliant
        GracePeriod  = $gracePeriod
        Unknown      = $unknown
        ComplianceRate = if ($total -gt 0) { [math]::Round($compliant / $total * 100, 1) } else { 0 }
        ByOS         = $byOS
    }
}
#endregion

#region --- Report Generation ---
function Export-ComplianceHtml {
    param(
        [object[]]$Devices,
        [object[]]$Policies,
        [hashtable]$Stats,
        [string]$Path
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $rateColor = if ($Stats.ComplianceRate -ge 90) { "#107c10" } elseif ($Stats.ComplianceRate -ge 70) { "#ff8c00" } else { "#d13438" }

    $osRows = $Stats.ByOS | ForEach-Object {
        $rateClr = if ($_.ComplianceRate -ge 90) { "#107c10" } elseif ($_.ComplianceRate -ge 70) { "#ff8c00" } else { "#d13438" }
        "<tr><td>$($_.OS)</td><td>$($_.Total)</td><td>$($_.Compliant)</td><td>$($_.NonCompliant)</td><td style='color:$rateClr; font-weight:bold;'>$($_.ComplianceRate)%</td></tr>"
    }

    $deviceRows = $Devices | Sort-Object ComplianceState | ForEach-Object {
        $stateClass = switch ($_.ComplianceState) {
            "compliant"     { "state-compliant" }
            "noncompliant"  { "state-noncompliant" }
            "inGracePeriod" { "state-grace" }
            default         { "state-unknown" }
        }
        "<tr class='$stateClass'><td>$($_.DeviceName)</td><td>$($_.UserPrincipalName)</td><td>$($_.OperatingSystem)</td><td>$($_.OSVersion)</td><td>$($_.ComplianceState)</td><td>$($_.LastSyncDateTime)</td><td>$($_.IsEncrypted)</td></tr>"
    }

    $policyRows = $Policies | ForEach-Object {
        "<tr><td>$($_.PolicyName)</td><td>$($_.Description)</td><td>$($_.LastModifiedDateTime)</td></tr>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Intune Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 2rem; background: #f5f5f5; color: #333; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 0.5rem; }
        h2 { color: #106ebe; margin-top: 2rem; }
        table { border-collapse: collapse; width: 100%; margin: 1rem 0; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 10px 14px; text-align: left; font-size: 0.85rem; }
        th { background: #0078d4; color: #fff; }
        tr:hover { background: #e8f0fe; }
        .cards { display: flex; gap: 1rem; flex-wrap: wrap; margin: 1rem 0; }
        .card { background: #fff; padding: 1rem 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); min-width: 140px; border-top: 4px solid #0078d4; }
        .card .num { font-size: 2.2rem; font-weight: bold; color: #0078d4; }
        .card.green .num { color: #107c10; }
        .card.green { border-top-color: #107c10; }
        .card.red .num { color: #d13438; }
        .card.red { border-top-color: #d13438; }
        .card.orange .num { color: #ff8c00; }
        .card.orange { border-top-color: #ff8c00; }
        .state-noncompliant { border-left: 4px solid #d13438; }
        .state-grace { border-left: 4px solid #ff8c00; }
        .state-unknown { border-left: 4px solid #888; }
        .state-compliant { border-left: 4px solid #107c10; }
        .timestamp { color: #888; font-size: 0.85rem; }
        .rate-badge { display: inline-block; font-size: 2.2rem; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Intune Device Compliance Report</h1>
    <p class="timestamp">Generated: $timestamp</p>

    <div class="cards">
        <div class="card"><div class="num">$($Stats.Total)</div>Total Devices</div>
        <div class="card green"><div class="num">$($Stats.Compliant)</div>Compliant</div>
        <div class="card red"><div class="num">$($Stats.NonCompliant)</div>Non-Compliant</div>
        <div class="card orange"><div class="num">$($Stats.GracePeriod)</div>In Grace Period</div>
        <div class="card"><div class="num">$($Stats.Unknown)</div>Unknown</div>
        <div class="card" style="border-top-color: $rateColor;"><div class="rate-badge" style="color: $rateColor;">$($Stats.ComplianceRate)%</div>Compliance Rate</div>
    </div>

    <h2>Compliance by OS</h2>
    <table>
        <tr><th>Operating System</th><th>Total</th><th>Compliant</th><th>Non-Compliant</th><th>Compliance Rate</th></tr>
        $($osRows -join "`n        ")
    </table>

    <h2>Device Details</h2>
    <table>
        <tr><th>Device Name</th><th>User</th><th>OS</th><th>Version</th><th>Compliance State</th><th>Last Sync</th><th>Encrypted</th></tr>
        $($deviceRows -join "`n        ")
    </table>

    <h2>Compliance Policies</h2>
    <table>
        <tr><th>Policy Name</th><th>Description</th><th>Last Modified</th></tr>
        $($policyRows -join "`n        ")
    </table>

    <hr style="margin-top: 3rem; border: none; border-top: 1px solid #ddd;">
    <p class="timestamp">IntuneOps &mdash; Compliance Reporter v1.0.0</p>
</body>
</html>
"@

    $html | Out-File -FilePath $Path -Encoding utf8
    Write-Host "  HTML report: $Path" -ForegroundColor Green
}
#endregion

#region --- Main ---
function Invoke-ComplianceReport {
    Write-Host "`n=== IntuneOps: Compliance Reporter ===" -ForegroundColor Cyan
    Write-Host ""

    # Connect
    if (-not (Connect-ToGraph -TenantId $TenantId)) { return }

    # Collect data
    Write-Host "`nCollecting data..." -ForegroundColor Cyan
    $devices  = Get-ManagedDevicesCompliance -Filter $Filter -OS $OS -Top $Top
    $policies = Get-CompliancePolicies

    if ($devices.Count -eq 0) {
        Write-Warning "No devices found with the specified filters."
        return
    }

    # Statistics
    $stats = Get-ComplianceStats -Devices $devices

    # Console summary
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host "  Total devices    : $($stats.Total)"
    Write-Host "  Compliant        : $($stats.Compliant)" -ForegroundColor Green
    Write-Host "  Non-Compliant    : $($stats.NonCompliant)" -ForegroundColor Red
    Write-Host "  Grace Period     : $($stats.GracePeriod)" -ForegroundColor Yellow
    Write-Host "  Unknown          : $($stats.Unknown)"
    Write-Host "  Compliance Rate  : $($stats.ComplianceRate)%" -ForegroundColor $(if ($stats.ComplianceRate -ge 90) { "Green" } elseif ($stats.ComplianceRate -ge 70) { "Yellow" } else { "Red" })

    # Ensure output dir
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    # Export
    if ($OutputFormat -in @("HTML", "Both")) {
        $htmlPath = Join-Path $OutputPath "ComplianceReport_$timestamp.html"
        Export-ComplianceHtml -Devices $devices -Policies $policies -Stats $stats -Path $htmlPath
    }

    if ($OutputFormat -in @("CSV", "Both")) {
        $csvPath = Join-Path $OutputPath "ComplianceDevices_$timestamp.csv"
        $devices | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
        Write-Host "  CSV report: $csvPath" -ForegroundColor Green
    }

    Write-Host "`nDone." -ForegroundColor Green
}

# Run
Invoke-ComplianceReport
#endregion
