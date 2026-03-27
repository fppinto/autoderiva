<#
.SYNOPSIS
    Extracts HP Softpaq .exe files from a folder and organises them for import into this repo.

.DESCRIPTION
    Scans a source folder for spXXXXXX.exe files, silently extracts each one,
    derives a slug from the CVA title (or INF class as fallback), and writes the
    extracted contents to:

        <OutputFolder>\drivers\spXXXXXX-<slug>\

    Run this on Windows, then copy the resulting 'drivers' folder into the repo.

.PARAMETER SourceFolder
    Folder that contains the spXXXXXX.exe files to process.
    Defaults to the current directory.

.PARAMETER OutputFolder
    Root folder where the 'drivers' subfolder will be created.
    Defaults to the current directory.

.EXAMPLE
    .\Expand-Softpaqs.ps1 -SourceFolder "C:\Downloads\HP 255 G7" -OutputFolder "C:\Staging"

.EXAMPLE
    .\Expand-Softpaqs.ps1
    # Runs in the current directory, outputs a 'drivers' subfolder alongside the exes.
#>

[CmdletBinding()]
param(
    [string]$SourceFolder = (Get-Location).Path,
    [string]$OutputFolder = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-CvaTitle {
    param([string]$CvaPath)
    $inTitle = $false
    foreach ($line in (Get-Content -Path $CvaPath -Encoding UTF8)) {
        if ($line -match '^\[Software Title\]') { $inTitle = $true; continue }
        if ($inTitle -and $line -match '^\[') { break }
        if ($inTitle -and $line -match '^US\s*=\s*(.+)') {
            return $matches[1].Trim()
        }
    }
    return $null
}

function Get-InfClass {
    param([string]$InfPath)
    foreach ($line in (Get-Content -Path $InfPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*Class\s*=\s*(.+)') {
            return $matches[1].Trim().Trim('"')
        }
    }
    return $null
}

function ConvertTo-Slug {
    param([string]$Text)
    $slug = $Text.ToLower()
    $slug = $slug -replace '[^a-z0-9\s-]', ''   # remove non-alphanumeric except spaces/hyphens
    $slug = $slug -replace '\s+', '-'             # spaces to hyphens
    $slug = $slug -replace '-{2,}', '-'           # collapse multiple hyphens
    $slug = $slug.Trim('-')
    return $slug
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$driversOut = Join-Path $OutputFolder 'drivers'
if (-not (Test-Path $driversOut)) { New-Item -ItemType Directory -Path $driversOut | Out-Null }

$exeFiles = Get-ChildItem -Path $SourceFolder -Filter 'sp*.exe' |
    Where-Object { $_.Name -match '^sp\d+\.exe$' }

if ($exeFiles.Count -eq 0) {
    Write-Host "No spXXXXXX.exe files found in: $SourceFolder" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($exeFiles.Count) softpaq(s) to process.`n" -ForegroundColor Cyan

$results = @()

foreach ($exe in $exeFiles) {
    $spNumber = [System.IO.Path]::GetFileNameWithoutExtension($exe.Name)  # e.g. sp96883
    Write-Host "Processing $($exe.Name)..." -ForegroundColor White

    # Extract to a temp folder
    $tempDir = Join-Path $env:TEMP "autoderiva_$spNumber"
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        $proc = Start-Process -FilePath $exe.FullName `
            -ArgumentList "-e -f `"$tempDir`" -s" `
            -Wait -PassThru -WindowStyle Hidden
    }
    catch {
        Write-Host "  ERROR: Could not launch $($exe.Name): $_" -ForegroundColor Red
        continue
    }

    # Give the extractor a moment to finish writing files
    Start-Sleep -Milliseconds 500

    if ((Get-ChildItem -Path $tempDir -Recurse -File).Count -eq 0) {
        Write-Host "  WARN: No files extracted from $($exe.Name) — skipping." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $tempDir
        continue
    }

    # --- Determine slug from CVA title ---
    $slug = $null
    $cva = Get-ChildItem -Path $tempDir -Filter '*.cva' -Recurse | Select-Object -First 1
    if ($cva) {
        $title = Get-CvaTitle -CvaPath $cva.FullName
        if ($title) { $slug = ConvertTo-Slug $title }
    }

    # Fallback: use the Class from the first INF found
    if (-not $slug) {
        $inf = Get-ChildItem -Path $tempDir -Filter '*.inf' -Recurse | Select-Object -First 1
        if ($inf) {
            $class = Get-InfClass -InfPath $inf.FullName
            if ($class) { $slug = ConvertTo-Slug $class }
        }
    }

    # Last resort: use the exe name as slug
    if (-not $slug) { $slug = $spNumber }

    $folderName = "$spNumber-$slug"
    $destDir = Join-Path $driversOut $folderName

    if (Test-Path $destDir) {
        Write-Host "  WARN: Destination already exists, overwriting: $folderName" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $destDir
    }

    Copy-Item -Path $tempDir -Destination $destDir -Recurse
    Remove-Item -Recurse -Force $tempDir

    $fileCount = (Get-ChildItem -Path $destDir -Recurse -File).Count
    $infCount  = (Get-ChildItem -Path $destDir -Filter '*.inf' -Recurse).Count

    Write-Host "  -> $folderName  ($fileCount files, $infCount .inf)" -ForegroundColor Green
    $results += [PSCustomObject]@{
        Softpaq   = $spNumber
        Folder    = $folderName
        Files     = $fileCount
        InfFiles  = $infCount
    }
}

Write-Host "`nDone. $($results.Count) softpaq(s) extracted to: $driversOut`n" -ForegroundColor Cyan
$results | Format-Table -AutoSize
