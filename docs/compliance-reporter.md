# Compliance Reporter

## Overview

Generates a comprehensive Intune device compliance report with summary statistics, per-OS breakdown, and device-level detail.

## What It Reports

- **Compliance state** for every managed device (compliant, non-compliant, grace period, unknown)
- **Per-OS statistics** — compliance rate by Windows, iOS, Android, macOS
- **Compliance policies** — all policies with last-modified dates
- **Device details** — name, user, OS version, encryption status, last sync

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TenantId` | String | (current) | Azure AD tenant ID |
| `-OutputPath` | String | `.` | Output directory |
| `-OutputFormat` | String | `Both` | `HTML`, `CSV`, or `Both` |
| `-Filter` | String | `All` | `All`, `Compliant`, `NonCompliant`, `InGracePeriod`, `Unknown` |
| `-OS` | String | `All` | `All`, `Windows`, `iOS`, `Android`, `macOS` |
| `-Top` | Int | (all) | Limit number of devices processed |

## Graph Permissions

- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementConfiguration.Read.All`

## Examples

```powershell
# Full compliance report
.\Get-ComplianceReport.ps1

# Non-compliant Windows devices only
.\Get-ComplianceReport.ps1 -Filter NonCompliant -OS Windows

# Quick CSV of top 50 devices
.\Get-ComplianceReport.ps1 -OutputFormat CSV -Top 50

# HTML only, custom path
.\Get-ComplianceReport.ps1 -OutputFormat HTML -OutputPath C:\Reports
```

## Output

- `ComplianceReport_<timestamp>.html` — dashboard with summary cards, OS breakdown, device table
- `ComplianceDevices_<timestamp>.csv` — flat device list for Excel/Power BI
