[CmdletBinding()]
param(
    [string]$ProjectRoot = "."
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$assetsDir = Join-Path (Split-Path -Parent $scriptDir) "assets"

if (-not (Test-Path $ProjectRoot)) {
    New-Item -ItemType Directory -Path $ProjectRoot | Out-Null
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path

$dirs = @("data-sources", "scripts", "qvds", "documentation", "tests")

foreach ($d in $dirs) {
    $targetDir = Join-Path $ProjectRoot $d
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir | Out-Null
        Write-Host "Created: $targetDir"
    } else {
        Write-Host "Exists:  $targetDir"
    }

    $targetReadme = Join-Path $targetDir "README.md"
    $sourceReadme = Join-Path $assetsDir "$d-README.md"
    if (-not (Test-Path $targetReadme)) {
        if (Test-Path $sourceReadme) {
            Copy-Item -Path $sourceReadme -Destination $targetReadme
            Write-Host "Wrote:   $targetReadme"
        } else {
            Write-Warning "Template missing: $sourceReadme (skipped README)"
        }
    } else {
        Write-Host "Kept:    $targetReadme (existing file preserved)"
    }
}

Write-Host ""
Write-Host "Scaffold complete in: $ProjectRoot"
