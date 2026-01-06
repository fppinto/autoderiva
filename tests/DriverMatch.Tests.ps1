Describe 'Driver Matching Logic' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile
    }

    Context 'Find-CompatibleDriver' {
        It 'Matches driver when HardwareID intersects strictly (ignoring case)' {
            $inventory = @(
                [PSCustomObject]@{ HardwareIDs = 'PCI\VEN_8086&DEV_1234'; DriverId = 'D1' }
                [PSCustomObject]@{ HardwareIDs = 'PCI\VEN_10DE&DEV_9999'; DriverId = 'D2' }
            )
            $systemIds = @('PCI\VEN_8086&DEV_1234')

            $matches = Find-CompatibleDriver -DriverInventory $inventory -SystemHardwareIds $systemIds
            $matches.Count | Should -Be 1
            $matches[0].DriverId | Should -Be 'D1'
        }

        It 'Handles semicolon-separated HardwareIDs in inventory' {
            $inventory = @(
                [PSCustomObject]@{ HardwareIDs = 'PCI\A;PCI\B'; DriverId = 'D1' }
            )
            $systemIds = @('PCI\B')

            $matches = Find-CompatibleDriver -DriverInventory $inventory -SystemHardwareIds $systemIds
            $matches.Count | Should -Be 1
            $matches[0].DriverId | Should -Be 'D1'
        }

        It 'Returns empty if no intersection' {
             $inventory = @(
                [PSCustomObject]@{ HardwareIDs = 'PCI\A'; DriverId = 'D1' }
            )
            $systemIds = @('PCI\C')

            $matches = Find-CompatibleDriver -DriverInventory $inventory -SystemHardwareIds $systemIds
            $matches.Count | Should -Be 0
        }
    }

    Context 'Get-SystemHardware' {
        BeforeAll {
            Mock Write-Section {}
            Mock Write-AutoDerivaLog { Write-Host "LOG: $Message" }
            $Script:Test_GetSystemHardware = $null
        }

        It 'Returns all active hardware IDs by default (AllDevices switch)' {
            $Script:Config = @{}
            Mock Get-PnpDevice {
                return @(
                    [PSCustomObject]@{ HardwareID = @('ID1'); InstanceId = 'ID1'; ConfigManagerErrorCode = 0; PNPDeviceID='ID1' }
                    [PSCustomObject]@{ HardwareID = @('ID2'); InstanceId = 'ID2'; ConfigManagerErrorCode = 0; PNPDeviceID='ID2' }
                )
            }

            # Use -AllDevices to bypass config logic and ensure we test basic retrieval
            $result = @(Get-SystemHardware -AllDevices)
            
            Assert-MockCalled Get-PnpDevice

            $result.Count | Should -Be 2
            $result | Should -Contain 'ID1'
            $result | Should -Contain 'ID2'
        }

        It 'Filters by Missing Drivers directly using Get-CimInstance when ScanOnlyMissingDrivers is set' {
            $Script:Config = @{ ScanOnlyMissingDrivers = $true }

            # Mock Get-MissingDriverDevicesDirect MUST return objects with HardwareID
            Mock Get-MissingDriverDevicesDirect {
                 return @(
                    [PSCustomObject]@{ HardwareID = @('BADDEV'); InstanceId = 'BADDEV'; ConfigManagerErrorCode = 28; PNPDeviceID='BADDEV' }
                 )
            }

            $result = @(Get-SystemHardware)
            
            Assert-MockCalled Get-MissingDriverDevicesDirect

            $result.Count | Should -Be 1
            $result[0] | Should -Be 'BADDEV'
        }

        It 'Falls back to Get-PnpDevice + Get-MissingDriverDevice if direct query fails (ProblemCode 28)' {
             $Script:Config = @{ ScanOnlyMissingDrivers = $true }

            Mock Get-MissingDriverDevicesDirect { return $null }

            # Mock Get-PnpDevice with InstanceId
            Mock Get-PnpDevice {
                return @(
                    [PSCustomObject]@{ HardwareID = @('GoodDev'); InstanceId = 'GoodDev'; ConfigManagerErrorCode = 0; PNPDeviceID='GoodDev' }
                    [PSCustomObject]@{ HardwareID = @('BadDev'); InstanceId = 'BadDev'; ConfigManagerErrorCode = 28; PNPDeviceID='BadDev' }
                )
            } -ParameterFilter { $PresentOnly }

            # Mock Get-CimInstance for Get-MissingDriverDevice
            Mock Get-CimInstance {
                return @(
                    [PSCustomObject]@{ PNPDeviceID = 'BadDev'; ConfigManagerErrorCode = 28 }
                )
            } -ParameterFilter { $ClassName -eq 'Win32_PnPEntity' }

            $result = @(Get-SystemHardware)
            $result.Count | Should -Be 1
            $result[0] | Should -Be 'BADDEV'
        }

        It 'Filters by ProblemCodes when configured' {
            $Script:Config = @{ 
                ScanOnlyProblemDevices = $true 
                ProblemDeviceCodes = @(10, 43)
            }

            Mock Get-MissingDriverDevicesDirect { return $null }
            
            Mock Get-PnpDevice {
                return @(
                    [PSCustomObject]@{ HardwareID = @('Error10'); InstanceId = 'Error10'; ConfigManagerErrorCode = 10; PNPDeviceID='Error10' }
                    [PSCustomObject]@{ HardwareID = @('Error43'); InstanceId = 'Error43'; ConfigManagerErrorCode = 43; PNPDeviceID='Error43' }
                    [PSCustomObject]@{ HardwareID = @('Working'); InstanceId = 'Working'; ConfigManagerErrorCode = 0; PNPDeviceID='Working'  }
                )
            }

            Mock Get-CimInstance {
                return @(
                    [PSCustomObject]@{ PNPDeviceID = 'Error10'; ConfigManagerErrorCode = 10 }
                    [PSCustomObject]@{ PNPDeviceID = 'Error43'; ConfigManagerErrorCode = 43 }
                )
            }

            $result = @(Get-SystemHardware)
            $result.Count | Should -Be 2
            $result | Should -Contain 'ERROR10'
            $result | Should -Contain 'ERROR43'
        }
    }
}
