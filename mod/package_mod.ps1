# FSTel FS25 Mod Packaging & Deployment Script
# Zips modDesc.xml, FSTelTelemetry.lua, and icon.png directly into FS25_FSTel.zip

$modSourceDir = "d:\Documents\Agv\fs25buttonbox\mod\FS25_FSTel"
$zipOutput = "d:\Documents\Agv\fs25buttonbox\mod\FS25_FSTel.zip"
$fs25ModsDir = "D:\Documents\My Games\FarmingSimulator2025\mods"

Write-Host "[FSTel] Packaging FS25_FSTel mod..." -ForegroundColor Cyan

# Remove old zip if exists
if (Test-Path $zipOutput) {
    Remove-Item -Force $zipOutput
}

# Ensure icon exists
if (-not (Test-Path "$modSourceDir\icon.png")) {
    Write-Host "[FSTel] Generating icon..." -ForegroundColor Yellow
    & "$modSourceDir\generate_icon.ps1"
}

$filesToZip = @(
    "$modSourceDir\modDesc.xml",
    "$modSourceDir\FSTelTelemetry.lua",
    "$modSourceDir\icon.png"
)

Compress-Archive -Path $filesToZip -DestinationPath $zipOutput -Force
Write-Host "[FSTel] Successfully created archive: $zipOutput" -ForegroundColor Green

# Deploy to game directory if found
if (Test-Path $fs25ModsDir) {
    $targetModFile = Join-Path $fs25ModsDir "FS25_FSTel.zip"
    Copy-Item -Path $zipOutput -Destination $targetModFile -Force
    Write-Host "[FSTel] Deployed directly to FS25 mods folder: $targetModFile" -ForegroundColor Magenta
} else {
    Write-Host "[FSTel] FS25 mods folder not found at: $fs25ModsDir" -ForegroundColor Yellow
}
