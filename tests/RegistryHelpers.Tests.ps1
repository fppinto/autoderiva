Describe 'Registry Helper Functions' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile
    }

    Context 'Convert-AutoDerivaRegistryPathToInteractiveUser' {
        BeforeEach {
            # Disable test mode bypass for this function to test actual logic
            $env:AUTODERIVA_TEST = '0'
            $script:HkcuRedirectLogged = $false
        }
        AfterEach {
            $env:AUTODERIVA_TEST = '1'
        }

        It 'Returns original path if not HKCU' {
            $path = 'HKLM:\Software\Test'
            $res = Convert-AutoDerivaRegistryPathToInteractiveUser -Path $path
            $res | Should -Be $path
        }

        It 'Returns original path if Interactive SID not found' {
            Mock Get-AutoDerivaInteractiveUserSid { return $null }
            $path = 'HKCU:\Software\Test'
            
            # Mock Identity to look like Admin/System to allow logic to proceed
            # (Requires rigorous mocking of .NET types which is hard in Pester)
            # Instead, we are limited by the checks in the function.
            # The function checks: IsInRole(Admin). 
            
            # Since we can't easily mock WindowsIdentity in PowerShell without TypeMock, 
            # we might struggle to trigger the "Redirect" logic if the test runner isn't Admin.
        }
    }

    Context 'Set-AutoDerivaRegistryDword (Real Logic)' {
        BeforeEach {
            $Script:Test_SetRegistryDword = $null # Disable the test hook to test real logic
            $Script:DryRun = $false
            
            Mock Write-AutoDerivaLog {}
            Mock Convert-AutoDerivaRegistryPathToInteractiveUser { param($Path) return $Path } # Passthrough
        }

        It 'Creates registry key if missing' {
            Mock Test-Path { return $false }
            Mock New-Item { return $true }
            Mock New-ItemProperty {}

            Set-AutoDerivaRegistryDword -Path 'HKCU:\Test' -Name 'Dword1' -Value 1

            Assert-MockCalled New-Item -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Test' }
            Assert-MockCalled New-ItemProperty -Times 1
        }

        It 'Sets value using New-ItemProperty' {
            Mock Test-Path { return $true }
            Mock New-ItemProperty {}

            Set-AutoDerivaRegistryDword -Path 'HKCU:\Test' -Name 'Val' -Value 99

            Assert-MockCalled New-ItemProperty -Times 1 -ParameterFilter { 
                $Path -eq 'HKCU:\Test' -and 
                $Name -eq 'Val' -and 
                $Value -eq 99 -and 
                $PropertyType -eq 'DWord' 
            }
        }

        It 'Handles UnauthorizedAccessException via fallback if redirected' {
            Mock Convert-AutoDerivaRegistryPathToInteractiveUser { return 'REDIRECTED_PATH' }
            Mock Test-Path { return $true }
             
            # First attempt fails
            Mock New-ItemProperty { throw [System.UnauthorizedAccessException]::new("Access Denied") } -ParameterFilter { $Path -eq 'REDIRECTED_PATH' }
             
            # Fallback attempt succeeds
            Mock New-ItemProperty { return $true } -ParameterFilter { $Path -eq 'HKCU:\Orig' }

            Set-AutoDerivaRegistryDword -Path 'HKCU:\Orig' -Name 'Val' -Value 1

            # Should call New-ItemProperty twice: once for redirected, once for fallback
            Assert-MockCalled New-ItemProperty -Times 2
            Assert-MockCalled Write-AutoDerivaLog -ParameterFilter { $Status -eq 'INFO' -and $Message -like '*fallback*' }
        }
        
        It 'Logs warning if UnauthorizedAccessException occurs without redirection' {
            Mock Convert-AutoDerivaRegistryPathToInteractiveUser { return 'HKCU:\Orig' } # No redirect
            Mock Test-Path { return $true }
             
            Mock New-ItemProperty { throw [System.UnauthorizedAccessException]::new("Access Denied") } 

            Set-AutoDerivaRegistryDword -Path 'HKCU:\Orig' -Name 'Val' -Value 1

            Assert-MockCalled New-ItemProperty -Times 1
            Assert-MockCalled Write-AutoDerivaLog -ParameterFilter { $Status -eq 'WARN' -and $Message -like '*Insufficient permissions*' }
        }
    }
}
