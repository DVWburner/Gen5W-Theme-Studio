$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("Gen5W smoke " + [Guid]::NewGuid())
$server = $null
function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
}
function Post([string]$path, $body) {
    Invoke-RestMethod "http://127.0.0.1:18470$path" -Method Post -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 20) -TimeoutSec 180
}
try {
    New-Item -ItemType Directory -Path $work | Out-Null
    foreach ($dir in @("scripts", "tools", "nemesis-package", "nemesis-usb")) {
        Copy-Item (Join-Path $repo $dir) $work -Recurse
    }
    $stock = Join-Path $work "studio/themes/stock-oem"
    New-Item -ItemType Directory -Path $stock -Force | Out-Null
    Copy-Item (Join-Path $repo "studio/themes/stock-oem/theme-config.json") $stock
    Copy-Item (Join-Path $repo "studio/index.html") (Join-Path $work "studio")
    $exe = (Get-Process -Id $PID).Path
    $server = Start-Process $exe -ArgumentList @("-NoProfile", "-File", ('"' + (Join-Path $work "scripts/start-theme-studio.ps1") + '"'), "-NoBrowser", "-Port", "18470") -PassThru -RedirectStandardOutput (Join-Path $work "server.log") -RedirectStandardError (Join-Path $work "server-error.log")
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        try {
            $themes = Invoke-RestMethod "http://127.0.0.1:18470/api/themes" -TimeoutSec 2
            $ready = $true
            break
        } catch { $startupError = $_; Start-Sleep -Milliseconds 500 }
        if ($server.HasExited) { throw "Studio exited during startup" }
    }
    Assert $ready "Studio did not start: $startupError"
    Assert ($themes.activeTheme -eq "stock-oem") "Wrong default theme"
    $page = Invoke-WebRequest "http://127.0.0.1:18470/" -UseBasicParsing
    Assert ($page.Content -match "Theme Studio") "Studio HTML did not load"
    $cfg = Invoke-RestMethod "http://127.0.0.1:18470/api/config"
    $created = Post "/api/themes/create" @{ name = "Mac Smoke"; config = $cfg }
    Assert $created.ok "Theme creation failed"
    $id = $created.activeTheme

    $bitmap = New-Object System.Drawing.Bitmap(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::CornflowerBlue)
    $graphics.Dispose()
    foreach ($format in @("Png", "Jpeg")) {
        $file = Join-Path $work "upload.$format"
        $bitmap.Save($file, [System.Drawing.Imaging.ImageFormat]::$format)
        $mime = $format.ToLower()
        $data = "data:image/$mime;base64," + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file))
        $uploaded = Post "/api/upload-asset?slot=smoke_$mime" @{ dataUrl = $data }
        Assert $uploaded.ok "$format upload failed"
    }
    $bitmap.Dispose()
    $webp = Join-Path $work "upload.webp"
    $cwebp = if ($PSVersionTable.Platform -eq "Unix") { "cwebp" } else { Join-Path $repo "tools/cwebp.exe" }
    & $cwebp -quiet (Join-Path $work "upload.Png") -o $webp
    Assert ($LASTEXITCODE -eq 0) "WebP fixture encoding failed"
    $uploaded = Post "/api/upload-asset?slot=smoke_webp" @{ dataUrl = "data:image/webp;base64," + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($webp)) }
    Assert $uploaded.ok "WebP upload failed"

    $cfg = $created.config
    $font = if ($env:WINDIR) { Join-Path $env:WINDIR "Fonts/arial.ttf" } else { "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf" }
    $uploaded = Post "/api/upload-asset?slot=custom_font" @{ dataUrl = "data:font/ttf;base64," + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($font)) }
    Assert $uploaded.ok "Font upload failed"
    $cfg.homeScreen.fontFamily = "custom"
    $cfg.homeScreen.customFontFile = "custom_font.ttf"
    $cfg.homeScreen.bgMode = "custom"
    $cfg.homeScreen.customBgFile = "smoke_png.png"
    $cfg.allApps.bgMode = "lcars"
    $cfg.tile.style = "lcars"
    $cfg.statusBar.bgMode = "lcars"
    $cfg.climateScreen.bgMode = "lcars"
    $saved = Post "/api/save-config" $cfg
    Assert $saved.ok "Save failed"
    $pack = Join-Path $work "export.gen5wtheme"
    Invoke-WebRequest "http://127.0.0.1:18470/api/themes/export" -UseBasicParsing -OutFile $pack
    $imported = Post "/api/themes/import" @{ dataUrl = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pack)) }
    Assert ($imported.ok -and $imported.activeTheme -ne $id -and $imported.assetsExtracted -eq 4) "Theme round trip failed"

    $built = Post "/api/build-and-deploy" @{ config = $imported.config; selectedThemes = @($id, $imported.activeTheme) }
    Assert $built.ok "USB build failed"
    $usb = Join-Path $work "usb.zip"
    Invoke-WebRequest ("http://127.0.0.1:18470" + $built.downloadUrl) -UseBasicParsing -OutFile $usb
    $zip = [System.IO.Compression.ZipFile]::OpenRead($usb)
    try {
        Assert ($null -ne $zip.GetEntry("NEMESIS.data")) "USB descriptor missing"
        Assert ($null -ne $zip.GetEntry("packages/gen5w.nemesis.themer.zip")) "NEMESIS package missing"
    } finally { $zip.Dispose() }
    $apk = Join-Path $work "dist/Gen5WThemer.apk"
    $zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
    try {
        Assert ($null -ne $zip.GetEntry("META-INF/GEN5WTHE.RSA")) "APK signature missing"
        $sf = New-Object System.IO.MemoryStream
        $rsa = New-Object System.IO.MemoryStream
        try {
            $stream = $zip.GetEntry("META-INF/GEN5WTHE.SF").Open()
            try { $stream.CopyTo($sf) } finally { $stream.Dispose() }
            $stream = $zip.GetEntry("META-INF/GEN5WTHE.RSA").Open()
            try { $stream.CopyTo($rsa) } finally { $stream.Dispose() }
            $content = New-Object System.Security.Cryptography.Pkcs.ContentInfo(,$sf.ToArray())
            $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms($content, $true)
            $cms.Decode($rsa.ToArray())
            $cms.CheckSignature($true)
        } finally { $sf.Dispose(); $rsa.Dispose() }
        foreach ($tid in @($id, $imported.activeTheme)) {
            Assert ($null -ne $zip.GetEntry("assets/themes/$tid/manifest.txt")) "Theme manifest missing: $tid"
            Assert ($null -ne $zip.GetEntry("assets/themes/$tid/res/drawable-hdpi/home_bg_weather_map.webp")) "Rendered home background missing: $tid"
            Assert ($null -ne $zip.GetEntry("assets/themes/$tid/assets/fonts/CubeN.ttf")) "Custom font missing: $tid"
            Assert ($null -ne $zip.GetEntry("assets/themes/$tid/systemui/status_bg.9.png")) "Status bar missing: $tid"
            Assert ($null -ne $zip.GetEntry("assets/themes/$tid/climate/clm_bg_main.webp")) "Climate background missing: $tid"
        }
        Assert (-not @($zip.Entries | Where-Object { $_.FullName.Contains('\') }).Count) "APK contains Windows separators"
    } finally { $zip.Dispose() }
    $zipalign = if ($PSVersionTable.Platform -eq "Unix") { "zipalign" } else { Join-Path $repo "tools/zipalign.exe" }
    & $zipalign -c 4 $apk
    Assert ($LASTEXITCODE -eq 0) "APK is not aligned"
    foreach ($file in @("Start-ThemeStudio.bat", "Start-ThemeStudio.command", "Dockerfile", ".dockerignore", "compose.yaml", "README.md", "README-INSTRUCTIONS.txt", "CHANGELOG.md", "THIRD_PARTY_LICENSES.txt")) {
        Copy-Item (Join-Path $repo $file) $work -Force
    }
    Copy-Item (Join-Path $repo "app/src/main/AndroidManifest.xml") (Join-Path $work "app/src/main")
    foreach ($dir in @("java", "res")) {
        Copy-Item (Join-Path $repo "app/src/main/$dir") (Join-Path $work "app/src/main") -Recurse
    }
    & $exe -NoProfile -File (Join-Path $work "scripts/package-for-distribution.ps1")
    Assert ($LASTEXITCODE -eq 0) "Redistributable packaging failed"
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $work "Gen5W-Theme-Studio-Redistributable.zip"))
    try {
        Assert (-not @($zip.Entries | Where-Object { $_.FullName.Contains('\') }).Count) "Redistributable contains Windows separators"
        foreach ($file in @("Start-ThemeStudio.command", "Dockerfile", ".dockerignore", "compose.yaml")) {
            Assert ($null -ne $zip.GetEntry("Gen5WThemeStudio/$file")) "Redistributable missing $file"
        }
    } finally { $zip.Dispose() }
    Write-Host "PASS: startup, theme save/import/export, PNG/JPEG/WebP/font upload, multi-theme USB build, APK signature/alignment, redistributable."
} catch {
    foreach ($log in @("server.log", "server-error.log")) {
        $file = Join-Path $work $log
        if (Test-Path $file) { Get-Content $file -Tail 50 | Write-Host }
    }
    throw
} finally {
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
}
