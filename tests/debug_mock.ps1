Describe 'Start-Process Mock Test' {
    It 'Mocks Start-Process with parameters' {
        Mock Start-Process { return [PSCustomObject]@{ ExitCode = 0 } }
        
        $p = Start-Process -FilePath "pnputil.exe" -ArgumentList "/foo" -NoNewWindow -Wait -PassThru
        $p.ExitCode | Should -Be 0
    }
}
