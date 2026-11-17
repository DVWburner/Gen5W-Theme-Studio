#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectRoot) {
    $ProjectRoot = (Get-Location).Path
}

Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ToolsDir     = Join-Path $ProjectRoot "tools"
$DevToolsDir  = Join-Path $ProjectRoot ".build-tools"
$JdkDir       = Join-Path $DevToolsDir "jdk"
$SdkDir       = Join-Path $DevToolsDir "android-sdk"
$BuildOut     = Join-Path $ProjectRoot "build"
$DistDir      = Join-Path $ProjectRoot "dist"
$AssetsDir    = Join-Path $ProjectRoot "app\src\main\assets"
$BaseApkPath  = Join-Path $ToolsDir "Gen5WThemer-base.apk"
$PfxPath      = Join-Path $ToolsDir "nemesis-release.pfx"

New-Item -ItemType Directory -Force -Path $BuildOut | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
New-Item -ItemType Directory -Force -Path $AssetsDir | Out-Null

$ZipalignExe = Join-Path $ToolsDir "zipalign.exe"
if ($PSVersionTable.Platform -eq "Unix") {
    $ZipalignExe = (Get-Command zipalign -ErrorAction Stop).Source
} elseif (-not (Test-Path $ZipalignExe)) {
    $ZipalignExe = Get-ChildItem -Path (Join-Path $SdkDir "build-tools") -Recurse -Filter "zipalign.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}

function Format-ManifestAttributeLine([string]$Line) {
    # JAR specification: max 72 bytes per line; continuation lines start with a single space
    $ascii = [System.Text.Encoding]::UTF8
    $bytes = $ascii.GetBytes($Line)
    if ($bytes.Length -le 70) {
        return "$Line`r`n"
    }
    $sb = New-Object System.Text.StringBuilder
    $sb.Append($Line.Substring(0, 70)).Append("`r`n") | Out-Null
    $pos = 70
    while ($pos -lt $Line.Length) {
        $take = [Math]::Min(69, $Line.Length - $pos)
        $sb.Append(" ").Append($Line.Substring($pos, $take)).Append("`r`n") | Out-Null
        $pos += $take
    }
    return $sb.ToString()
}

function Sign-ApkV1PurePowerShell([string]$ApkPath, [string]$PfxFile, [string]$PfxPassword) {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        $PfxFile,
        $PfxPassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    )
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    $zip = [System.IO.Compression.ZipFile]::Open($ApkPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        # Remove any existing META-INF entries
        $oldMeta = @($zip.Entries | Where-Object { $_.FullName.StartsWith("META-INF/") })
        foreach ($m in $oldMeta) { $m.Delete() }

        $mfMainHeader = "Manifest-Version: 1.0`r`nCreated-By: 1.8.0 (Gen5WThemeStudio)`r`n`r`n"
        $mfBuilder = New-Object System.Text.StringBuilder
        [void]$mfBuilder.Append($mfMainHeader)

        $entrySections = @()
        $allEntries = @($zip.Entries | Sort-Object FullName)
        foreach ($entry in $allEntries) {
            if ($entry.FullName.EndsWith("/")) { continue }
            $ms = New-Object System.IO.MemoryStream
            $s = $entry.Open()
            $s.CopyTo($ms)
            $s.Close()
            $dataBytes = $ms.ToArray()
            $ms.Close()

            $hashB64 = [Convert]::ToBase64String($sha256.ComputeHash($dataBytes))
            $secText = (Format-ManifestAttributeLine "Name: $($entry.FullName)") +
                       (Format-ManifestAttributeLine "SHA-256-Digest: $hashB64") +
                       "`r`n"
            [void]$mfBuilder.Append($secText)
            $entrySections += @{ Name = $entry.FullName; SectionText = $secText }
        }

        $mfBytes = $utf8NoBom.GetBytes($mfBuilder.ToString())
        $mfMainBytes = $utf8NoBom.GetBytes($mfMainHeader)

        $mfDigestB64 = [Convert]::ToBase64String($sha256.ComputeHash($mfBytes))
        $mfMainDigestB64 = [Convert]::ToBase64String($sha256.ComputeHash($mfMainBytes))

        $sfBuilder = New-Object System.Text.StringBuilder
        [void]$sfBuilder.Append("Signature-Version: 1.0`r`n")
        [void]$sfBuilder.Append("Created-By: 1.8.0 (Gen5WThemeStudio)`r`n")
        [void]$sfBuilder.Append((Format-ManifestAttributeLine "SHA-256-Digest-Manifest: $mfDigestB64"))
        [void]$sfBuilder.Append((Format-ManifestAttributeLine "SHA-256-Digest-Manifest-Main-Attributes: $mfMainDigestB64"))
        [void]$sfBuilder.Append("`r`n")

        foreach ($sec in $entrySections) {
            $secBytes = $utf8NoBom.GetBytes($sec.SectionText)
            $secHashB64 = [Convert]::ToBase64String($sha256.ComputeHash($secBytes))
            [void]$sfBuilder.Append((Format-ManifestAttributeLine "Name: $($sec.Name)"))
            [void]$sfBuilder.Append((Format-ManifestAttributeLine "SHA-256-Digest: $secHashB64"))
            [void]$sfBuilder.Append("`r`n")
        }

        $sfBytes = $utf8NoBom.GetBytes($sfBuilder.ToString())

        # Compute detached PKCS#7 / CMS signature (SHA256withRSA, no signed attributes)
        $ci = New-Object System.Security.Cryptography.Pkcs.ContentInfo(,$sfBytes)
        $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms($ci, $true)
        $signer = New-Object System.Security.Cryptography.Pkcs.CmsSigner($cert)
        $signer.IncludeOption = [System.Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
        $signer.DigestAlgorithm = New-Object System.Security.Cryptography.Oid("2.16.840.1.101.3.4.2.1") # SHA-256
        $cms.ComputeSignature($signer, $false)
        $rsaBytes = $cms.Encode()

        foreach ($metaItem in @(
            @{ Name = "META-INF/MANIFEST.MF";  Bytes = $mfBytes },
            @{ Name = "META-INF/GEN5WTHE.SF";  Bytes = $sfBytes },
            @{ Name = "META-INF/GEN5WTHE.RSA"; Bytes = $rsaBytes }
        )) {
            $ze = $zip.CreateEntry($metaItem.Name, [System.IO.Compression.CompressionLevel]::Optimal)
            $zs = $ze.Open()
            $zs.Write($metaItem.Bytes, 0, $metaItem.Bytes.Length)
            $zs.Close()
        }
    } finally {
        $zip.Dispose()
        $sha256.Dispose()
    }
}

$UnsignedApk = Join-Path $BuildOut "Gen5WThemer-unsigned.apk"
if (Test-Path $UnsignedApk) { Remove-Item $UnsignedApk -Force }

# Check if full JDK + Android SDK are available (dev machine) or if we should use the prebuilt base APK shell
$JavacExe = if ($PSVersionTable.Platform -ne "Unix" -and (Test-Path $JdkDir)) { Get-ChildItem -Path $JdkDir -Recurse -Filter "javac.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName } else { $null }
$AndroidJar = Join-Path $SdkDir "platforms\android-28\android.jar"

if ($JavacExe -and (Test-Path $AndroidJar)) {
    $JavaBinDir = Split-Path -Parent $JavacExe
    $JavaHome = Split-Path -Parent $JavaBinDir
    $JavaExe = Join-Path $JavaBinDir "java.exe"
    $env:JAVA_HOME = $JavaHome
    $env:PATH = "$JavaBinDir;$env:PATH"
    Write-Host "==> [Dev Mode] Compiling Java & Android resources with JDK/SDK..."

    $BuildToolsDir = Join-Path $SdkDir "build-tools\28.0.3"
    $AaptExe = Get-ChildItem -Path $BuildToolsDir -Recurse -Filter "aapt.exe" | Select-Object -First 1 -ExpandProperty FullName
    $DxJar = Get-ChildItem -Path $BuildToolsDir -Recurse -Filter "dx.jar" | Select-Object -First 1 -ExpandProperty FullName

    $GenDir = Join-Path $BuildOut "gen"
    $ClassesDir = Join-Path $BuildOut "classes"
    if (Test-Path $GenDir) { Remove-Item $GenDir -Recurse -Force }
    if (Test-Path $ClassesDir) { Remove-Item $ClassesDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $GenDir | Out-Null
    New-Item -ItemType Directory -Force -Path $ClassesDir | Out-Null

    $ManifestPath = Join-Path $ProjectRoot "app\src\main\AndroidManifest.xml"
    $ResDir = Join-Path $ProjectRoot "app\src\main\res"

    & $AaptExe package -f -m -J $GenDir -M $ManifestPath -S $ResDir -A $AssetsDir -I $AndroidJar
    if ($LASTEXITCODE -ne 0) { throw "aapt R.java generation failed" }

    $JavaFiles = @()
    $JavaFiles += Get-ChildItem -Path (Join-Path $ProjectRoot "app\src\main\java") -Recurse -Filter "*.java" | Select-Object -ExpandProperty FullName
    $JavaFiles += Get-ChildItem -Path $GenDir -Recurse -Filter "*.java" | Select-Object -ExpandProperty FullName

    & $JavacExe -source 1.7 -target 1.7 -encoding UTF-8 -bootclasspath $AndroidJar -d $ClassesDir $JavaFiles
    if ($LASTEXITCODE -ne 0) { throw "javac compilation failed" }

    $DexFile = Join-Path $BuildOut "classes.dex"
    & $JavaExe -jar $DxJar --dex --min-sdk-version=19 --output=$DexFile $ClassesDir
    if ($LASTEXITCODE -ne 0) { throw "dx dexing failed" }

    & $AaptExe package -f -0 ttf -0 otf -M $ManifestPath -S $ResDir -A $AssetsDir -I $AndroidJar -F $UnsignedApk
    if ($LASTEXITCODE -ne 0) { throw "aapt APK packaging failed" }

    $Archive = [System.IO.Compression.ZipFile]::Open($UnsignedApk, [System.IO.Compression.ZipArchiveMode]::Update)
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Archive, $DexFile, "classes.dex") | Out-Null
    $Archive.Dispose()

    # Also refresh tools/Gen5WThemer-base.apk so standalone distributions stay up-to-date
    if (Test-Path $ToolsDir) {
        if (Test-Path $BaseApkPath) { Remove-Item $BaseApkPath -Force }
        $srcZip = [System.IO.Compression.ZipFile]::OpenRead($UnsignedApk)
        $dstZip = [System.IO.Compression.ZipFile]::Open($BaseApkPath, [System.IO.Compression.ZipArchiveMode]::Create)
        foreach ($e in $srcZip.Entries) {
            if (-not $e.FullName.StartsWith("assets/") -and -not $e.FullName.StartsWith("META-INF/")) {
                $lvl = if ($e.FullName -eq "resources.arsc") { [System.IO.Compression.CompressionLevel]::NoCompression } else { [System.IO.Compression.CompressionLevel]::Optimal }
                $ne = $dstZip.CreateEntry($e.FullName, $lvl)
                $inS = $e.Open(); $outS = $ne.Open()
                $inS.CopyTo($outS)
                $outS.Close(); $inS.Close()
            }
        }
        $dstZip.Dispose(); $srcZip.Dispose()
    }
} else {
    Write-Host "==> [Standalone Mode] Packaging theme assets into Gen5WThemer-base.apk..."
    if (-not (Test-Path $BaseApkPath)) {
        throw "Missing base APK shell at $BaseApkPath"
    }
    Copy-Item $BaseApkPath $UnsignedApk -Force
    $Archive = [System.IO.Compression.ZipFile]::Open($UnsignedApk, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $AssetFiles = Get-ChildItem -Path $AssetsDir -Recurse -File
        foreach ($af in $AssetFiles) {
            $rel = "assets/" + $af.FullName.Substring($AssetsDir.Length + 1).Replace('\', '/')
            $lvl = if ($af.Extension -match "^\.(webp|png|jpg|ttf|otf)$") {
                [System.IO.Compression.CompressionLevel]::NoCompression
            } else {
                [System.IO.Compression.CompressionLevel]::Optimal
            }
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Archive, $af.FullName, $rel, $lvl) | Out-Null
        }
    } finally {
        $Archive.Dispose()
    }
}

Write-Host "==> Signing APK with v1 JAR Signature (SHA256withRSA) for Android 4.4.2..."
$SignedUnalignedApk = Join-Path $BuildOut "Gen5WThemer-signed-unaligned.apk"
Copy-Item $UnsignedApk $SignedUnalignedApk -Force
Sign-ApkV1PurePowerShell -ApkPath $SignedUnalignedApk -PfxFile $PfxPath -PfxPassword "nemesis123"

Write-Host "==> Zipaligning final APK..."
$FinalApk = Join-Path $DistDir "Gen5WThemer.apk"
if (Test-Path $FinalApk) { Remove-Item $FinalApk -Force }
& $ZipalignExe -f 4 $SignedUnalignedApk $FinalApk
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

Write-Host "==> Assembling NEMESIS Package and USB Installer ZIP archives..."
$NemesisZip = Join-Path $DistDir "gen5w.nemesis.themer.zip"
if (Test-Path $NemesisZip) { Remove-Item $NemesisZip -Force }

$NemesisDataFile = Join-Path $ProjectRoot "nemesis-package\NEMESIS.data"
$RawNemesisData = [System.IO.File]::ReadAllText($NemesisDataFile) -replace "`r`n", "`n"
foreach ($line in ($RawNemesisData -split "`n")) {
    if ($line -match "^short-desc=(.*)$" -and $Matches[1].Length -gt 64) {
        throw "NEMESIS validation error: short-desc exceeds 64 characters ($($Matches[1].Length) chars)"
    }
    if ($line -match "^detailed-desc=(.*)$" -and $Matches[1].Length -gt 256) {
        throw "NEMESIS validation error: detailed-desc exceeds 256 characters ($($Matches[1].Length) chars)"
    }
}
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($NemesisDataFile, $RawNemesisData, $Utf8NoBom)

$HelperScriptFile = Join-Path $ProjectRoot "nemesis-package\svc\themer-helper.sh"
$RawHelperScript = [System.IO.File]::ReadAllText($HelperScriptFile) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($HelperScriptFile, $RawHelperScript, $Utf8NoBom)

$PkgArchive = [System.IO.Compression.ZipFile]::Open($NemesisZip, [System.IO.Compression.ZipArchiveMode]::Create)
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($PkgArchive, $NemesisDataFile, "NEMESIS.data") | Out-Null
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($PkgArchive, $FinalApk, "app/Gen5WThemer.apk") | Out-Null
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($PkgArchive, $HelperScriptFile, "svc/themer-helper.sh") | Out-Null
$PkgArchive.Dispose()

$UsbDataFile = Join-Path $ProjectRoot "nemesis-usb\NEMESIS.data"
$RawUsbData = [System.IO.File]::ReadAllText($UsbDataFile) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($UsbDataFile, $RawUsbData, $Utf8NoBom)

$UsbBundleZip = Join-Path $DistDir "gen5w.nemesis.themer-usb.zip"
if (Test-Path $UsbBundleZip) { Remove-Item $UsbBundleZip -Force }
$UsbArchive = [System.IO.Compression.ZipFile]::Open($UsbBundleZip, [System.IO.Compression.ZipArchiveMode]::Create)
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($UsbArchive, $UsbDataFile, "NEMESIS.data") | Out-Null
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($UsbArchive, $NemesisZip, "packages/gen5w.nemesis.themer.zip") | Out-Null
$UsbArchive.Dispose()

Write-Host "BUILD SUCCESSFUL: $UsbBundleZip"
