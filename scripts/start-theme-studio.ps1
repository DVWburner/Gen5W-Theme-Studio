#Requires -Version 5.1
param(
    [int]$Port = 8470,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$StudioVersion = "1.5.0"
$SchemaVersion = 2

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
}

$StudioDir     = Join-Path $ProjectRoot "studio"
$ThemesDir     = Join-Path $StudioDir "themes"
$ActiveIdFile  = Join-Path $ThemesDir "active-theme.txt"
$CustomDir     = Join-Path $StudioDir "custom-assets"
$ConfigPath    = Join-Path $StudioDir "theme-config.json"
$DwebpExe      = Join-Path $ProjectRoot "tools\dwebp.exe"
if (-not (Test-Path $DwebpExe)) {
    $DwebpExe = Join-Path $ProjectRoot ".build-tools\webp\libwebp-1.4.0-windows-x64\bin\dwebp.exe"
}
$Utf8NoBom     = New-Object System.Text.UTF8Encoding($false)

New-Item -ItemType Directory -Force -Path $ThemesDir | Out-Null
New-Item -ItemType Directory -Force -Path $CustomDir | Out-Null

# Ensure built-in "stock-oem" theme exists in studio/themes/stock-oem
$StockThemeDir = Join-Path $ThemesDir "stock-oem"
$StockAssetsDir = Join-Path $StockThemeDir "assets"
$StockCfgPath = Join-Path $StockThemeDir "theme-config.json"
New-Item -ItemType Directory -Force -Path $StockAssetsDir | Out-Null
if (-not (Test-Path $StockCfgPath)) {
    Copy-Item $ConfigPath $StockCfgPath -Force
}

if (-not (Test-Path $ActiveIdFile)) {
    [System.IO.File]::WriteAllText($ActiveIdFile, "stock-oem", $Utf8NoBom)
}

function Get-ActiveThemeId {
    if (Test-Path $ActiveIdFile) {
        $id = ([System.IO.File]::ReadAllText($ActiveIdFile)).Trim() -replace "[^a-zA-Z0-9_-]", ""
        if ($id -and (Test-Path (Join-Path $ThemesDir "$id\theme-config.json"))) {
            return $id
        }
    }
    [System.IO.File]::WriteAllText($ActiveIdFile, "stock-oem", $Utf8NoBom)
    return "stock-oem"
}

function Sync-ActiveThemeToWorking([string]$ThemeId) {
    $tDir = Join-Path $ThemesDir $ThemeId
    $tCfg = Join-Path $tDir "theme-config.json"
    $tAssets = Join-Path $tDir "assets"
    New-Item -ItemType Directory -Force -Path $tAssets | Out-Null
    if (Test-Path $tCfg) {
        Copy-Item $tCfg $ConfigPath -Force
    }
    Remove-Item (Join-Path $CustomDir "*") -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $tAssets -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $CustomDir $_.Name) -Force
    }
}

function Get-ThemesList {
    $activeId = Get-ActiveThemeId
    $list = @()
    $dirs = Get-ChildItem -Path $ThemesDir -Directory | Sort-Object Name
    foreach ($d in $dirs) {
        $cfgFile = Join-Path $d.FullName "theme-config.json"
        if (Test-Path $cfgFile) {
            try {
                $parsed = Get-Content $cfgFile -Raw | ConvertFrom-Json
                $tName = if ($parsed.themeName) { [string]$parsed.themeName } else { $d.Name }
                $list += @{ id = $d.Name; name = $tName; isStock = ($d.Name -eq "stock-oem") }
            } catch {}
        }
    }
    return @{ activeTheme = $activeId; themes = $list; themesDir = $ThemesDir }
}

# Sync active theme on startup
$initId = Get-ActiveThemeId
Sync-ActiveThemeToWorking $initId

$Url = "http://localhost:$Port/"
$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add($Url)
$Listener.Start()

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Gen5W Theme Studio running at: $Url" -ForegroundColor Green
Write-Host "  Saved Themes : $ThemesDir" -ForegroundColor Gray
Write-Host "  Press Ctrl+C in this window to stop the server." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

if (-not $NoBrowser) {
    Start-Process $Url
}

function Send-Json($Response, [int]$StatusCode, $Obj) {
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.AddHeader("Cache-Control", "no-cache, no-store, must-revalidate")
    $Json = $Obj | ConvertTo-Json -Depth 12 -Compress
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function Send-File($Response, [string]$FilePath, [string]$MimeType) {
    if (-not (Test-Path $FilePath)) {
        $Response.StatusCode = 404
        $Response.OutputStream.Close()
        return
    }
    $Response.StatusCode = 200
    $Response.ContentType = $MimeType
    $Response.AddHeader("Cache-Control", "no-cache, no-store, must-revalidate")
    $Bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

try {
    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Req = $Context.Request
        $Res = $Context.Response
        $Path = $Req.Url.AbsolutePath

        try {
            if ($Req.HttpMethod -eq "GET" -and ($Path -eq "/" -or $Path -eq "/index.html")) {
                Send-File $Res (Join-Path $StudioDir "index.html") "text/html; charset=utf-8"
            }
            elseif ($Req.HttpMethod -eq "GET" -and $Path -eq "/api/themes") {
                Send-Json $Res 200 (Get-ThemesList)
            }
            elseif ($Req.HttpMethod -eq "GET" -and $Path -eq "/api/config") {
                $actId = Get-ActiveThemeId
                $actCfg = Join-Path $ThemesDir "$actId\theme-config.json"
                Send-File $Res $actCfg "application/json; charset=utf-8"
            }
            elseif ($Req.HttpMethod -eq "GET" -and $Path.StartsWith("/custom-assets/")) {
                $FileName = [System.IO.Path]::GetFileName($Path)
                $actId = Get-ActiveThemeId
                $ThemeAssetPath = Join-Path $ThemesDir "$actId\assets\$FileName"
                if (Test-Path $ThemeAssetPath) {
                    Send-File $Res $ThemeAssetPath "image/png"
                } else {
                    Send-File $Res (Join-Path $CustomDir $FileName) "image/png"
                }
            }
            elseif ($Req.HttpMethod -eq "POST" -and $Path -eq "/api/themes/select") {
                $TargetId = ($Req.QueryString["id"]) -replace "[^a-zA-Z0-9_-]", ""
                $TargetCfg = Join-Path $ThemesDir "$TargetId\theme-config.json"
                if (-not $TargetId -or -not (Test-Path $TargetCfg)) {
                    throw "Theme '$TargetId' not found"
                }
                [System.IO.File]::WriteAllText($ActiveIdFile, $TargetId, $Utf8NoBom)
                Sync-ActiveThemeToWorking $TargetId
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Switched active theme to: $TargetId" -ForegroundColor Cyan
                $cfgObj = Get-Content $TargetCfg -Raw | ConvertFrom-Json
                Send-Json $Res 200 @{ ok = $true; activeTheme = $TargetId; config = $cfgObj; themes = (Get-ThemesList).themes }
            }
            elseif ($Req.HttpMethod -eq "POST" -and $Path -eq "/api/themes/create") {
                $Reader = New-Object System.IO.StreamReader($Req.InputStream, [System.Text.Encoding]::UTF8)
                $Body = $Reader.ReadToEnd()
                $Reader.Close()
                $Payload = $Body | ConvertFrom-Json

                $RawName = [string]$Payload.name
                if (-not $RawName) { $RawName = "Custom Theme" }
                $Slug = ($RawName.ToLower() -replace "[^a-z0-9]+", "-").Trim('-')
                if (-not $Slug -or $Slug -eq "stock-oem") { $Slug = "theme-" + (Get-Date -Format "MMdd-HHmmss") }
                $NewDir = Join-Path $ThemesDir $Slug
                if (Test-Path $NewDir) {
                    $Slug = "$Slug-" + (Get-Date -Format "HHmmss")
                    $NewDir = Join-Path $ThemesDir $Slug
                }
                $NewAssets = Join-Path $NewDir "assets"
                New-Item -ItemType Directory -Force -Path $NewAssets | Out-Null

                $BaseId = if ($Payload.baseId) { ([string]$Payload.baseId) -replace "[^a-zA-Z0-9_-]", "" } else { Get-ActiveThemeId }
                $BaseAssets = Join-Path $ThemesDir "$BaseId\assets"
                if (Test-Path $BaseAssets) {
                    Get-ChildItem -Path $BaseAssets -File -ErrorAction SilentlyContinue | ForEach-Object {
                        Copy-Item $_.FullName (Join-Path $NewAssets $_.Name) -Force
                    }
                }

                $CfgToSave = if ($null -ne $Payload.config) { $Payload.config } else { Get-Content (Join-Path $ThemesDir "stock-oem\theme-config.json") -Raw | ConvertFrom-Json }
                $CfgToSave.themeName = $RawName
                $Formatted = $CfgToSave | ConvertTo-Json -Depth 12
                [System.IO.File]::WriteAllText((Join-Path $NewDir "theme-config.json"), $Formatted, $Utf8NoBom)
                [System.IO.File]::WriteAllText($ActiveIdFile, $Slug, $Utf8NoBom)
                Sync-ActiveThemeToWorking $Slug

                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Created and activated theme: $RawName ($Slug)" -ForegroundColor Green
                Send-Json $Res 200 @{ ok = $true; activeTheme = $Slug; name = $RawName; config = $CfgToSave; themes = (Get-ThemesList).themes }
            }
            elseif ($Req.HttpMethod -eq "POST" -and $Path -eq "/api/themes/delete") {
                $DelId = ($Req.QueryString["id"]) -replace "[^a-zA-Z0-9_-]", ""
                if (-not $DelId -or $DelId -eq "stock-oem") {
                    throw "Cannot delete the built-in Factory Stock OEM theme"
                }
                $DelDir = Join-Path $ThemesDir $DelId
                if (Test-Path $DelDir) {
                    Remove-Item -Path $DelDir -Recurse -Force
                }
                [System.IO.File]::WriteAllText($ActiveIdFile, "stock-oem", $Utf8NoBom)
                Sync-ActiveThemeToWorking "stock-oem"
                $stockCfg = Get-Content (Join-Path $ThemesDir "stock-oem\theme-config.json") -Raw | ConvertFrom-Json
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Deleted theme '$DelId', reverted to stock-oem" -ForegroundColor Yellow
                Send-Json $Res 200 @{ ok = $true; activeTheme = "stock-oem"; config = $stockCfg; themes = (Get-ThemesList).themes }
            }
            elseif ($Req.HttpMethod -eq "GET" -and $Path -eq "/api/themes/export") {
                $ExpId = ($Req.QueryString["id"]) -replace "[^a-zA-Z0-9_-]", ""
                if (-not $ExpId) { $ExpId = Get-ActiveThemeId }
                $ExpDir = Join-Path $ThemesDir $ExpId
                $ExpCfgFile = Join-Path $ExpDir "theme-config.json"
                if (-not (Test-Path $ExpCfgFile)) {
                    throw "Theme '$ExpId' not found on disk"
                }

                $ExpCfgObj = Get-Content $ExpCfgFile -Raw | ConvertFrom-Json
                if (-not $ExpCfgObj.PSObject.Properties["studioVersion"]) {
                    $ExpCfgObj | Add-Member -NotePropertyName "studioVersion" -NotePropertyValue $StudioVersion
                } else {
                    $ExpCfgObj.studioVersion = $StudioVersion
                }
                if (-not $ExpCfgObj.PSObject.Properties["schemaVersion"]) {
                    $ExpCfgObj | Add-Member -NotePropertyName "schemaVersion" -NotePropertyValue $SchemaVersion
                } else {
                    $ExpCfgObj.schemaVersion = $SchemaVersion
                }

                $ExpAssetsDir = Join-Path $ExpDir "assets"
                $AssetFiles = if (Test-Path $ExpAssetsDir) { @(Get-ChildItem -Path $ExpAssetsDir -File) } else { @() }
                $DispName = if ($ExpCfgObj.themeName) { [string]$ExpCfgObj.themeName } else { $ExpId }

                $MetaObj = [ordered]@{
                    format               = "Gen5WThemeStudioPack"
                    studioVersion        = $StudioVersion
                    schemaVersion        = $SchemaVersion
                    minCompatibleVersion = "1.0.0"
                    exportedAt           = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    themeSlug            = $ExpId
                    themeName            = $DispName
                    assetsCount          = $AssetFiles.Count
                }

                $Ms = New-Object System.IO.MemoryStream
                $Zip = New-Object System.IO.Compression.ZipArchive($Ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
                try {
                    $MetaBytes = $Utf8NoBom.GetBytes(($MetaObj | ConvertTo-Json -Depth 6))
                    $MetaEntry = $Zip.CreateEntry("gen5w-theme-meta.json", [System.IO.Compression.CompressionLevel]::Optimal)
                    $MetaStream = $MetaEntry.Open()
                    $MetaStream.Write($MetaBytes, 0, $MetaBytes.Length)
                    $MetaStream.Close()

                    $CfgBytes = $Utf8NoBom.GetBytes(($ExpCfgObj | ConvertTo-Json -Depth 12))
                    $CfgEntry = $Zip.CreateEntry("theme-config.json", [System.IO.Compression.CompressionLevel]::Optimal)
                    $CfgStream = $CfgEntry.Open()
                    $CfgStream.Write($CfgBytes, 0, $CfgBytes.Length)
                    $CfgStream.Close()

                    foreach ($af in $AssetFiles) {
                        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                            $Zip,
                            $af.FullName,
                            "assets/$($af.Name)",
                            [System.IO.Compression.CompressionLevel]::Optimal
                        ) | Out-Null
                    }
                } finally {
                    $Zip.Dispose()
                }

                $ZipBytes = $Ms.ToArray()
                $Ms.Close()

                $DlFileName = "$ExpId-v$StudioVersion.gen5wtheme"
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Exported theme '$DispName' ($($AssetFiles.Count) assets, v$StudioVersion) -> $DlFileName" -ForegroundColor Cyan
                $Res.StatusCode = 200
                $Res.ContentType = "application/octet-stream"
                $Res.AddHeader("Content-Disposition", "attachment; filename=`"$DlFileName`"")
                $Res.AddHeader("Cache-Control", "no-cache, no-store, must-revalidate")
                $Res.ContentLength64 = $ZipBytes.Length
                $Res.OutputStream.Write($ZipBytes, 0, $ZipBytes.Length)
                $Res.OutputStream.Close()
            }
            elseif ($Req.HttpMethod -eq "POST" -and $Path -eq "/api/themes/import") {
                $Reader = New-Object System.IO.StreamReader($Req.InputStream, [System.Text.Encoding]::UTF8)
                $Body = $Reader.ReadToEnd()
                $Reader.Close()

                $Payload = $Body | ConvertFrom-Json
                $DataUrl = [string]$Payload.dataUrl
                if (-not $DataUrl) { throw "Missing ZIP data payload" }
                $B64 = if ($DataUrl -match "^data:[^;]+;base64,(.+)$") { $Matches[1] } else { $DataUrl }
                $ZipBytes = [Convert]::FromBase64String($B64)

                $Ms = New-Object System.IO.MemoryStream(,$ZipBytes)
                $Zip = New-Object System.IO.Compression.ZipArchive($Ms, [System.IO.Compression.ZipArchiveMode]::Read)
                try {
                    $CfgEntry = $Zip.Entries | Where-Object { $_.FullName -match "(^|/)theme-config\.json$" } | Select-Object -First 1
                    if ($null -eq $CfgEntry) {
                        throw "Invalid theme ZIP: missing theme-config.json"
                    }

                    $CfgReader = New-Object System.IO.StreamReader($CfgEntry.Open(), [System.Text.Encoding]::UTF8)
                    $CfgJsonText = $CfgReader.ReadToEnd()
                    $CfgReader.Close()
                    $ImpCfg = $CfgJsonText | ConvertFrom-Json

                    $MetaEntry = $Zip.Entries | Where-Object { $_.FullName -match "(^|/)gen5w-theme-meta\.json$" } | Select-Object -First 1
                    $ImpMeta = $null
                    if ($null -ne $MetaEntry) {
                        $MetaReader = New-Object System.IO.StreamReader($MetaEntry.Open(), [System.Text.Encoding]::UTF8)
                        $ImpMeta = ($MetaReader.ReadToEnd()) | ConvertFrom-Json
                        $MetaReader.Close()
                    }

                    $CreatedVer = if ($ImpMeta -and $ImpMeta.studioVersion) { [string]$ImpMeta.studioVersion } elseif ($ImpCfg.studioVersion) { [string]$ImpCfg.studioVersion } else { "1.0.0 (Legacy)" }
                    $ImpSchema  = if ($ImpMeta -and $ImpMeta.schemaVersion) { [int]$ImpMeta.schemaVersion } elseif ($ImpCfg.schemaVersion) { [int]$ImpCfg.schemaVersion } else { 1 }

                    $CompatNote = ""
                    if ($ImpSchema -gt $SchemaVersion) {
                        $CompatNote = "Warning: Theme was exported from a newer Studio version (v$CreatedVer, schema v$ImpSchema). Current Studio is v$StudioVersion."
                    } elseif ($ImpSchema -lt $SchemaVersion) {
                        $CompatNote = "Migrated legacy v$CreatedVer theme to v$StudioVersion schema."
                    }

                    # Ensure any newly introduced v1.5 fields have safe defaults on older imported themes
                    if ($null -ne $ImpCfg.homeScreen) {
                        if (-not $ImpCfg.homeScreen.PSObject.Properties["bgFit"])            { $ImpCfg.homeScreen | Add-Member -NotePropertyName "bgFit"            -NotePropertyValue "cover" }
                        if (-not $ImpCfg.homeScreen.PSObject.Properties["mapFadeMode"])      { $ImpCfg.homeScreen | Add-Member -NotePropertyName "mapFadeMode"      -NotePropertyValue "feather" }
                        if (-not $ImpCfg.homeScreen.PSObject.Properties["mapFadeWidth"])     { $ImpCfg.homeScreen | Add-Member -NotePropertyName "mapFadeWidth"     -NotePropertyValue 75 }
                        if (-not $ImpCfg.homeScreen.PSObject.Properties["mapCenterOpacity"]) { $ImpCfg.homeScreen | Add-Member -NotePropertyName "mapCenterOpacity" -NotePropertyValue 0 }
                    }
                    if ($null -ne $ImpCfg.batteryWidget) {
                        if (-not $ImpCfg.batteryWidget.PSObject.Properties["rangeOffsetX"])    { $ImpCfg.batteryWidget | Add-Member -NotePropertyName "rangeOffsetX"    -NotePropertyValue 0 }
                        if (-not $ImpCfg.batteryWidget.PSObject.Properties["rangeOffsetY"])    { $ImpCfg.batteryWidget | Add-Member -NotePropertyName "rangeOffsetY"    -NotePropertyValue 0 }
                        if (-not $ImpCfg.batteryWidget.PSObject.Properties["battTextOffsetX"]) { $ImpCfg.batteryWidget | Add-Member -NotePropertyName "battTextOffsetX" -NotePropertyValue 0 }
                        if (-not $ImpCfg.batteryWidget.PSObject.Properties["battTextOffsetY"]) { $ImpCfg.batteryWidget | Add-Member -NotePropertyName "battTextOffsetY" -NotePropertyValue 0 }
                    }

                    $RawName = if ($ImpCfg.themeName) { [string]$ImpCfg.themeName } elseif ($ImpMeta -and $ImpMeta.themeName) { [string]$ImpMeta.themeName } else { "Imported Theme" }
                    $BaseSlug = ($RawName.ToLower() -replace "[^a-z0-9]+", "-").Trim('-')
                    if (-not $BaseSlug -or $BaseSlug -eq "stock-oem") { $BaseSlug = "imported-theme" }

                    $TargetSlug = $BaseSlug
                    $Suffix = 2
                    while (Test-Path (Join-Path $ThemesDir $TargetSlug)) {
                        $TargetSlug = "$BaseSlug-$Suffix"
                        $Suffix++
                    }
                    if ($TargetSlug -ne $BaseSlug) {
                        $RawName = "$RawName ($($Suffix - 1))"
                        $ImpCfg.themeName = $RawName
                    }

                    $TargetDir = Join-Path $ThemesDir $TargetSlug
                    $TargetAssets = Join-Path $TargetDir "assets"
                    New-Item -ItemType Directory -Force -Path $TargetAssets | Out-Null

                    $ExtractedCount = 0
                    foreach ($ze in $Zip.Entries) {
                        if ($ze.FullName.EndsWith("/")) { continue }
                        if ($ze.FullName -match "(^|/)assets/([^/]+\.(png|jpg|jpeg|webp))$") {
                            $SafeAssetName = [System.IO.Path]::GetFileName($ze.FullName) -replace "[^a-zA-Z0-9._-]", ""
                            if ($SafeAssetName) {
                                $DestAssetPath = Join-Path $TargetAssets $SafeAssetName
                                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($ze, $DestAssetPath, $true)
                                $ExtractedCount++
                            }
                        }
                    }

                    $FormattedCfg = $ImpCfg | ConvertTo-Json -Depth 12
                    [System.IO.File]::WriteAllText((Join-Path $TargetDir "theme-config.json"), $FormattedCfg, $Utf8NoBom)
                    if ($null -ne $ImpMeta) {
                        [System.IO.File]::WriteAllText((Join-Path $TargetDir "gen5w-theme-meta.json"), ($ImpMeta | ConvertTo-Json -Depth 6), $Utf8NoBom)
                    }

                    [System.IO.File]::WriteAllText($ActiveIdFile, $TargetSlug, $Utf8NoBom)
                    Sync-ActiveThemeToWorking $TargetSlug

                    $Msg = "Imported '$RawName' (made on Studio v$CreatedVer, $ExtractedCount custom assets) -> studio/themes/$TargetSlug"
                    if ($CompatNote) { $Msg += " [$CompatNote]" }
                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor Green

                    Send-Json $Res 200 @{
                        ok = $true
                        activeTheme = $TargetSlug
                        name = $RawName
                        createdWithVersion = $CreatedVer
                        schemaVersion = $ImpSchema
                        assetsExtracted = $ExtractedCount
                        compatNote = $CompatNote
                        message = $Msg
                        config = $ImpCfg
                        themes = (Get-ThemesList).themes
                    }
                } finally {
                    $Zip.Dispose()
                    $Ms.Close()
                }
            }
            elseif ($Req.HttpMethod -eq "POST" -and $Path -eq "/api/save-config") {
                $Reader = New-Object System.IO.StreamReader($Req.InputStream, [System.Text.Encoding]::UTF8)
                $Body = $Reader.ReadToEnd()
                $Reader.Close()
                $Parsed = $Body | ConvertFrom-Json
                $Formatted = $Parsed | ConvertTo-Json -Depth 12
                $actId = Get-ActiveThemeId
                $actCfgPath = Join-Path $ThemesDir "$actId\theme-config.json"
                [System.IO.File]::WriteAllText($actCfgPath, $Formatted, $Utf8NoBom)
                [System.IO.File]::WriteAllText($ConfigPath, $Formatted, $Utf8NoBom)
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Saved theme '$actId' ($($Parsed.themeName))" -ForegroundColor Green
                Send-Json $Res 200 @{ ok = $true; message = "Saved theme '$($Parsed.themeName)'!"; themes = (Get-ThemesList).themes }
            }
            elseif ($Req.HttpMethod -eq "POST" -and ($Path -eq "/api/upload-asset" -or $Path -eq "/api/upload-icon")) {
                $SlotKey = $Req.QueryString["slot"]
                if (-not $SlotKey) { $SlotKey = $Req.QueryString["key"] }
                $SlotKey = $SlotKey -replace "[^a-zA-Z0-9_-]", ""
                if (-not $SlotKey) { throw "Missing slot/key parameter" }

                $Reader = New-Object System.IO.StreamReader($Req.InputStream, [System.Text.Encoding]::UTF8)
                $Body = $Reader.ReadToEnd()
                $Reader.Close()

                $DataUrl = $Body
                if ($Body.TrimStart().StartsWith("{")) {
                    $Payload = $Body | ConvertFrom-Json
                    $DataUrl = [string]$Payload.dataUrl
                }
                if ($DataUrl -match "^data:image/([a-zA-Z0-9+.-]+);base64,(.+)$") {
                    $ImgFmt = $Matches[1].ToLower()
                    $Base64 = $Matches[2]
                    $Bytes = [Convert]::FromBase64String($Base64)

                    $actId = Get-ActiveThemeId
                    $actAssetsDir = Join-Path $ThemesDir "$actId\assets"
                    New-Item -ItemType Directory -Force -Path $actAssetsDir | Out-Null
                    $OutPng = Join-Path $actAssetsDir "$SlotKey.png"

                    if ($ImgFmt -eq "webp" -and (Test-Path $DwebpExe)) {
                        $TmpWebp = Join-Path $actAssetsDir "$SlotKey.tmp.webp"
                        [System.IO.File]::WriteAllBytes($TmpWebp, $Bytes)
                        & $DwebpExe -quiet $TmpWebp -o $OutPng
                        Remove-Item $TmpWebp -Force -ErrorAction SilentlyContinue
                    } elseif ($ImgFmt -eq "png") {
                        [System.IO.File]::WriteAllBytes($OutPng, $Bytes)
                    } else {
                        $Ms = New-Object System.IO.MemoryStream(,$Bytes)
                        $Bmp = [System.Drawing.Bitmap]::FromStream($Ms)
                        $Bmp.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
                        $Bmp.Dispose()
                        $Ms.Dispose()
                    }
                    Copy-Item $OutPng (Join-Path $CustomDir "$SlotKey.png") -Force
                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Uploaded asset to theme '$actId': $SlotKey.png" -ForegroundColor Cyan
                    Send-Json $Res 200 @{ ok = $true; file = "$SlotKey.png" }
                } else {
                    throw "Invalid image dataUrl"
                }
            }
            elseif ($Req.HttpMethod -eq "GET" -and $Path -eq "/api/download-usb-zip") {
                $actId = Get-ActiveThemeId
                $reqName = $Req.QueryString["name"] -replace "[^a-zA-Z0-9._-]", ""
                $usbZip = Join-Path $ProjectRoot "dist\gen5w.nemesis.themer-usb.zip"
                if (-not (Test-Path $usbZip)) {
                    $Res.StatusCode = 404
                    $Res.OutputStream.Close()
                } else {
                    $dlName = if ($reqName -and $reqName.EndsWith(".zip")) { $reqName } else { "Gen5W-Theme-$actId-USB.zip" }
                    $Res.StatusCode = 200
                    $Res.ContentType = "application/zip"
                    $Res.AddHeader("Content-Disposition", "attachment; filename=`"$dlName`"")
                    $Res.AddHeader("Cache-Control", "no-cache, no-store, must-revalidate")
                    $Bytes = [System.IO.File]::ReadAllBytes($usbZip)
                    $Res.ContentLength64 = $Bytes.Length
                    $Res.OutputStream.Write($Bytes, 0, $Bytes.Length)
                    $Res.OutputStream.Close()
                }
            }
            elseif ($Req.HttpMethod -eq "POST" -and $Path -eq "/api/build-and-deploy") {
                $Reader = New-Object System.IO.StreamReader($Req.InputStream, [System.Text.Encoding]::UTF8)
                $Body = $Reader.ReadToEnd()
                $Reader.Close()
                $RawObj = $Body | ConvertFrom-Json

                $ParsedCfg = if ($null -ne $RawObj.config -and $null -ne $RawObj.selectedThemes) { $RawObj.config } else { $RawObj }
                $SelectedIds = if ($null -ne $RawObj.selectedThemes -and @($RawObj.selectedThemes).Count -gt 0) {
                    @(@($RawObj.selectedThemes) | ForEach-Object { ([string]$_) -replace "[^a-zA-Z0-9_-]", "" } | Where-Object { $_ -ne "" })
                } else {
                    @()
                }

                $Formatted = $ParsedCfg | ConvertTo-Json -Depth 12
                $actId = Get-ActiveThemeId
                $actCfgPath = Join-Path $ThemesDir "$actId\theme-config.json"
                $actAssetsDir = Join-Path $ThemesDir "$actId\assets"
                New-Item -ItemType Directory -Force -Path $actAssetsDir | Out-Null

                [System.IO.File]::WriteAllText($actCfgPath, $Formatted, $Utf8NoBom)
                [System.IO.File]::WriteAllText($ConfigPath, $Formatted, $Utf8NoBom)
                Sync-ActiveThemeToWorking $actId

                if ($SelectedIds.Count -eq 0) {
                    $SelectedIds = @($actId)
                }

                $AppThemesRoot = Join-Path $ProjectRoot "app\src\main\assets\themes"
                if (Test-Path $AppThemesRoot) {
                    Remove-Item -Path $AppThemesRoot -Recurse -Force
                }
                New-Item -ItemType Directory -Force -Path $AppThemesRoot | Out-Null

                $GenScript = Join-Path $ProjectRoot "scripts\generate-lcars-theme.ps1"
                $BuildScript = Join-Path $ProjectRoot "scripts\build-nemesis-package.ps1"
                $IndexLines = @()
                $BuiltNames = @()
                $BuiltIds = @()

                foreach ($tid in $SelectedIds) {
                    $tCfgFile = Join-Path $ThemesDir "$tid\theme-config.json"
                    $tAssDir  = Join-Path $ThemesDir "$tid\assets"
                    if (-not (Test-Path $tCfgFile)) { continue }
                    New-Item -ItemType Directory -Force -Path $tAssDir | Out-Null
                    $tParsed = Get-Content $tCfgFile -Raw | ConvertFrom-Json
                    $tDispName = if ($tParsed.themeName) { [string]$tParsed.themeName } else { $tid }

                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Generating theme '$tDispName' ($tid)..." -ForegroundColor Yellow
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GenScript -ConfigPath $tCfgFile -CustomAssetsDir $tAssDir -OutputSubdir $tid
                    if ($LASTEXITCODE -ne 0) { throw "generate-lcars-theme.ps1 failed for theme '$tid'" }

                    $IndexLines += "$tid|$tDispName"
                    $BuiltNames += $tDispName
                    $BuiltIds += $tid
                }

                if ($IndexLines.Count -eq 0) {
                    throw "No valid themes selected to build"
                }

                [System.IO.File]::WriteAllLines((Join-Path $AppThemesRoot "themes-index.txt"), $IndexLines, $Utf8NoBom)

                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Packaging $($IndexLines.Count) theme(s) into Gen5WThemer.apk..." -ForegroundColor Yellow
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript
                if ($LASTEXITCODE -ne 0) { throw "build-nemesis-package.ps1 failed" }

                $ZipFileName = if ($IndexLines.Count -gt 1) { "Gen5W-MultiTheme-Pack-$($IndexLines.Count)Themes-USB.zip" } else { "Gen5W-Theme-$($BuiltIds[0])-USB.zip" }
                $NamedZip = Join-Path $ProjectRoot "dist\$ZipFileName"
                Copy-Item (Join-Path $ProjectRoot "dist\gen5w.nemesis.themer-usb.zip") $NamedZip -Force

                $BuildMsg = "Built $($IndexLines.Count) theme(s) (" + ($BuiltNames -join ", ") + ") -> $ZipFileName"
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $BuildMsg" -ForegroundColor Green
                Send-Json $Res 200 @{
                    ok = $true
                    message = $BuildMsg
                    downloadUrl = "/api/download-usb-zip?name=" + [Uri]::EscapeDataString($ZipFileName) + "&t=" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    fileName = $ZipFileName
                }
            }
            else {
                $Res.StatusCode = 404
                $Res.OutputStream.Close()
            }
        } catch {
            Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
            try {
                Send-Json $Res 500 @{ ok = $false; error = $_.Exception.Message }
            } catch {}
        }
    }
} finally {
    $Listener.Stop()
    $Listener.Close()
}
