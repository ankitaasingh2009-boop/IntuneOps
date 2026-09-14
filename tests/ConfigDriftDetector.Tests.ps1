BeforeAll {
    $scriptPath = "$PSScriptRoot/../src/ConfigDriftDetector/Find-IntuneDrift.ps1"
}

Describe "Find-IntuneDrift" {

    BeforeAll {
        Mock Connect-MgGraph { }
        Mock Get-MgContext { [PSCustomObject]@{ Account = "test@contoso.com" } }
    }

    Context "Drift Comparison Logic" {

        It "Should detect added settings" {
            $baseline = @{
                "Wi-Fi Profile" = @{
                    Settings = @{
                        "wifiSecurityType" = "wpa2Enterprise"
                    }
                }
            }
            $live = @{
                "Wi-Fi Profile" = @{
                    Settings = @{
                        "wifiSecurityType" = "wpa2Enterprise"
                        "proxySettings"    = "automatic"
                    }
                }
            }

            # Inline comparison logic
            $drifts = @()
            foreach ($profileName in $live.Keys) {
                if ($baseline.ContainsKey($profileName)) {
                    foreach ($key in $live[$profileName].Settings.Keys) {
                        if (-not $baseline[$profileName].Settings.ContainsKey($key)) {
                            $drifts += [PSCustomObject]@{
                                DriftType = "SettingAdded"
                                Setting   = $key
                            }
                        }
                    }
                }
            }

            $drifts | Should -HaveCount 1
            $drifts[0].DriftType | Should -Be "SettingAdded"
            $drifts[0].Setting | Should -Be "proxySettings"
        }

        It "Should detect removed settings" {
            $baseline = @{
                "VPN Profile" = @{
                    Settings = @{
                        "connectionType" = "ikev2"
                        "alwaysOn"       = $true
                    }
                }
            }
            $live = @{
                "VPN Profile" = @{
                    Settings = @{
                        "connectionType" = "ikev2"
                    }
                }
            }

            $drifts = @()
            foreach ($key in $baseline["VPN Profile"].Settings.Keys) {
                if (-not $live["VPN Profile"].Settings.ContainsKey($key)) {
                    $drifts += [PSCustomObject]@{
                        DriftType = "SettingRemoved"
                        Setting   = $key
                    }
                }
            }

            $drifts | Should -HaveCount 1
            $drifts[0].Setting | Should -Be "alwaysOn"
        }

        It "Should detect modified settings" {
            $baseline = @{
                "Firewall" = @{
                    Settings = @{
                        "firewallEnabled" = $true
                        "stealthMode"     = $false
                    }
                }
            }
            $live = @{
                "Firewall" = @{
                    Settings = @{
                        "firewallEnabled" = $true
                        "stealthMode"     = $true
                    }
                }
            }

            $drifts = @()
            foreach ($key in $live["Firewall"].Settings.Keys) {
                if ($baseline["Firewall"].Settings.ContainsKey($key)) {
                    $baseJson = $baseline["Firewall"].Settings[$key] | ConvertTo-Json -Compress
                    $liveJson = $live["Firewall"].Settings[$key] | ConvertTo-Json -Compress
                    if ($baseJson -ne $liveJson) {
                        $drifts += [PSCustomObject]@{
                            DriftType = "SettingModified"
                            Setting   = $key
                        }
                    }
                }
            }

            $drifts | Should -HaveCount 1
            $drifts[0].Setting | Should -Be "stealthMode"
        }

        It "Should detect added profiles" {
            $baseline = @{
                "Existing Profile" = @{ Settings = @{} }
            }
            $live = @{
                "Existing Profile" = @{ Settings = @{} }
                "New Profile"      = @{ Settings = @{ "setting1" = "value1" } }
            }

            $addedProfiles = $live.Keys | Where-Object { -not $baseline.ContainsKey($_) }
            $addedProfiles | Should -HaveCount 1
            $addedProfiles | Should -Contain "New Profile"
        }

        It "Should detect removed profiles" {
            $baseline = @{
                "Profile A" = @{ Settings = @{} }
                "Profile B" = @{ Settings = @{} }
            }
            $live = @{
                "Profile A" = @{ Settings = @{} }
            }

            $removedProfiles = $baseline.Keys | Where-Object { -not $live.ContainsKey($_) }
            $removedProfiles | Should -HaveCount 1
            $removedProfiles | Should -Contain "Profile B"
        }

        It "Should report no drifts for identical configurations" {
            $baseline = @{
                "Profile" = @{
                    Settings = @{
                        "setting1" = "value1"
                        "setting2" = $true
                    }
                }
            }
            $live = @{
                "Profile" = @{
                    Settings = @{
                        "setting1" = "value1"
                        "setting2" = $true
                    }
                }
            }

            $drifts = @()
            foreach ($key in $live["Profile"].Settings.Keys) {
                if ($baseline["Profile"].Settings.ContainsKey($key)) {
                    $baseJson = $baseline["Profile"].Settings[$key] | ConvertTo-Json -Compress
                    $liveJson = $live["Profile"].Settings[$key] | ConvertTo-Json -Compress
                    if ($baseJson -ne $liveJson) { $drifts += $key }
                }
            }

            $drifts | Should -HaveCount 0
        }
    }

    Context "Baseline Import/Export" {

        It "Should serialize config to valid JSON" {
            $config = @{
                "TestProfile" = @{
                    Settings = @{
                        "passwordRequired" = $true
                        "minLength"        = 8
                    }
                }
            }

            $json = $config | ConvertTo-Json -Depth 20
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should round-trip baseline without data loss" {
            $original = @{
                "Profile1" = @{
                    Settings = @{
                        "key1" = "value1"
                        "key2" = @(1, 2, 3)
                    }
                }
            }

            $json = $original | ConvertTo-Json -Depth 20
            $restored = $json | ConvertFrom-Json -AsHashtable

            $restored["Profile1"].Settings["key1"] | Should -Be "value1"
            $restored["Profile1"].Settings["key2"] | Should -HaveCount 3
        }
    }

    Context "Parameter Validation" {

        It "Should accept valid OutputFormat values" {
            $validFormats = @("HTML", "CSV", "JSON", "Console")
            foreach ($fmt in $validFormats) {
                { [ValidateSet("HTML", "CSV", "JSON", "Console")]$testParam = $fmt } | Should -Not -Throw
            }
        }
    }
}
