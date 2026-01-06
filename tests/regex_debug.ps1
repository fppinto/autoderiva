
$line = "    All User Profile     : NETWORK_A"
$m = [regex]::Match($line, 'All\s+User\s+Profile\s*:\s*(.+)$')
Write-Host "Match Success: $($m.Success)"
if ($m.Success) {
    Write-Host "Value: '$($m.Groups[1].Value)'"
}
