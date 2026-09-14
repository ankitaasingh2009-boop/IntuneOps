# Config Drift Detector

## Overview

Compares live Intune device configuration profiles against a saved JSON baseline to detect unauthorized or untracked changes.

## How It Works

1. **Export a baseline** — snapshot your current config profiles to a JSON file
2. **Detect drift** — re-run later against that baseline; the tool diffs every setting
3. **Review report** — drifts are categorized by severity (Critical / Warning / Info)

## Drift Types

| Drift Type | Severity | Meaning |
|------------|----------|---------|
| `ProfileAdded` | Info | New profile exists in live that wasn't in baseline |
| `ProfileRemoved` | Critical | Profile from baseline no longer exists |
| `SettingAdded` | Warning | New setting added to an existing profile |
| `SettingRemoved` | Warning | Setting from baseline removed from profile |
| `SettingModified` | Critical | Setting value changed from baseline |

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TenantId` | String | (current) | Azure AD tenant ID |
| `-BaselinePath` | String | — | Path to baseline JSON (required for detection) |
| `-ExportBaseline` | Switch | — | Export current state as new baseline |
| `-OutputPath` | String | `.` | Output directory |
| `-OutputFormat` | String | `HTML` | `HTML`, `CSV`, `JSON`, or `Console` |
| `-ProfileName` | String | (all) | Filter by profile name (supports wildcards) |

## Graph Permissions

- `DeviceManagementConfiguration.Read.All`

## Examples

```powershell
# Step 1: Save your baseline
.\Find-IntuneDrift.ps1 -ExportBaseline -OutputPath ./baselines

# Step 2: Later, detect drift
.\Find-IntuneDrift.ps1 -BaselinePath ./baselines/baseline_20260901.json

# Check a specific profile
.\Find-IntuneDrift.ps1 -BaselinePath ./baselines/baseline.json -ProfileName "Firewall*"

# Console output for quick checks
.\Find-IntuneDrift.ps1 -BaselinePath ./baselines/baseline.json -OutputFormat Console
```

## Output

- `DriftReport_<timestamp>.html` — color-coded drift dashboard
- `DriftReport_<timestamp>.csv` — tabular drift data
- `DriftReport_<timestamp>.json` — machine-readable drift data
- Console output — quick terminal summary
