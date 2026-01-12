Describe 'AutoDeriva Full Integration' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile

        function New-DummyFile {
            param($Path)
            $dir = Split-Path $Path -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            "DUMMY DATA" | Set-Content $Path -Force
        }
        
        # Hook for ConcurrentDownload to avoid runspaces in tests
        $Script:Test_InvokeConcurrentDownload = {
            param($FileList, $MaxConcurrency, $TestMode)
            foreach ($f in $FileList) {
                Invoke-DownloadFile -Url $f.Url -OutputPath $f.OutputPath
            }
        }

        function Set-Config {
            param($Name, $Value)
            if ($null -eq $Config) { $Config = @{} }
            $exists = $false
            if ($Config -is [hashtable]) {
                $Config[$Name] = $Value
                $exists = $true
            }
            elseif ($Config.PSObject.Properties.Match($Name).Count -gt 0) {
                $Config.$Name = $Value
                $exists = $true
            }
            if (-not $exists) {
                $Config | Add-Member -Name $Name -Value $Value -MemberType NoteProperty -Force
            }
        }
    }

    Context 'Happy Path: Single Driver Install' {
        BeforeAll {
            Mock Write-Host {} 
            Mock Write-AutoDerivaLog { }
            Mock Test-PreFlight { return $true }
            Mock Invoke-PerformanceTuning {}
            Mock Clear-WifiProfile {}
             
            Set-Config 'DownloadAllFiles' $false
            Set-Config 'DownloadCuco' $false
            Set-Config 'CheckDiskSpace' $false
            Set-Config 'BaseUrl' 'http://test/'
            Set-Config 'InventoryPath' 'inventory.csv'
            Set-Config 'ManifestPath' 'manifest.csv'
            Set-Config 'MaxConcurrentDownloads' 6
            Set-Config 'CucoTargetDir' 'C:\Temp'
            Set-Config 'CucoBinaryPath' 'cuco.exe'

            $script:mockInventoryCsv = @"
HardwareIDs,DriverId,Version,Date,Source,SourceUrl,InfPath
PCI\TEST\0001,driver-1,1.0.0.0,2021-01-01,File,,drivers/test/driver.inf
"@
            $script:mockManifestCsv = @"
AssociatedInf,RelativePath,Sha256,Bytes
drivers/test/driver.inf,drivers/test/driver.inf,dummyhash,100
drivers/test/driver.inf,drivers/test/driver.sys,dummyhash,100
"@
             
            Mock Get-RemoteCsv {
                param($Url)
                if ($Url -match 'inventory') { return ($script:mockInventoryCsv | ConvertFrom-Csv) }
                if ($Url -match 'manifest') { return ($script:mockManifestCsv | ConvertFrom-Csv) }
                return @()
            }

            Mock Get-SystemHardware {
                return @('PCI\TEST\0001')
            }

            Mock Invoke-DownloadFile {
                param($Url, $OutputPath)
                New-DummyFile -Path $OutputPath
                return $true
            }
            Mock Test-AutoDerivaFileHash { return $true }
            Mock Invoke-DownloadedFileHashVerification { return $null } 
            Mock Start-Process { return [PSCustomObject]@{ ExitCode = 0 } }
        }

        It 'Runs Main() and successfully installs one driver' {
            Main
            Assert-MockCalled Get-SystemHardware -Times 1
            Assert-MockCalled Get-RemoteCsv -Times 2 
            Assert-MockCalled Invoke-DownloadFile -Exactly 2
            Assert-MockCalled Start-Process -Times 1
        }
    }
}
