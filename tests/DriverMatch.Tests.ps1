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

    Context 'Compare-DriverVersion' {
        It 'Returns 0 for equal versions' {
            Compare-DriverVersion -VersionA '8.5.10101.6917' -VersionB '8.5.10101.6917' | Should -Be 0
        }

        It 'Returns 1 when A is greater' {
            Compare-DriverVersion -VersionA '8.7.10201.13396' -VersionB '8.5.10101.6917' | Should -Be 1
        }

        It 'Returns -1 when A is lesser' {
            Compare-DriverVersion -VersionA '8.5.10101.6917' -VersionB '8.7.10201.13396' | Should -Be -1
        }

        It 'Handles different segment counts' {
            Compare-DriverVersion -VersionA '22.100.0.3' -VersionB '20.100.10.6' | Should -Be 1
        }

        It 'Handles null versions' {
            Compare-DriverVersion -VersionA $null -VersionB '1.0' | Should -Be -1
            Compare-DriverVersion -VersionA '1.0' -VersionB $null | Should -Be 1
            Compare-DriverVersion -VersionA $null -VersionB $null | Should -Be 0
        }
    }

    Context 'Remove-DuplicateDriverVersions' {
        BeforeAll {
            Mock Write-Section {}
            Mock Write-AutoDerivaLog { Write-Host "LOG: $Message" }
        }

        It 'Keeps newest version when multiple drivers share HWIDs' {
            $drivers = @(
                [PSCustomObject]@{ FileName = 'dptf_acpi.inf'; InfPath = 'drivers\model\dptf-v8.5\dptf_acpi.inf'; HardwareIDs = 'ACPI\INT3400;ACPI\INT3401'; Version = '8.5.10101.6917'; Class = 'System' }
                [PSCustomObject]@{ FileName = 'dptf_acpi.inf'; InfPath = 'drivers\model\dptf-v8.7\dptf_acpi.inf'; HardwareIDs = 'ACPI\INT3400;ACPI\INT3401'; Version = '8.7.10201.13396'; Class = 'System' }
            )

            $result = @(Remove-DuplicateDriverVersions -DriverMatches $drivers)
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be '8.7.10201.13396'
        }

        It 'Keeps all drivers when HWIDs do not overlap' {
            $drivers = @(
                [PSCustomObject]@{ FileName = 'audio.inf'; InfPath = 'drivers\model\audio\audio.inf'; HardwareIDs = 'HDAUDIO\FUNC_01'; Version = '1.0'; Class = 'Media' }
                [PSCustomObject]@{ FileName = 'net.inf'; InfPath = 'drivers\model\net\net.inf'; HardwareIDs = 'PCI\VEN_8086&DEV_1234'; Version = '2.0'; Class = 'Net' }
            )

            $result = @(Remove-DuplicateDriverVersions -DriverMatches $drivers)
            $result.Count | Should -Be 2
        }

        It 'Returns input unchanged when only one driver' {
            $drivers = @(
                [PSCustomObject]@{ FileName = 'single.inf'; InfPath = 'drivers\model\single.inf'; HardwareIDs = 'PCI\A'; Version = '1.0'; Class = 'System' }
            )

            $result = @(Remove-DuplicateDriverVersions -DriverMatches $drivers)
            $result.Count | Should -Be 1
        }

        It 'Handles three versions, keeps only newest' {
            $drivers = @(
                [PSCustomObject]@{ FileName = 'drv.inf'; InfPath = 'drivers\m\v1\drv.inf'; HardwareIDs = 'ACPI\DEV1'; Version = '1.0.0.0'; Class = 'System' }
                [PSCustomObject]@{ FileName = 'drv.inf'; InfPath = 'drivers\m\v3\drv.inf'; HardwareIDs = 'ACPI\DEV1'; Version = '3.0.0.0'; Class = 'System' }
                [PSCustomObject]@{ FileName = 'drv.inf'; InfPath = 'drivers\m\v2\drv.inf'; HardwareIDs = 'ACPI\DEV1'; Version = '2.0.0.0'; Class = 'System' }
            )

            $result = @(Remove-DuplicateDriverVersions -DriverMatches $drivers)
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be '3.0.0.0'
        }
    }

    Context 'Select-ModelFromInventory' {
        BeforeAll {
            Mock Write-Section {}
            Mock Write-AutoDerivaLog { Write-Host "LOG: $Message" }
        }

        It 'Filters inventory by model when Config.Model is set' {
            $Script:Config = @{ Model = 'hp-240-g8' }
            $inventory = @(
                [PSCustomObject]@{ InfPath = 'drivers\hp-240-g8\bt\bt.inf'; ModelName = 'hp-240-g8'; HardwareIDs = 'USB\A' }
                [PSCustomObject]@{ InfPath = 'drivers\gw1-w149\audio\audio.inf'; ModelName = 'gw1-w149'; HardwareIDs = 'PCI\B' }
                [PSCustomObject]@{ InfPath = 'drivers\hp-240-g8\net\net.inf'; ModelName = 'hp-240-g8'; HardwareIDs = 'PCI\C' }
            )

            $result = @(Select-ModelFromInventory -DriverInventory $inventory)
            $result.Count | Should -Be 2
            $result | ForEach-Object { $_.ModelName | Should -Be 'hp-240-g8' }
        }

        It 'Returns full inventory when model not found' {
            $Script:Config = @{ Model = 'nonexistent-model' }
            $inventory = @(
                [PSCustomObject]@{ InfPath = 'drivers\hp-240-g8\bt.inf'; ModelName = 'hp-240-g8'; HardwareIDs = 'USB\A' }
            )

            $result = @(Select-ModelFromInventory -DriverInventory $inventory)
            $result.Count | Should -Be 1
        }

        It 'Returns full inventory when ScanAllModels behavior (no model set, fallback)' {
            $Script:Config = @{ Model = $null }
            Mock Read-Host { return '0' }
            $inventory = @(
                [PSCustomObject]@{ InfPath = 'drivers\hp-240-g8\bt.inf'; ModelName = 'hp-240-g8'; HardwareIDs = 'USB\A' }
                [PSCustomObject]@{ InfPath = 'drivers\gw1-w149\audio.inf'; ModelName = 'gw1-w149'; HardwareIDs = 'PCI\B' }
            )

            $result = @(Select-ModelFromInventory -DriverInventory $inventory)
            $result.Count | Should -Be 2
        }

        It 'Extracts model from InfPath when ModelName column is missing' {
            $Script:Config = @{ Model = 'hp-240-g8' }
            $inventory = @(
                [PSCustomObject]@{ InfPath = 'drivers\hp-240-g8\bt\bt.inf'; HardwareIDs = 'USB\A' }
                [PSCustomObject]@{ InfPath = 'drivers\gw1-w149\audio\audio.inf'; HardwareIDs = 'PCI\B' }
            )

            $result = @(Select-ModelFromInventory -DriverInventory $inventory)
            $result.Count | Should -Be 1
            $result[0].InfPath | Should -BeLike 'drivers\hp-240-g8\*'
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
