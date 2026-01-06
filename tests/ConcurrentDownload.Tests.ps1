Describe 'Download Logic' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $script:ScriptFile = Join-Path $script:RepoRoot 'scripts\Install-AutoDeriva.ps1'
        $env:AUTODERIVA_TEST = '1'
        . $script:ScriptFile
    }

    Context 'Invoke-ConcurrentDownload (TestMode)' {
        BeforeEach {
            $Script:Stats = @{ FilesDownloaded = 0; FilesDownloadFailed = 0 }
            
            # Shim logging/progress to avoid errors and verify calls
            Mock Write-AutoDerivaLog {} 
            Mock Write-Progress {}
        }

        It 'Downloads files sequentially in TestMode' {
            $fileList = @(
                @{ Url = 'http://site/file1.txt'; OutputPath = 'C:\Temp\file1.txt' }
                @{ Url = 'http://site/file2.txt'; OutputPath = 'C:\Temp\file2.txt' }
            )

            # Mock individual file download to succeed
            Mock Invoke-DownloadFile { return $true }

            Invoke-ConcurrentDownload -FileList $fileList -MaxConcurrency 1 -TestMode

            Assert-MockCalled Invoke-DownloadFile -Times 2
            $Script:Stats.FilesDownloaded | Should -Be 2
            $Script:Stats.FilesDownloadFailed | Should -Be 0
        }

        It 'Handles failed downloads in TestMode' {
            $fileList = @(
                @{ Url = 'http://site/ok.txt'; OutputPath = 'C:\Temp\ok.txt' }
                @{ Url = 'http://site/fail.txt'; OutputPath = 'C:\Temp\fail.txt' }
            )

            Mock Invoke-DownloadFile {
                param($Url, $OutputPath)
                if ($Url -match 'fail') { return $false }
                return $true
            }

            Invoke-ConcurrentDownload -FileList $fileList -MaxConcurrency 1 -TestMode

            Assert-MockCalled Invoke-DownloadFile -Times 2
            $Script:Stats.FilesDownloaded | Should -Be 1
            $Script:Stats.FilesDownloadFailed | Should -Be 1
        }
        
        It 'Logs warning on failure' {
            $fileList = @(
                @{ Url = 'http://site/fail.txt'; OutputPath = 'C:\Temp\fail.txt' }
            )

            Mock Invoke-DownloadFile { return $false }
            Mock Write-AutoDerivaLog { param($Status, $Message, $Color) } 

            Invoke-ConcurrentDownload -FileList $fileList -MaxConcurrency 1 -TestMode
            
            # Verification using Pester 5 'Should -Invoke' is not always reliable if Mock scope differs, 
            # so we trust the Mock implementation or use Assert-MockCalled
            Assert-MockCalled Write-AutoDerivaLog -ParameterFilter { $Status -eq 'WARN' -and $Message -like '*Failed to download*' }
        }
    }
}
