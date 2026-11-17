#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
}

$OutZip = Join-Path $ProjectRoot "Gen5W-Theme-Studio-Redistributable.zip"
$StageDir = Join-Path $ProjectRoot "build\redist_stage\Gen5WThemeStudio"

if (Test-Path (Join-Path $ProjectRoot "build\redist_stage")) {
    Remove-Item (Join-Path $ProjectRoot "build\redist_stage") -Recurse -Force
}
if (Test-Path $OutZip) {
    Remove-Item $OutZip -Force
}

New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

Write-Host "==> Staging clean redistributable package in $StageDir..." -ForegroundColor Cyan

# 1. Root files
foreach ($rootFile in @("Start-ThemeStudio.bat", "Start-ThemeStudio.command", "Dockerfile", ".dockerignore", "compose.yaml", "README-INSTRUCTIONS.txt", "README.md", "CHANGELOG.md", "THIRD_PARTY_LICENSES.txt")) {
    $rPath = Join-Path $ProjectRoot $rootFile
    if (Test-Path $rPath) {
        Copy-Item $rPath (Join-Path $StageDir $rootFile) -Force
    }
}

# 2. Standalone tools/ (cwebp, dwebp, zipalign, Gen5WThemer-base.apk, signing cert, byte-offset patch table)
Copy-Item (Join-Path $ProjectRoot "tools") (Join-Path $StageDir "tools") -Recurse -Force

# 3. Scripts
New-Item -ItemType Directory -Force -Path (Join-Path $StageDir "scripts") | Out-Null
foreach ($scr in @("start-theme-studio.ps1", "generate-lcars-theme.ps1", "build-nemesis-package.ps1", "package-for-distribution.ps1")) {
    $srcPath = Join-Path $ProjectRoot "scripts\$scr"
    if (Test-Path $srcPath) {
        Copy-Item $srcPath (Join-Path $StageDir "scripts\$scr") -Force
    }
}

# 4. NEMESIS descriptors & root helper service
Copy-Item (Join-Path $ProjectRoot "nemesis-package") (Join-Path $StageDir "nemesis-package") -Recurse -Force
Copy-Item (Join-Path $ProjectRoot "nemesis-usb") (Join-Path $StageDir "nemesis-usb") -Recurse -Force

# 5. Android app source & new launcher icon (without large generated assets)
New-Item -ItemType Directory -Force -Path (Join-Path $StageDir "app\src\main") | Out-Null
Copy-Item (Join-Path $ProjectRoot "app\src\main\AndroidManifest.xml") (Join-Path $StageDir "app\src\main\AndroidManifest.xml") -Force
Copy-Item (Join-Path $ProjectRoot "app\src\main\java") (Join-Path $StageDir "app\src\main\java") -Recurse -Force
Copy-Item (Join-Path $ProjectRoot "app\src\main\res") (Join-Path $StageDir "app\src\main\res") -Recurse -Force

# 6. Studio web app and default stock-oem theme (Zero OEM files distributed)
New-Item -ItemType Directory -Force -Path (Join-Path $StageDir "studio\custom-assets") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $StageDir "studio\themes\stock-oem\assets") | Out-Null
Copy-Item (Join-Path $ProjectRoot "studio\index.html") (Join-Path $StageDir "studio\index.html") -Force
Copy-Item (Join-Path $ProjectRoot "studio\themes\stock-oem\theme-config.json") (Join-Path $StageDir "studio\theme-config.json") -Force
Copy-Item (Join-Path $ProjectRoot "studio\themes\stock-oem\theme-config.json") (Join-Path $StageDir "studio\themes\stock-oem\theme-config.json") -Force
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $StageDir "studio\themes\active-theme.txt"), "stock-oem", $utf8NoBom)

# 7. Empty dist/ directory ready for builds
New-Item -ItemType Directory -Force -Path (Join-Path $StageDir "dist") | Out-Null

Write-Host "==> Compressing to $OutZip..." -ForegroundColor Cyan
[System.IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $ProjectRoot "build\redist_stage"), $OutZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)

Remove-Item (Join-Path $ProjectRoot "build\redist_stage") -Recurse -Force
$zipSizeMB = [math]::Round(((Get-Item $OutZip).Length / 1MB), 2)
Write-Host "SUCCESS: Created $OutZip ($zipSizeMB MB)" -ForegroundColor Green
