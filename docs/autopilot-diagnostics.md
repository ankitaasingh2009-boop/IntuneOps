# Autopilot Diagnostics Collector

## Overview

Collects Windows Autopilot diagnostic data from Microsoft Intune via Microsoft Graph SDK.

## What It Collects

- **Device Identities** — serial, manufacturer, model, group tag, enrollment state, profile assignment status
- **Deployment Profiles** — OOBE settings, device name templates, hardware hash extraction
- **Enrollment Status Page (ESP)** — progress display, blocking behavior, timeouts, error messages
- **Enrollment Failures** — recent failures with correlation IDs for troubleshooting

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TenantId` | String | (current) | Azure AD tenant ID |
| `-OutputPath` | String | `.` | Output directory |
| `-OutputFormat` | String | `Both` | `HTML`, `CSV`, or `Both` |
| `-DeviceSerial` | String | (all) | Filter to specific serial number |
| `-DaysBack` | Int | `7` | Days to look back for enrollment failures |

## Graph Permissions

- `DeviceManagementServiceConfig.Read.All`
- `DeviceManagementManagedDevices.Read.All`

## Examples

```powershell
# Full diagnostic run
.\Get-AutopilotDiagnostics.ps1

# Specific device, last 30 days of failures
.\Get-AutopilotDiagnostics.ps1 -DeviceSerial "SN-001" -DaysBack 30

# CSV only, custom output path
.\Get-AutopilotDiagnostics.ps1 -OutputFormat CSV -OutputPath C:\Reports
```

## Output

- `AutopilotDiagnostics_<timestamp>.html` — full HTML dashboard
- `AutopilotDevices_<timestamp>.csv` — device identity data as CSV
