# IntuneOps

[![CI — Pester Tests](https://github.com/ankitaasingh2009-boop/IntuneOps/actions/workflows/ci.yml/badge.svg)](https://github.com/ankitaasingh2009-boop/IntuneOps/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-SDK-0078d4?logo=microsoft)](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)

**Open-source PowerShell toolkit for Intune operations** — Autopilot diagnostics, configuration drift detection, and compliance reporting, all powered by Microsoft Graph SDK.

Built for endpoint engineers, IT admins, and DEX teams managing enterprise fleets.

---

## Tools

| Tool | Script | What It Does |
|------|--------|-------------|
| **Autopilot Diagnostics** | `Get-AutopilotDiagnostics.ps1` | Collects Autopilot device identities, deployment profiles, ESP config, and enrollment failures. Exports HTML/CSV. |
| **Config Drift Detector** | `Find-IntuneDrift.ps1` | Compares live Intune device configuration profiles against a saved JSON baseline. Reports added/removed/modified settings with severity levels. |
| **Compliance Reporter** | `Get-ComplianceReport.ps1` | Pulls device compliance state across your fleet — filters by OS, compliance state. Generates a dashboard-style HTML report with stats. |

## Quick Start

### Prerequisites

- PowerShell 7+
- Microsoft.Graph PowerShell SDK

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

### Install

```powershell
git clone https://github.com/ankitaasingh2009-boop/IntuneOps.git
cd IntuneOps
```

### Usage

```powershell
# Autopilot diagnostics — full report
.\src\AutopilotDiagnostics\Get-AutopilotDiagnostics.ps1 -OutputFormat HTML

# Autopilot diagnostics — single device
.\src\AutopilotDiagnostics\Get-AutopilotDiagnostics.ps1 -DeviceSerial "SN-12345"

# Config drift — export baseline first
.\src\ConfigDriftDetector\Find-IntuneDrift.ps1 -ExportBaseline -OutputPath ./baselines

# Config drift — detect changes
.\src\ConfigDriftDetector\Find-IntuneDrift.ps1 -BaselinePath ./baselines/baseline_20260901.json

# Compliance report — non-compliant Windows devices
.\src\ComplianceReporter\Get-ComplianceReport.ps1 -Filter NonCompliant -OS Windows
```

## Graph Permissions

The scripts use `Connect-MgGraph` with these scopes:

| Scope | Used By |
|-------|---------|
| `DeviceManagementServiceConfig.Read.All` | Autopilot Diagnostics |
| `DeviceManagementManagedDevices.Read.All` | Autopilot Diagnostics, Compliance Reporter |
| `DeviceManagementConfiguration.Read.All` | Config Drift Detector, Compliance Reporter |

All scripts are **read-only** — they never modify your tenant.

## Project Structure

```
IntuneOps/
├── src/
│   ├── AutopilotDiagnostics/   # Get-AutopilotDiagnostics.ps1
│   ├── ConfigDriftDetector/    # Find-IntuneDrift.ps1
│   └── ComplianceReporter/     # Get-ComplianceReport.ps1
├── tests/                      # Pester 5 unit tests
├── docs/                       # Per-tool documentation
├── .github/workflows/          # CI pipeline
└── baselines/                  # (gitignored) your saved baselines
```

## Running Tests

```powershell
Install-Module Pester -MinimumVersion 5.0 -Force
Invoke-Pester ./tests/ -Output Detailed
```

## Reports

Each tool generates professional HTML reports with:
- Summary cards with key metrics
- Color-coded severity/state indicators
- Sortable device tables
- Timestamped output files

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE) — use it, fork it, improve it.

## Author

**Ankita Singh** — Senior Technical Architect | DEX & Endpoint Management
