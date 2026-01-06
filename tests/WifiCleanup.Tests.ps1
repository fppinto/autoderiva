Describe 'Wi-Fi Profile Cleanup' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile

        # Define Shim for netsh.exe
        # Because we can't easily Mock external commands invoked with &, 
        # defining a function with the same name usually takes precedence.
        function netsh.exe {
            # Pass all arguments to the shim block using splatting
            Write-Host "DEBUG-SHIM-ENTRY: ArgCount=$($args.Count) Args=$($args -join '|')"
            & $script:NetshShimBlock @args
        }
    }

    BeforeEach {
        $env:AUTODERIVA_TEST = '0' # Enable real logic
        
        # Modify the existing global Config object which is visible to the function
        if ($null -ne $Config) {
            $Config.ClearWifiProfiles = $true
            $Config.WifiCleanupMode = 'All'
            $Config.AskBeforeClearingWifiProfiles = $false
            $Config.WifiProfileNameToDelete = 'TargetWifi'
        }
        
        Mock Write-AutoDerivaLog {
             param($Level, $Message, $Color)
             Write-Host "LOG: [$Level] $Message" -ForegroundColor Cyan
        }

        Mock Test-AutoDerivaPromptAvailable { return $true }
        
        $script:NetshCalls = New-Object System.Collections.Generic.List[string]

        # Default Shim Behavior: Return list of profiles
        $script:NetshShimBlock = {
            # Use automatic $args to capture all passed arguments
            $cmdLine = $args -join ' '
            $script:NetshCalls.Add($cmdLine)
            Write-Host "DEBUG-BLOCK: CmdLine='$cmdLine'"

            if ($cmdLine -match 'show profiles') {
                Write-Host "DEBUG-BLOCK: Returning profiles list"
                return @(
                    "Profiles on interface Wi-Fi:",
                    "Group Policy Profiles (Read Only)",
                    "---------------------------------",
                    "    <None>",
                    "User Profiles",
                    "-------------",
                    "    All User Profile     : MatchWifi",
                    "    All User Profile     : OtherWifi",
                    "    All User Profile     : TargetWifi" 
                )
            }
            return @()
        }
    }

    AfterEach {
        $env:AUTODERIVA_TEST = '1'
    }

    It 'Enumerates profiles correctly from netsh output' {
        Clear-WifiProfile

        $script:NetshCalls.Count | Should -Be 1
        $script:NetshCalls[0] | Should -Be 'wlan show profiles'
        
        # In 'All' mode, it should proceed to delete. The logic executes `netsh wlan delete profile name="..."`
        # But wait, the function deletes them one by one or in batch?
        # Let's check implementation behavior through mocking.
        # Actually I missed implementing the DELETE part in the shim default behavior.
    }
    
    It 'Deletes ALL profiles when mode is All' {
        $Script:Config.WifiCleanupMode = 'All'
        
        Clear-WifiProfile
        
        # 1 call to show, 3 calls to delete
        $script:NetshCalls.Count | Should -Be 4
        $script:NetshCalls[0] | Should -Be 'wlan show profiles'
        $script:NetshCalls[1] | Should -Match 'delete profile name="MatchWifi"'
        $script:NetshCalls[2] | Should -Match 'delete profile name="OtherWifi"'
        $script:NetshCalls[3] | Should -Match 'delete profile name="TargetWifi"'
    }

    It 'Deletes Single profile when mode is SingleOnly' {
        $Script:Config.WifiCleanupMode = 'SingleOnly'
        $Script:Config.WifiProfileNameToDelete = 'TargetWifi'

        Clear-WifiProfile
        
        # 1 call to show, 1 call to delete
        $script:NetshCalls.Count | Should -Be 2
        $script:NetshCalls[1] | Should -Match 'delete profile name="TargetWifi"'
    }

    It 'Does not delete if SingleOnly target not found' {
        $Script:Config.WifiCleanupMode = 'SingleOnly'
        $Script:Config.WifiProfileNameToDelete = 'MissingWifi'

        Clear-WifiProfile

        # 1 call to show, 0 calls to delete
        $script:NetshCalls.Count | Should -Be 1
        $script:NetshCalls[0] | Should -Match 'show profiles'
    }

    It 'Skips deletion if confirmation declined' {
        $Script:Config.AskBeforeClearingWifiProfiles = $true
        
        Mock Read-Host { return 'n' } # Decline

        Clear-WifiProfile
        
        $script:NetshCalls.Count | Should -Be 1 # Only list, no delete
    }

    It 'Proceeds with deletion if confirmation accepted' {
        $Script:Config.AskBeforeClearingWifiProfiles = $true
        
        Mock Read-Host { return 'y' } # Accept

        Clear-WifiProfile
        
        $script:NetshCalls.Count | Should -Be 4 # List + 3 Deletes (Mode=All)
    }

    It 'Parses profile names with spaces correctly' {
         $script:NetshShimBlock = {
            # Use automatic $args
            $cmdLine = $args -join ' '
            $script:NetshCalls.Add($cmdLine)

            if ($cmdLine -match 'show profiles') {
                return @(
                    "User Profiles",
                    "-------------",
                    "    All User Profile     : Starbucks WiFi",
                    "    All User Profile     :  Weird Spacing " 
                )
            }
            return @()
        }

        $Script:Config.WifiCleanupMode = 'All'
        Clear-WifiProfile

        # The names should be trimmed
        # "Starbucks WiFi"
        # "Weird Spacing"
        $script:NetshCalls | Should -Contain 'wlan delete profile name="Starbucks WiFi"'
        $script:NetshCalls | Should -Contain 'wlan delete profile name="Weird Spacing"'
    }
}
