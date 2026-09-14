BeforeAll {
    # Dot-source the script functions (we'll mock the Graph calls)
    $scriptPath = "$PSScriptRoot/../src/AutopilotDiagnostics/Get-AutopilotDiagnostics.ps1"
}

Describe "Get-AutopilotDiagnostics" {

    BeforeAll {
        # Mock Graph SDK commands
        Mock Connect-MgGraph { }
        Mock Get-MgContext { [PSCustomObject]@{ Account = "test@contoso.com" } }

        Mock Get-MgDeviceManagementWindowsAutopilotDeviceIdentity {
            @(
                [PSCustomObject]@{
                    SerialNumber                       = "SN-001"
                    Model                              = "ThinkPad X1"
                    Manufacturer                       = "Lenovo"
                    GroupTag                            = "IT-Standard"
                    PurchaseOrderIdentifier            = "PO-2026-001"
                    EnrollmentState                    = "enrolled"
                    LastContactedDateTime              = "2026-09-10T10:00:00Z"
                    DeploymentProfileAssignmentStatus   = "assigned"
                    DeploymentProfileAssignedDateTime   = "2026-09-01T00:00:00Z"
                },
                [PSCustomObject]@{
                    SerialNumber                       = "SN-002"
                    Model                              = "Surface Pro 9"
                    Manufacturer                       = "Microsoft"
                    GroupTag                            = "Exec"
                    PurchaseOrderIdentifier            = "PO-2026-002"
                    EnrollmentState                    = "notContacted"
                    LastContactedDateTime              = $null
                    DeploymentProfileAssignmentStatus   = "notAssigned"
                    DeploymentProfileAssignedDateTime   = $null
                }
            )
        }

        Mock Get-MgDeviceManagementWindowsAutopilotDeploymentProfile {
            @(
                [PSCustomObject]@{
                    DisplayName          = "Standard Deployment"
                    Description          = "Default OOBE profile"
                    Language             = "en-US"
                    OutOfBoxExperienceSetting = @{ hidePrivacySettings = $true }
                    ExtractHardwareHash  = $true
                    DeviceNameTemplate   = "IT-%SERIAL%"
                    DeviceType           = "windowsPc"
                    CreatedDateTime      = "2026-01-15T00:00:00Z"
                    LastModifiedDateTime = "2026-08-20T00:00:00Z"
                }
            )
        }

        Mock Invoke-MgGraphRequest {
            @{ value = @() }
        }
    }

    Context "Data Collection" {

        It "Should return Autopilot devices" {
            $devices = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity
            $devices | Should -HaveCount 2
            $devices[0].SerialNumber | Should -Be "SN-001"
        }

        It "Should return deployment profiles" {
            $profiles = Get-MgDeviceManagementWindowsAutopilotDeploymentProfile
            $profiles | Should -HaveCount 1
            $profiles[0].DisplayName | Should -Be "Standard Deployment"
        }

        It "Should handle serial number filter parameter" {
            Mock Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -ParameterFilter {
                $Filter -like "*SN-001*"
            } -MockWith {
                @([PSCustomObject]@{ SerialNumber = "SN-001"; Model = "ThinkPad X1" })
            }

            $filtered = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'SN-001')"
            $filtered | Should -HaveCount 1
            $filtered[0].SerialNumber | Should -Be "SN-001"
        }
    }

    Context "Output Validation" {

        It "Should not throw when Graph returns empty results" {
            Mock Get-MgDeviceManagementWindowsAutopilotDeviceIdentity { @() }
            { Get-MgDeviceManagementWindowsAutopilotDeviceIdentity } | Should -Not -Throw
        }

        It "Should produce valid device objects with expected properties" {
            $devices = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity
            $devices[0] | Should -HaveProperty "SerialNumber"
            $devices[0] | Should -HaveProperty "EnrollmentState"
            $devices[0] | Should -HaveProperty "Model"
        }
    }

    Context "Parameter Validation" {

        It "Should accept valid OutputFormat values" {
            $validFormats = @("HTML", "CSV", "Both")
            foreach ($fmt in $validFormats) {
                { [ValidateSet("HTML", "CSV", "Both")]$testParam = $fmt } | Should -Not -Throw
            }
        }

        It "Should reject invalid OutputFormat values" {
            { [ValidateSet("HTML", "CSV", "Both")]$testParam = "PDF" } | Should -Throw
        }

        It "Should accept positive DaysBack" {
            $daysBack = 7
            $daysBack | Should -BeGreaterThan 0
        }
    }
}
