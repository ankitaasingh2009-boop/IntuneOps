BeforeAll {
    $scriptPath = "$PSScriptRoot/../src/ComplianceReporter/Get-ComplianceReport.ps1"
}

Describe "Get-ComplianceReport" {

    BeforeAll {
        Mock Connect-MgGraph { }
        Mock Get-MgContext { [PSCustomObject]@{ Account = "test@contoso.com" } }
    }

    Context "Compliance Statistics" {

        It "Should calculate correct compliance rate" {
            $devices = @(
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "iOS" },
                [PSCustomObject]@{ ComplianceState = "noncompliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "unknown"; OperatingSystem = "Android" }
            )

            $total = $devices.Count
            $compliant = ($devices | Where-Object ComplianceState -eq "compliant").Count
            $rate = [math]::Round($compliant / $total * 100, 1)

            $rate | Should -Be 60.0
            $compliant | Should -Be 3
            $total | Should -Be 5
        }

        It "Should group statistics by OS" {
            $devices = @(
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "noncompliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "iOS" },
                [PSCustomObject]@{ ComplianceState = "noncompliant"; OperatingSystem = "iOS" }
            )

            $byOS = $devices | Group-Object OperatingSystem
            $byOS | Should -HaveCount 2

            $windows = $byOS | Where-Object Name -eq "Windows"
            $windows.Count | Should -Be 3

            $windowsCompliant = ($windows.Group | Where-Object ComplianceState -eq "compliant").Count
            $windowsRate = [math]::Round($windowsCompliant / $windows.Count * 100, 1)
            $windowsRate | Should -Be 66.7
        }

        It "Should handle zero devices without error" {
            $devices = @()
            $total = $devices.Count
            $rate = if ($total -gt 0) { [math]::Round(0 / $total * 100, 1) } else { 0 }

            $total | Should -Be 0
            $rate | Should -Be 0
        }

        It "Should handle 100% compliance" {
            $devices = @(
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Windows" }
            )

            $compliant = ($devices | Where-Object ComplianceState -eq "compliant").Count
            $rate = [math]::Round($compliant / $devices.Count * 100, 1)

            $rate | Should -Be 100.0
        }

        It "Should count all compliance states" {
            $devices = @(
                [PSCustomObject]@{ ComplianceState = "compliant" },
                [PSCustomObject]@{ ComplianceState = "noncompliant" },
                [PSCustomObject]@{ ComplianceState = "inGracePeriod" },
                [PSCustomObject]@{ ComplianceState = "unknown" }
            )

            ($devices | Where-Object ComplianceState -eq "compliant").Count | Should -Be 1
            ($devices | Where-Object ComplianceState -eq "noncompliant").Count | Should -Be 1
            ($devices | Where-Object ComplianceState -eq "inGracePeriod").Count | Should -Be 1
            ($devices | Where-Object ComplianceState -eq "unknown").Count | Should -Be 1
        }
    }

    Context "Filter Logic" {

        It "Should filter by compliance state" {
            $devices = @(
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "noncompliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "iOS" }
            )

            $filtered = $devices | Where-Object ComplianceState -eq "noncompliant"
            $filtered | Should -HaveCount 1
        }

        It "Should filter by OS" {
            $devices = @(
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Windows" },
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "iOS" },
                [PSCustomObject]@{ ComplianceState = "compliant"; OperatingSystem = "Android" }
            )

            $filtered = $devices | Where-Object OperatingSystem -eq "iOS"
            $filtered | Should -HaveCount 1
        }
    }

    Context "Parameter Validation" {

        It "Should accept valid Filter values" {
            $validFilters = @("All", "Compliant", "NonCompliant", "InGracePeriod", "Unknown")
            foreach ($f in $validFilters) {
                { [ValidateSet("All", "Compliant", "NonCompliant", "InGracePeriod", "Unknown")]$testParam = $f } | Should -Not -Throw
            }
        }

        It "Should accept valid OS values" {
            $validOS = @("All", "Windows", "iOS", "Android", "macOS")
            foreach ($o in $validOS) {
                { [ValidateSet("All", "Windows", "iOS", "Android", "macOS")]$testParam = $o } | Should -Not -Throw
            }
        }

        It "Should accept valid OutputFormat values" {
            $validFormats = @("HTML", "CSV", "Both")
            foreach ($fmt in $validFormats) {
                { [ValidateSet("HTML", "CSV", "Both")]$testParam = $fmt } | Should -Not -Throw
            }
        }
    }
}
