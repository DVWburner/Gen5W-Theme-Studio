param(
    [string]$ConfigPath = "",
    [string]$CustomAssetsDir = "",
    [string]$OutputSubdir = "lcars"
)

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$cwebp = Join-Path $rootDir "tools\cwebp.exe"
if (-not (Test-Path $cwebp)) {
    $cwebp = Join-Path $rootDir ".build-tools\webp\cwebp.exe"
}
$nightIconsFile = Join-Path $rootDir "tools\night-icons.txt"
$allAppIconsFile = Join-Path $rootDir "tools\all-app-icons.txt"
$safeSubdir = ($OutputSubdir -replace "[^a-zA-Z0-9_-]", "")
if (-not $safeSubdir) { $safeSubdir = "lcars" }
$themeOutDir = Join-Path $rootDir "app\src\main\assets\themes\$safeSubdir"
$tempPngDir = Join-Path $rootDir "build\lcars_png_tmp"
$distDir = Join-Path $rootDir "dist"
if (-not $ConfigPath) { $ConfigPath = Join-Path $rootDir "studio\theme-config.json" }
if (-not $CustomAssetsDir) { $CustomAssetsDir = Join-Path $rootDir "studio\custom-assets" }

$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if (Test-Path $themeOutDir) { Remove-Item -Recurse -Force $themeOutDir }
if (Test-Path $tempPngDir) { Remove-Item -Recurse -Force $tempPngDir }

New-Item -ItemType Directory -Force -Path (Join-Path $themeOutDir "res\layout") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $themeOutDir "res\drawable-hdpi") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $themeOutDir "res\drawable-night-hdpi") | Out-Null
New-Item -ItemType Directory -Force -Path $tempPngDir | Out-Null
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
New-Item -ItemType Directory -Force -Path $CustomAssetsDir | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not ("AlphaFadeHelper" -as [type])) {
    Add-Type -ReferencedAssemblies "System.Drawing" -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class AlphaFadeHelper {
    private static double SmoothStep(double u) {
        if (u <= 0.0) return 0.0;
        if (u >= 1.0) return 1.0;
        return u * u * (3.0 - 2.0 * u);
    }

    public static void ApplyMapFade(Bitmap bmp, int rx, int ry, int rw, int rh, string mode, double fadeWidth, int centerOpacityPct, Bitmap oemMaskBmp) {
        int w = bmp.Width;
        int h = bmp.Height;
        BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int byteCount = Math.Abs(bd.Stride) * h;
        byte[] pixels = new byte[byteCount];
        Marshal.Copy(bd.Scan0, pixels, 0, byteCount);

        double minAlphaRatio = Math.Max(0.0, Math.Min(1.0, centerOpacityPct / 100.0));

        if (mode == "oem-alpha") {
            if (oemMaskBmp != null && oemMaskBmp.Width == w && oemMaskBmp.Height == h) {
                BitmapData md = oemMaskBmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                byte[] maskPx = new byte[byteCount];
                Marshal.Copy(md.Scan0, maskPx, 0, byteCount);
                oemMaskBmp.UnlockBits(md);

                for (int i = 0; i < byteCount; i += 4) {
                    double mA = maskPx[i + 3] / 255.0;
                    double norm = Math.Max(0.0, Math.Min(1.0, (mA - 0.31) / (1.0 - 0.31)));
                    double eff = minAlphaRatio + (1.0 - minAlphaRatio) * norm;
                    pixels[i + 3] = (byte)Math.Round(pixels[i + 3] * eff);
                }
            } else {
                // Mathematical left-edge fade curve matching Gen5W split-screen map blend (X=1125..1245)
                for (int y = 0; y < h; y++) {
                    int rowOff = y * bd.Stride;
                    for (int x = 1125; x < w; x++) {
                        double u = Math.Max(0.0, Math.Min(1.0, (x - 1125.0) / 115.0));
                        double holeStrength = SmoothStep(u);
                        double eff = 1.0 - holeStrength * (1.0 - minAlphaRatio);
                        int idx = rowOff + (x * 4) + 3;
                        pixels[idx] = (byte)Math.Round(pixels[idx] * eff);
                    }
                }
            }
        } else {
            double F = Math.Max(1.0, fadeWidth);
            double FEdge = Math.Max(1.0, Math.Min(F * 0.35, 28.0));
            int x0 = Math.Max(0, rx);
            int y0 = Math.Max(0, ry);
            int x1 = Math.Min(w, rx + rw);
            int y1 = Math.Min(h, ry + rh);

            for (int y = y0; y < y1; y++) {
                double dT = y - ry;
                double dB = (ry + rh - 1) - y;
                double sT = (mode == "feather-left") ? SmoothStep(dT / FEdge) : SmoothStep(dT / F);
                double sB = (mode == "feather-left") ? SmoothStep(dB / FEdge) : SmoothStep(dB / F);
                double sY = sT * sB;
                int rowOff = y * bd.Stride;

                for (int x = x0; x < x1; x++) {
                    double dL = x - rx;
                    double dR = (rx + rw - 1) - x;
                    double sL = SmoothStep(dL / F);
                    double sR = (mode == "feather-left") ? SmoothStep(dR / FEdge) : SmoothStep(dR / F);
                    double holeStrength = sL * sR * sY;
                    double alphaMult = 1.0 - holeStrength * (1.0 - minAlphaRatio);
                    int idx = rowOff + (x * 4) + 3;
                    pixels[idx] = (byte)Math.Round(pixels[idx] * alphaMult);
                }
            }
        }

        Marshal.Copy(pixels, 0, bd.Scan0, byteCount);
        bmp.UnlockBits(bd);
    }
}
"@
}

function Parse-HexColor {
    param([string]$Hex, [int]$OverrideAlpha = -1)
    if (-not $Hex) { $Hex = "#3B82F6" }
    $h = $Hex.TrimStart('#')
    $a = 255; $r = 0; $g = 0; $b = 0
    if ($h.Length -eq 8) {
        $a = [Convert]::ToInt32($h.Substring(0, 2), 16)
        $r = [Convert]::ToInt32($h.Substring(2, 2), 16)
        $g = [Convert]::ToInt32($h.Substring(4, 2), 16)
        $b = [Convert]::ToInt32($h.Substring(6, 2), 16)
    } elseif ($h.Length -eq 6) {
        $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
    }
    if ($OverrideAlpha -ge 0) { $a = [Math]::Max(0, [Math]::Min(255, $OverrideAlpha)) }
    return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

function Save-WebpOrPng {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$RelPath
    )
    $fullOut = Join-Path $themeOutDir $RelPath
    $parent = Split-Path -Parent $fullOut
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    if ($RelPath.EndsWith(".png")) {
        $Bitmap.Save($fullOut, [System.Drawing.Imaging.ImageFormat]::Png)
    } else {
        $tmpPng = Join-Path $tempPngDir ([Guid]::NewGuid().ToString("N") + ".png")
        $Bitmap.Save($tmpPng, [System.Drawing.Imaging.ImageFormat]::Png)
        & $cwebp -quiet -lossless -z 6 $tmpPng -o $fullOut | Out-Null
        Remove-Item -Force $tmpPng -ErrorAction SilentlyContinue
    }
}

function New-RoundedRectPath {
    param([float]$X, [float]$Y, [float]$W, [float]$H, [float]$R)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($R -le 0.5) {
        $path.AddRectangle((New-Object System.Drawing.RectangleF($X, $Y, $W, $H)))
        return $path
    }
    $d = [Math]::Max(2.0, $R * 2.0)
    if ($d -gt $W) { $d = $W }
    if ($d -gt $H) { $d = $H }
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-StarfleetDeltaPath {
    param([float]$Cx, [float]$Cy, [float]$Scale)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $pts = @(
        (New-Object System.Drawing.PointF($Cx, ($Cy - 42 * $Scale))),
        (New-Object System.Drawing.PointF(($Cx + 28 * $Scale), ($Cy + 36 * $Scale))),
        (New-Object System.Drawing.PointF(($Cx + 4 * $Scale), ($Cy + 14 * $Scale))),
        (New-Object System.Drawing.PointF(($Cx - 26 * $Scale), ($Cy + 38 * $Scale)))
    )
    $path.AddPolygon($pts)
    return $path
}

function Draw-FittedImageInBox {
    param(
        [System.Drawing.Graphics]$G,
        [string]$ImgPath,
        [float]$BoxX = 0.0,
        [float]$BoxY = 0.0,
        [float]$TargetW,
        [float]$TargetH,
        [string]$Fit = "cover",
        [float]$ScalePct = 100.0,
        [float]$OffsetX = 0.0,
        [float]$OffsetY = 0.0,
        [float]$Alpha = 1.0
    )
    if (-not $ImgPath -or -not (Test-Path $ImgPath)) { return $false }
    $src = [System.Drawing.Bitmap]::FromFile($ImgPath)
    try {
        $sw = [float]$src.Width
        $sh = [float]$src.Height
        $scale = $ScalePct / 100.0
        $dw = $TargetW
        $dh = $TargetH
        if ($Fit -eq "cover") {
            $ratio = [Math]::Max($TargetW / $sw, $TargetH / $sh) * $scale
            $dw = $sw * $ratio
            $dh = $sh * $ratio
        } elseif ($Fit -eq "contain") {
            $ratio = [Math]::Min($TargetW / $sw, $TargetH / $sh) * $scale
            $dw = $sw * $ratio
            $dh = $sh * $ratio
        } else {
            $dw = $TargetW * $scale
            $dh = $TargetH * $scale
        }
        $dx = $BoxX + ($TargetW - $dw) / 2.0 + $OffsetX
        $dy = $BoxY + ($TargetH - $dh) / 2.0 + $OffsetY

        $G.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        if ($Alpha -lt 0.999) {
            $cm = New-Object System.Drawing.Imaging.ColorMatrix
            $cm.Matrix33 = $Alpha
            $ia = New-Object System.Drawing.Imaging.ImageAttributes
            $ia.SetColorMatrix($cm)
            $destRect = New-Object System.Drawing.Rectangle(([int][Math]::Round($dx)), ([int][Math]::Round($dy)), ([int][Math]::Round($dw)), ([int][Math]::Round($dh)))
            $G.DrawImage($src, $destRect, 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
            $ia.Dispose()
        } else {
            $G.DrawImage($src, $dx, $dy, $dw, $dh)
        }
        return $true
    } finally {
        $src.Dispose()
    }
}

function Draw-FittedImage {
    param(
        [System.Drawing.Graphics]$G,
        [string]$ImgPath,
        [float]$TargetW,
        [float]$TargetH,
        [string]$Fit = "cover",
        [float]$ScalePct = 100.0,
        [float]$OffsetX = 0.0,
        [float]$OffsetY = 0.0,
        [float]$Alpha = 1.0
    )
    return (Draw-FittedImageInBox -G $G -ImgPath $ImgPath -BoxX 0.0 -BoxY 0.0 -TargetW $TargetW -TargetH $TargetH -Fit $Fit -ScalePct $ScalePct -OffsetX $OffsetX -OffsetY $OffsetY -Alpha $Alpha)
}

Write-Host "[1/6] Generating byte-offset patch table for Launcher_WP3 layout XMLs (Zero OEM XML files distributed)..."
$basePatchesFile = Join-Path $rootDir "tools\layout-base-patches.txt"
$layoutPatchLines = @()
if (Test-Path $basePatchesFile) {
    $layoutPatchLines += Get-Content $basePatchesFile | Where-Object { $_.Trim() -ne "" }
}

$bwCfg = $cfg.batteryWidget
$bTxtOffX = if ($null -ne $bwCfg.battTextOffsetX) { [double]$bwCfg.battTextOffsetX } else { 0.0 }
$bTxtOffY = if ($null -ne $bwCfg.battTextOffsetY) { [double]$bwCfg.battTextOffsetY } else { 0.0 }
$rTxtOffX = if ($null -ne $bwCfg.rangeOffsetX)    { [double]$bwCfg.rangeOffsetX }    else { 0.0 }
$rTxtOffY = if ($null -ne $bwCfg.rangeOffsetY)    { [double]$bwCfg.rangeOffsetY }    else { 0.0 }

function Format-DpPatchPairs([int]$Offset, [int]$BaseDp, [double]$OffsetPx) {
    $dp = [int][Math]::Round($BaseDp + ($OffsetPx / 1.5))
    $mantissa = $dp -band 0xFFFFFF
    $val = [uint32](($mantissa -shl 8) -bor 1)
    $bytes = [BitConverter]::GetBytes($val)
    $pairs = @()
    for ($bi = 0; $bi -lt 4; $bi++) {
        $pairs += ("{0}:{1:X2}" -f ($Offset + $bi), $bytes[$bi])
    }
    return ($pairs -join ",")
}

function Format-SpPatchPairs([int]$Offset, [int]$SpVal) {
    $sp = [Math]::Max(8, $SpVal)
    $val = [uint32]((($sp -band 0xFFFFFF) -shl 8) -bor 2)
    $bytes = [BitConverter]::GetBytes($val)
    $pairs = @()
    for ($bi = 0; $bi -lt 4; $bi++) {
        $pairs += ("{0}:{1:X2}" -f ($Offset + $bi), $bytes[$bi])
    }
    return ($pairs -join ",")
}

if ($bTxtOffX -ne 0.0 -or $bTxtOffY -ne 0.0 -or $rTxtOffX -ne 0.0 -or $rTxtOffY -ne 0.0) {
    $evPairs = @(
        (Format-DpPatchPairs 1276 24  $bTxtOffY),
        (Format-DpPatchPairs 1336 126 $bTxtOffX),
        (Format-DpPatchPairs 1496 48  $bTxtOffY),
        (Format-DpPatchPairs 1516 110 $bTxtOffX),
        (Format-DpPatchPairs 2056 136 $rTxtOffY),
        (Format-DpPatchPairs 2076 393 $rTxtOffX)
    ) -join ","
    $layoutPatchLines += "res/layout/widget_ev_main_v2.xml|$evPairs"
}

$hsCfg = $cfg.homeScreen
$clkOffX  = if ($null -ne $hsCfg -and $null -ne $hsCfg.clockOffsetX)   { [double]$hsCfg.clockOffsetX }   else { 0.0 }
$clkOffY  = if ($null -ne $hsCfg -and $null -ne $hsCfg.clockOffsetY)   { [double]$hsCfg.clockOffsetY }   else { 0.0 }
$clkScale = if ($null -ne $hsCfg -and $null -ne $hsCfg.clockFontScale -and [double]$hsCfg.clockFontScale -gt 0) { [double]$hsCfg.clockFontScale } else { 100.0 }
$medOffX  = if ($null -ne $hsCfg -and $null -ne $hsCfg.mediaOffsetX)   { [double]$hsCfg.mediaOffsetX }   else { 0.0 }
$medOffY  = if ($null -ne $hsCfg -and $null -ne $hsCfg.mediaOffsetY)   { [double]$hsCfg.mediaOffsetY }   else { 0.0 }
$medScale = if ($null -ne $hsCfg -and $null -ne $hsCfg.mediaFontScale -and [double]$hsCfg.mediaFontScale -gt 0) { [double]$hsCfg.mediaFontScale } else { 100.0 }

if ($clkOffX -ne 0.0 -or $clkOffY -ne 0.0 -or $clkScale -ne 100.0) {
    $sFactor = $clkScale / 100.0
    $dateSp  = [Math]::Max(8,  [int][Math]::Round(24.0 * $sFactor))
    $dateH   = [Math]::Max(18, [int][Math]::Round(32.0 * $sFactor))
    $clkRowH = [Math]::Max(44, [int][Math]::Round(86.0 * $sFactor))
    $timeSp  = [Math]::Max(24, [int][Math]::Round(80.0 * $sFactor))
    $ampmSp  = [Math]::Max(8,  [int][Math]::Round(24.0 * $sFactor))

    $clkPatches = @(
        (Format-SpPatchPairs 692 $dateSp),
        (Format-DpPatchPairs 792 $dateH 0.0),
        (Format-DpPatchPairs 812 2 $clkOffY),
        (Format-DpPatchPairs 852 4 $clkOffX),
        (Format-DpPatchPairs 992 $clkRowH 0.0),
        "1020:06,1021:00,1022:00,1023:00,1031:05",
        (Format-DpPatchPairs 1032 0 $clkOffX),
        (Format-SpPatchPairs 1088 $timeSp),
        (Format-DpPatchPairs 1188 $clkRowH 0.0),
        (Format-SpPatchPairs 1288 $ampmSp)
    ) -join ","
    $layoutPatchLines += "res/layout/widget_digital_clock_small_v3_large.xml|$clkPatches"
}

$utf8NoBomInit = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $themeOutDir "layout-patches.txt"), $layoutPatchLines, $utf8NoBomInit)

$fontFamilyChoice = if ($null -ne $hsCfg -and $hsCfg.fontFamily) { [string]$hsCfg.fontFamily } else { "oem" }
$script:ResolvedThemeFontFile = ""
$script:GdiTileFontName = "Segoe UI"
$winFontsDir = Join-Path $env:WINDIR "Fonts"
switch ($fontFamilyChoice) {
    "bahnschrift" {
        $script:GdiTileFontName = "Bahnschrift"
        $cand = Join-Path $winFontsDir "bahnschrift.ttf"
        if (Test-Path $cand) { $script:ResolvedThemeFontFile = $cand }
    }
    "consolas" {
        $script:GdiTileFontName = "Consolas"
        $cand = Join-Path $winFontsDir "consolab.ttf"
        if (-not (Test-Path $cand)) { $cand = Join-Path $winFontsDir "consola.ttf" }
        if (Test-Path $cand) { $script:ResolvedThemeFontFile = $cand }
    }
    "trebuchet" {
        $script:GdiTileFontName = "Trebuchet MS"
        $cand = Join-Path $winFontsDir "trebucbd.ttf"
        if (-not (Test-Path $cand)) { $cand = Join-Path $winFontsDir "trebuc.ttf" }
        if (Test-Path $cand) { $script:ResolvedThemeFontFile = $cand }
    }
    "impact" {
        $script:GdiTileFontName = "Impact"
        $cand = Join-Path $winFontsDir "impact.ttf"
        if (Test-Path $cand) { $script:ResolvedThemeFontFile = $cand }
    }
    "custom" {
        if ($hsCfg.customFontFile) {
            $cand = Join-Path $CustomAssetsDir ([string]$hsCfg.customFontFile)
            if (Test-Path $cand) { $script:ResolvedThemeFontFile = $cand }
        }
    }
}

if ($script:ResolvedThemeFontFile -and (Test-Path $script:ResolvedThemeFontFile)) {
    $launcherFontsDir = Join-Path $themeOutDir "assets\fonts"
    New-Item -ItemType Directory -Force -Path $launcherFontsDir | Out-Null
    Copy-Item $script:ResolvedThemeFontFile (Join-Path $launcherFontsDir "CubeN.ttf") -Force
}

$cOrange  = Parse-HexColor $cfg.colors.primary
$cPeach   = Parse-HexColor $cfg.colors.secondary
$cMagenta = Parse-HexColor $cfg.colors.tertiary
$cBlue    = Parse-HexColor $cfg.colors.accentBlue
$cRed     = Parse-HexColor $cfg.colors.alertRed
$cCyan    = Parse-HexColor $cfg.colors.sensorCyan

function Draw-AllAppsBg {
    param([bool]$IsNight)
    $aa = $cfg.allApps
    $bmp = New-Object System.Drawing.Bitmap(1920, 720, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    if ($aa.bgMode -eq "oem") {
        $g.Clear([System.Drawing.Color]::FromArgb(255, 18, 18, 20))
    } else {
        $bgTop = if ($IsNight) { Parse-HexColor $cfg.colors.bgNightTop } else { Parse-HexColor $cfg.colors.bgDayTop }
        $bgBot = if ($IsNight) { Parse-HexColor $cfg.colors.bgNightBot } else { Parse-HexColor $cfg.colors.bgDayBot }
        $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point(0, 0)),
            (New-Object System.Drawing.Point(1920, 720)),
            $bgTop, $bgBot
        )
        $g.FillRectangle($bgBrush, 0, 0, 1920, 720)
        $bgBrush.Dispose()

        $customFile = if ($IsNight -and $aa.customBgNightFile) { [string]$aa.customBgNightFile } else { [string]$aa.customBgFile }
        if ($aa.bgMode -eq "custom" -and $customFile) {
            $customFull = Join-Path $CustomAssetsDir $customFile
            $drewCustom = Draw-FittedImage -G $g -ImgPath $customFull -TargetW 1920 -TargetH 720 `
                -Fit ([string]$aa.bgFit) -ScalePct ([float]$aa.bgScale) `
                -OffsetX ([float]$aa.bgOffsetX) -OffsetY ([float]$aa.bgOffsetY)
            if ($drewCustom -and ([int]$aa.bgDim) -gt 0) {
                $dimAlpha = [int][Math]::Round(([float]$aa.bgDim / 100.0) * 255)
                $dimBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($dimAlpha, 0, 0, 0))
                $g.FillRectangle($dimBrush, 0, 0, 1920, 720)
                $dimBrush.Dispose()
            }
        }
    }

    $gridOp = [int]$aa.gridOpacity
    if ($gridOp -gt 0) {
        $gridPen = New-Object System.Drawing.Pen((Parse-HexColor $cfg.colors.accentBlue $gridOp), 1)
        for ($x = 90; $x -lt 1890; $x += 80) { $g.DrawLine($gridPen, $x, 96, $x, 675) }
        for ($y = 110; $y -lt 675; $y += 80) { $g.DrawLine($gridPen, 70, $y, 1890, $y) }
        $gridPen.Dispose()
    }

    $wmOp = [int]$aa.deltaWatermarkOpacity
    if ($wmOp -gt 0) {
        $ringPen = New-Object System.Drawing.Pen((Parse-HexColor $cfg.colors.primary $wmOp), 1.5)
        $g.DrawEllipse($ringPen, 960 - 240, 385 - 240, 480, 480)
        $g.DrawEllipse($ringPen, 960 - 340, 385 - 340, 680, 680)
        $ringPen.Dispose()

        $deltaPath = New-StarfleetDeltaPath -Cx 960 -Cy 390 -Scale ([float]$aa.deltaWatermarkScale)
        $deltaBrush = New-Object System.Drawing.SolidBrush((Parse-HexColor $cfg.colors.primary $wmOp))
        $deltaPen = New-Object System.Drawing.Pen((Parse-HexColor $cfg.colors.secondary ([Math]::Min(255, $wmOp * 2))), 2)
        $g.FillPath($deltaBrush, $deltaPath)
        $g.DrawPath($deltaPen, $deltaPath)
        $deltaBrush.Dispose(); $deltaPen.Dispose(); $deltaPath.Dispose()
    }

    if ($aa.showLcarsFrame -eq $true) {
        $bOrange  = New-Object System.Drawing.SolidBrush($cOrange)
        $bPeach   = New-Object System.Drawing.SolidBrush($cPeach)
        $bMagenta = New-Object System.Drawing.SolidBrush($cMagenta)
        $bBlue    = New-Object System.Drawing.SolidBrush($cBlue)
        $bRed     = New-Object System.Drawing.SolidBrush($cRed)

        $lx = [int]$aa.leftSpineX
        $lw = [int]$aa.leftSpineWidth
        $ty = [int]$aa.topBarY
        $th = [int]$aa.topBarHeight
        $ew = [int]$aa.elbowWidth
        $er = [float]$aa.elbowRadius
        $ir = [float]$aa.innerCutRadius
        $by = [int]$aa.botBarY
        $bh = [int]$aa.botBarHeight

        $topElbow = New-RoundedRectPath -X $lx -Y $ty -W $ew -H 175 -R $er
        $topCut   = New-RoundedRectPath -X ($lx + $lw) -Y ($ty + $th) -W ($ew - $lw + 20) -H 170 -R $ir
        $regTop = New-Object System.Drawing.Region($topElbow)
        $regTop.Exclude($topCut)
        $g.FillRegion($bOrange, $regTop)
        $regTop.Dispose(); $topElbow.Dispose(); $topCut.Dispose()

        $segStart = $lx + $ew + 8
        $g.FillRectangle($bPeach,   $segStart,       $ty, 240, $th)
        $g.FillRectangle($bMagenta, $segStart + 248, $ty, 180, $th)
        $g.FillRectangle($bBlue,    $segStart + 436, $ty, 500, $th)
        $g.FillRectangle($bOrange,  $segStart + 944, $ty, 300, $th)
        $g.FillRectangle($bRed,     $segStart + 1252, $ty, 210, $th)
        $endCapTop = New-RoundedRectPath -X 1852 -Y $ty -W 54 -H $th -R ([float]($th / 2.0))
        $g.FillPath($bPeach, $endCapTop); $endCapTop.Dispose()

        $g.FillRectangle($bPeach,   $lx, $ty + 182, $lw, 110)
        $g.FillRectangle($bMagenta, $lx, $ty + 300, $lw, 98)
        $g.FillRectangle($bBlue,    $lx, $ty + 406, $lw, 90)

        $botElbowH = ($by + $bh) - ($ty + 502)
        $botElbow = New-RoundedRectPath -X $lx -Y ($ty + 502) -W $ew -H $botElbowH -R $er
        $botCut   = New-RoundedRectPath -X ($lx + $lw) -Y ($ty + 485) -W ($ew - $lw + 20) -H ($botElbowH + 17 - $bh) -R $ir
        $regBot = New-Object System.Drawing.Region($botElbow)
        $regBot.Exclude($botCut)
        $g.FillRegion($bBlue, $regBot)
        $regBot.Dispose(); $botElbow.Dispose(); $botCut.Dispose()

        $cutX = [int]$aa.pageDotCutoutX
        $cutW = [int]$aa.pageDotCutoutW
        $leftBotW = [Math]::Max(40, $cutX - $segStart - 8)
        $g.FillRectangle($bMagenta, $segStart, $by, 180, $bh)
        if ($leftBotW -gt 188) {
            $g.FillRectangle($bOrange, $segStart + 188, $by, ($leftBotW - 188), $bh)
        }
        $rightBotX = $cutX + $cutW + 8
        $g.FillRectangle($bPeach, $rightBotX, $by, 260, $bh)
        $g.FillRectangle($bBlue,  $rightBotX + 268, $by, 310, $bh)
        $g.FillRectangle($bRed,   $rightBotX + 586, $by, 195, $bh)
        $endCapBot = New-RoundedRectPath -X 1852 -Y $by -W 54 -H $bh -R ([float]($bh / 2.0))
        $g.FillPath($bOrange, $endCapBot); $endCapBot.Dispose()

        $fontTitle = New-Object System.Drawing.Font("Arial Narrow", 13.5, [System.Drawing.FontStyle]::Bold)
        $fontTiny  = New-Object System.Drawing.Font("Arial", 8.5, [System.Drawing.FontStyle]::Bold)
        $bBlack    = [System.Drawing.Brushes]::Black

        $modeLabel = if ($IsNight) { [string]$aa.titleNight } else { [string]$aa.titleDay }
        if ($modeLabel) { $g.DrawString($modeLabel, $fontTitle, $bPeach, ($lx + $lw + 18), ($ty + $th + 3)) }
        if ($aa.subtitleRight) { $g.DrawString([string]$aa.subtitleRight, $fontTitle, $bBlue, 1345, ($ty + $th + 3)) }
        if ($aa.sectorLabel) { $g.DrawString([string]$aa.sectorLabel, $fontTiny, $bBlack, ($segStart + 448), ($ty + 2)) }
        if ($leftBotW -gt 260 -and $aa.bottomLabel) {
            $g.DrawString([string]$aa.bottomLabel, $fontTiny, $bBlack, ($segStart + 198), ($by + 1))
        }

        $fontTitle.Dispose(); $fontTiny.Dispose()
        $bOrange.Dispose(); $bPeach.Dispose(); $bMagenta.Dispose(); $bBlue.Dispose(); $bRed.Dispose()
    }

    $g.Dispose()
    return $bmp
}

Write-Host "[2/6] Generating All-Apps Console Backgrounds (1920x720 Day & Night)..."
$bgDay = Draw-AllAppsBg -IsNight $false
Save-WebpOrPng -Bitmap $bgDay -RelPath "res\drawable-hdpi\home_bg.webp"
$bgNight = Draw-AllAppsBg -IsNight $true
Save-WebpOrPng -Bitmap $bgNight -RelPath "res\drawable-night-hdpi\home_bg.webp"
$bgNight.Dispose()

function Draw-HomeOverlay {
    param([bool]$IsNight)
    $hs = $cfg.homeScreen

    $bmp = New-Object System.Drawing.Bitmap(1920, 720, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

    $divX = [int]$hs.dividerX
    $divW = [int]$hs.dividerWidth
    $topMaskH = [int]$hs.topMaskHeight
    $botMaskY = [int]$hs.botMaskY
    $mapRightX = [int]$hs.mapBorderRightX
    $mapRightW = [int]$hs.mapBorderRightW
    $mTopY = [int]$hs.mapBorderTopY
    $mTopH = [int]$hs.mapBorderTopH
    $mBotY = [int]$hs.mapBorderBotY
    $mBotH = [int]$hs.mapBorderBotH

    $mapViewX = $divX + $divW + 6
    $mapViewY = $mTopY + $mTopH
    $mapViewW = [Math]::Max(50, $mapRightX - $mapViewX)
    $mapViewH = [Math]::Max(50, $mBotY - $mapViewY)
    $mapCutPath = New-RoundedRectPath -X $mapViewX -Y $mapViewY -W $mapViewW -H $mapViewH -R ([float]$hs.mapCutoutRadius)

    $fadeMode = if ($hs.mapFadeMode) { [string]$hs.mapFadeMode } else { "feather" }
    $fadeWidth = if ($null -ne $hs.mapFadeWidth) { [double]$hs.mapFadeWidth } else { 75.0 }
    $centerOpacity = if ($null -ne $hs.mapCenterOpacity) { [int]$hs.mapCenterOpacity } else { 0 }
    $homeFit = if ($hs.bgFit) { [string]$hs.bgFit } else { "cover" }

    if ($fadeMode -eq "hard") {
        $fullReg = New-Object System.Drawing.Region((New-Object System.Drawing.Rectangle(0, 0, 1920, 720)))
        $fullReg.Exclude($mapCutPath)
        $g.SetClip($fullReg, [System.Drawing.Drawing2D.CombineMode]::Replace)
        $fullReg.Dispose()
    }

    $leftBg = if ($IsNight) { Parse-HexColor $cfg.colors.bgNightTop 252 } else { Parse-HexColor $cfg.colors.bgDayTop 248 }
    $leftBrush = New-Object System.Drawing.SolidBrush($leftBg)
    $g.FillRectangle($leftBrush, 0, 0, 1920, 720)
    $leftBrush.Dispose()

    $customHomeFile = ""
    if ($hs.bgMode -eq "custom" -and $hs.customBgFile) {
        $customHomeFile = [string]$hs.customBgFile
    } elseif ($hs.bgMode -eq "sameAsAllApps" -and $cfg.allApps.customBgFile) {
        $customHomeFile = [string]$cfg.allApps.customBgFile
    }
    if ($customHomeFile) {
        $customFull = Join-Path $CustomAssetsDir $customHomeFile
        $drewHome = Draw-FittedImage -G $g -ImgPath $customFull -TargetW 1920 -TargetH 720 `
            -Fit $homeFit -ScalePct ([float]$hs.bgScale) `
            -OffsetX ([float]$hs.bgOffsetX) -OffsetY ([float]$hs.bgOffsetY)
        if ($drewHome -and ([int]$hs.bgDim) -gt 0) {
            $dimAlpha = [int][Math]::Round(([float]$hs.bgDim / 100.0) * 255)
            $dimBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($dimAlpha, 0, 0, 0))
            $g.FillRectangle($dimBrush, 0, 0, 1920, 720)
            $dimBrush.Dispose()
        }
    }

    $g.ResetClip()

    if ($fadeMode -ne "hard") {
        [AlphaFadeHelper]::ApplyMapFade($bmp, $mapViewX, $mapViewY, $mapViewW, $mapViewH, $fadeMode, $fadeWidth, $centerOpacity, $null)
    }

    if ($hs.showLcarsFrame -ne $true) {
        if (([float]$hs.mapCutoutBorderW) -gt 0) {
            $pMap = New-Object System.Drawing.Pen((Parse-HexColor $hs.mapCutoutBorderColor), ([float]$hs.mapCutoutBorderW))
            $g.DrawPath($pMap, $mapCutPath)
            $pMap.Dispose()
        }
    } else {
        $gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22, 153, 204, 255), 1)
        for ($x = 70; $x -lt $divX; $x += 70) { $g.DrawLine($gridPen, $x, 90, $x, $botMaskY - 12) }
        for ($y = 95; $y -lt ($botMaskY - 12); $y += 70) { $g.DrawLine($gridPen, 45, $y, ($divX - 6), $y) }
        $gridPen.Dispose()

        $deltaPath = New-StarfleetDeltaPath -Cx 430 -Cy 365 -Scale 3.2
        $deltaBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(24, 255, 153, 0))
        $g.FillPath($deltaBrush, $deltaPath)
        $deltaBrush.Dispose(); $deltaPath.Dispose()

        $bOrange  = New-Object System.Drawing.SolidBrush($cOrange)
        $bPeach   = New-Object System.Drawing.SolidBrush($cPeach)
        $bMagenta = New-Object System.Drawing.SolidBrush($cMagenta)
        $bBlue    = New-Object System.Drawing.SolidBrush($cBlue)
        $bRed     = New-Object System.Drawing.SolidBrush($cRed)

        $lbX = [int]$hs.leftBarX
        $lbW = [int]$hs.leftBarWidth

        $g.FillRectangle($bOrange,  $lbX, ($mTopY + 8),  $lbW, 155)
        $g.FillRectangle($bPeach,   $lbX, ($mTopY + 171), $lbW, 128)
        $g.FillRectangle($bMagenta, $lbX, ($mTopY + 307), $lbW, 128)
        $g.FillRectangle($bBlue,    $lbX, ($mTopY + 443), $lbW, 162)

        $g.FillRectangle($bOrange,  ($lbX + $lbW + 6), $mTopY, 330, $mTopH)
        $g.FillRectangle($bPeach,   ($lbX + $lbW + 344), $mTopY, 220, $mTopH)
        $g.FillRectangle($bBlue,    ($lbX + $lbW + 572), $mTopY, ($divX - ($lbX + $lbW + 580)), $mTopH)

        $g.FillRectangle($bOrange,  $divX, $mTopY,  $divW, 185)
        $g.FillRectangle($bRed,     $divX, ($mTopY + 193), $divW, 92)
        $g.FillRectangle($bPeach,   $divX, ($mTopY + 293), $divW, 140)
        $g.FillRectangle($bBlue,    $divX, ($mTopY + 441), $divW, 183)

        $mapLeftX = $divX + $divW + 6
        $g.FillRectangle($bPeach,   $mapLeftX, $mTopY, 370, $mTopH)
        $g.FillRectangle($bMagenta, ($mapLeftX + 378), $mTopY, 210, $mTopH)
        $g.FillRectangle($bOrange,  ($mapLeftX + 596), $mTopY, ($mapRightX - ($mapLeftX + 596)), $mTopH)
        $g.FillRectangle($bOrange,  $mapRightX, ($mTopY + $mTopH), $mapRightW, 280)
        $g.FillRectangle($bBlue,    $mapRightX, ($mTopY + $mTopH + 288), $mapRightW, 312)
        $g.FillRectangle($bBlue,    $mapLeftX, $mBotY, 450, $mBotH)
        $g.FillRectangle($bPeach,   ($mapLeftX + 458), $mBotY, ($mapRightX + $mapRightW - ($mapLeftX + 458)), $mBotH)

        $g.FillRectangle($bBlue,     ($lbX + $lbW + 6), $mBotY, 410, $mBotH)
        $g.FillRectangle($bMagenta,  ($lbX + $lbW + 424), $mBotY, 230, $mBotH)
        $g.FillRectangle($bOrange,   ($lbX + $lbW + 662), $mBotY, 175, $mBotH)

        $fontTiny = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
        if ($hs.leftTitle)  { $g.DrawString([string]$hs.leftTitle,  $fontTiny, $bPeach,  ($lbX + $lbW + 14), ($mTopY + $mTopH + 6)) }
        if ($hs.rightTitle) { $g.DrawString([string]$hs.rightTitle, $fontTiny, $bOrange, ($mapLeftX + 12),   ($mTopY + $mTopH + 6)) }
        $fontTiny.Dispose()

        $bOrange.Dispose(); $bPeach.Dispose(); $bMagenta.Dispose(); $bBlue.Dispose(); $bRed.Dispose()
    }

    $mapCutPath.Dispose(); $g.Dispose()
    return $bmp
}

function Draw-StellarCartography {
    $bmp = New-Object System.Drawing.Bitmap(837, 720, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(255, 6, 9, 20))
    $penGrid = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30, 51, 204, 255), 1)
    for ($r = 80; $r -le 560; $r += 80) {
        $g.DrawEllipse($penGrid, 418 - [int]($r/2), 360 - [int]($r/2), $r, $r)
    }
    $penGrid.Dispose(); $g.Dispose()
    return $bmp
}

Write-Host "[3/6] Generating Home Screen Split-Screen & Map Overlays..."
if ($cfg.homeScreen.bgMode -ne "oem") {
    $homeMapDay = Draw-HomeOverlay -IsNight $false
    Save-WebpOrPng -Bitmap $homeMapDay -RelPath "res\drawable-hdpi\home_bg_weather_map.webp"
    $homeMapDay.Dispose()

    $homeMapNight = Draw-HomeOverlay -IsNight $true
    Save-WebpOrPng -Bitmap $homeMapNight -RelPath "res\drawable-night-hdpi\home_bg_weather_map.webp"
    $homeMapNight.Dispose()

    $stellarBmp = Draw-StellarCartography
    Save-WebpOrPng -Bitmap $stellarBmp -RelPath "res\drawable-hdpi\home_bg_weather_map_default.webp"
    Save-WebpOrPng -Bitmap $stellarBmp -RelPath "res\drawable-night-hdpi\home_bg_weather_map_default.webp"
    $stellarBmp.Dispose()
}

function Draw-TileBackgroundOnGraphics {
    param(
        [System.Drawing.Graphics]$G,
        [string]$Style,
        [string]$CustomFile,
        [string]$CustomFit = "cover",
        [float]$CustomScale = 100.0,
        [float]$CustomOffsetX = 0.0,
        [float]$CustomOffsetY = 0.0,
        [string]$FillHex = "#0A0F1E",
        [int]$FillOpacity = 220,
        [string]$BorderHex = "#3B82F6",
        [bool]$IsPushed = $false,
        [float]$AlphaMultiplier = 1.0
    )
    $tCfg = $cfg.tile
    if (-not $Style -or $Style -eq "none") { return }

    if ($Style -eq "oem") {
        if ($IsPushed) {
            $pushPath = New-RoundedRectPath -X 10.0 -Y 10.0 -W 286.0 -H 234.0 -R 24.0
            $pushBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int][Math]::Round(75 * $AlphaMultiplier), 255, 255, 255))
            $G.FillPath($pushBrush, $pushPath)
            $pushBrush.Dispose(); $pushPath.Dispose()
        }
        return
    }

    $cardX  = [float]$tCfg.cardX
    $cardY  = [float]$tCfg.cardY
    $cardW  = [float]$tCfg.cardW
    $cardH  = [float]$tCfg.cardH
    $rad    = [float]$tCfg.cornerRadius
    $spineW = [float]$tCfg.leftSpineW
    $topH   = [float]$tCfg.topBarH
    $botH   = [float]$tCfg.botBarH
    $bw     = [float]$tCfg.borderWidth

    $outerPath = New-RoundedRectPath -X $cardX -Y $cardY -W $cardW -H $cardH -R $rad

    if ($Style -eq "custom") {
        if ($CustomFile) {
            $fullCustom = Join-Path $CustomAssetsDir $CustomFile
            if (Test-Path $fullCustom) {
                $G.SetClip($outerPath)
                Draw-FittedImageInBox -G $G -ImgPath $fullCustom -BoxX $cardX -BoxY $cardY -TargetW $cardW -TargetH $cardH `
                    -Fit $CustomFit -ScalePct $CustomScale -OffsetX $CustomOffsetX -OffsetY $CustomOffsetY -Alpha $AlphaMultiplier | Out-Null
                $G.ResetClip()
                if ($bw -gt 0) {
                    $bCol = Parse-HexColor $BorderHex ([int][Math]::Round(255 * $AlphaMultiplier))
                    $borderPen = New-Object System.Drawing.Pen($bCol, $bw)
                    $G.DrawPath($borderPen, $outerPath)
                    $borderPen.Dispose()
                }
            }
        }
        $outerPath.Dispose()
        return
    }

    $effFillOp = [int][Math]::Round($FillOpacity * $AlphaMultiplier)
    $fillCol = if ($IsPushed) { Parse-HexColor $cfg.colors.tileBgPush $effFillOp } else { Parse-HexColor $FillHex $effFillOp }
    $fillBrush = New-Object System.Drawing.SolidBrush($fillCol)
    $G.FillPath($fillBrush, $outerPath)
    $fillBrush.Dispose()

    $mainAlpha = [int][Math]::Round(255 * $AlphaMultiplier)
    $mainCol = if ($IsPushed) { [System.Drawing.Color]::FromArgb($mainAlpha, 59, 130, 246) } else { Parse-HexColor $BorderHex $mainAlpha }
    $subCol  = if ($IsPushed) { Parse-HexColor $cfg.colors.sensorCyan $mainAlpha } else { Parse-HexColor $cfg.colors.accentBlue $mainAlpha }

    if ($Style -eq "lcars") {
        $G.SetClip($outerPath)
        $bMain  = New-Object System.Drawing.SolidBrush($mainCol)
        $bSub   = New-Object System.Drawing.SolidBrush($subCol)
        $bPeach = New-Object System.Drawing.SolidBrush((Parse-HexColor $cfg.colors.secondary $mainAlpha))

        $G.FillRectangle($bMain, $cardX, $cardY, $spineW, ($cardH * 0.62))
        $G.FillRectangle($bMain, $cardX, $cardY, ($cardW * 0.48), $topH)
        $G.FillRectangle($bPeach, ($cardX + $cardW * 0.50), $cardY, ($cardW * 0.20), $topH)
        $G.FillRectangle($bSub, ($cardX + $cardW * 0.72), $cardY, ($cardW * 0.30), $topH)

        $G.FillRectangle($bSub, $cardX, ($cardY + $cardH * 0.65), $spineW, ($cardH * 0.36))
        $G.FillRectangle($bSub, $cardX, ($cardY + $cardH - $botH), ($cardW * 0.62), $botH)
        $G.FillRectangle($bMain, ($cardX + $cardW * 0.64), ($cardY + $cardH - $botH), ($cardW * 0.38), $botH)

        if ($spineW -ge 12 -and $tCfg.cornerCode) {
            $fontMicro = New-Object System.Drawing.Font("Arial", 6.0, [System.Drawing.FontStyle]::Bold)
            $G.DrawString([string]$tCfg.cornerCode, $fontMicro, [System.Drawing.Brushes]::Black, ($cardX + 2), ($cardY + $cardH * 0.52))
            $fontMicro.Dispose()
        }
        $G.ResetClip()
        $bMain.Dispose(); $bSub.Dispose(); $bPeach.Dispose()
    }

    if ($bw -gt 0) {
        $borderPen = New-Object System.Drawing.Pen($mainCol, $bw)
        $G.DrawPath($borderPen, $outerPath)
        $borderPen.Dispose()
    }

    $outerPath.Dispose()
}

Write-Host "[4/6] Generating Icon Tile Selector (Transparent Base + Pressed Highlight)..."
$tileNor = New-Object System.Drawing.Bitmap(306, 249, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gNor = [System.Drawing.Graphics]::FromImage($tileNor)
$gNor.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
$gNor.Dispose()
Save-WebpOrPng -Bitmap $tileNor -RelPath "res\drawable-hdpi\home_bg_icon_nor.webp"
Save-WebpOrPng -Bitmap $tileNor -RelPath "res\drawable-night-hdpi\home_bg_icon_nor.webp"

$tilePush = New-Object System.Drawing.Bitmap(306, 249, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gPush = [System.Drawing.Graphics]::FromImage($tilePush)
$gPush.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gPush.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$gPush.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
$tCfg = $cfg.tile
Draw-TileBackgroundOnGraphics -G $gPush -Style ([string]$tCfg.style) `
    -CustomFile ([string]$tCfg.customPushFile) -CustomFit ([string]$tCfg.customFit) `
    -CustomScale ([float]$tCfg.customScale) -CustomOffsetX ([float]$tCfg.customOffsetX) -CustomOffsetY ([float]$tCfg.customOffsetY) `
    -FillHex ([string]$cfg.colors.tileBgPush) -FillOpacity ([int]$tCfg.fillOpacity) -BorderHex ([string]$tCfg.borderColor) -IsPushed $true
$gPush.Dispose()
Save-WebpOrPng -Bitmap $tilePush -RelPath "res\drawable-hdpi\home_bg_icon_push.webp"
Save-WebpOrPng -Bitmap $tilePush -RelPath "res\drawable-night-hdpi\home_bg_icon_push.webp"
$tilePush.Dispose()

function Resolve-CanonicalIconKey {
    param([string]$CleanKey)
    if ($null -ne $cfg.icons.overrides.$CleanKey) { return $CleanKey }
    switch -Regex ($CleanKey) {
        "^hom_(seat|climate_handle_heat|climate_seat.*)_66$" { return "hom_climate_seat_66" }
        "^hom_(carplay|android|mirrorlink)_66$"              { return "hom_phone_projection_66" }
        "^hom_menual_66$"                                    { return "hom_webmenual_66" }
        "^hom_(k_carpay|kia_carpay)_66$"                     { return "hom_carpay_66" }
        "^hom_uvo_66$"                                       { return "hom_bluelink_66" }
        "^hom_(data|driv_info)_66$"                          { return "hom_hddata_66" }
        "^hom_(music_streaming|usb_image|usb_vidio)_66$"     { return "hom_media_66" }
        default                                              { return $CleanKey }
    }
}

function Get-DefaultFallbackLabel {
    param([string]$CleanKey)
    switch -Regex ($CleanKey) {
        "ev"             { return "EV" }
        "map"            { return "Map" }
        "navi"           { return "Navigation Menu" }
        "phone_proj|carplay|android|mirrorlink" { return "Phone|Projection" }
        "phone"          { return "Phone" }
        "vm"             { return "Voice Memo" }
        "seat|handle_heat" { return "Warmer/|Ventilation" }
        "climate"        { return "Climate" }
        "valet"          { return "Valet Mode" }
        "carpay"         { return "Hyundai Pay" }
        "quiet"          { return "Quiet Mode" }
        "settings"       { return "Setup" }
        "radio"          { return "Radio" }
        "media|music|usb"{ return "Media" }
        "hddata|data"    { return "HD Radio Data" }
        "bluelink|uvo"   { return "Bluelink" }
        "notification"   { return "Notifications" }
        "menual"         { return "User's Manual" }
        "soundofnature"  { return "Sounds of Nature" }
        "soundmood"      { return "Sound Mood" }
        "driver_talk"    { return "Passenger Talk" }
        "passenger_view" { return "Passenger View" }
        "aircleaner"     { return "Air Cleaner" }
        "nmode"          { return "N Mode" }
        "perfo_mode"     { return "Performance" }
        default          { return "" }
    }
}

function Draw-AppIcon {
    param(
        [string]$IconName,
        [bool]$IsDisabled
    )
    $rawCleanKey = $IconName -replace '_dis_66$', '_66'
    $cleanKey = Resolve-CanonicalIconKey -CleanKey $rawCleanKey
    $ov = $cfg.icons.overrides.$cleanKey

    $bmp = New-Object System.Drawing.Bitmap(306, 249, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

    $alphaFloat = if ($IsDisabled) { 0.45 } else { 1.0 }
    $alphaByte  = if ($IsDisabled) { 115 } else { 255 }

    # --- 1. Draw Independent or Global Tile Background (306x249) ---
    $tileMode = if ($null -ne $ov -and $ov.tileMode) { [string]$ov.tileMode } else { "global" }
    $tCfg = $cfg.tile
    if ($tileMode -eq "global") {
        Draw-TileBackgroundOnGraphics -G $g -Style ([string]$tCfg.style) `
            -CustomFile ([string]$tCfg.customNorFile) -CustomFit ([string]$tCfg.customFit) `
            -CustomScale ([float]$tCfg.customScale) -CustomOffsetX ([float]$tCfg.customOffsetX) -CustomOffsetY ([float]$tCfg.customOffsetY) `
            -FillHex ([string]$cfg.colors.tileBgNor) -FillOpacity ([int]$tCfg.fillOpacity) `
            -BorderHex ([string]$tCfg.borderColor) -IsPushed $false -AlphaMultiplier 1.0
    } elseif ($tileMode -ne "none") {
        $tFile = if ($ov.tileBgFile) { [string]$ov.tileBgFile } else { "" }
        $tFit  = if ($ov.tileFit) { [string]$ov.tileFit } else { "cover" }
        $tScale = if ($null -ne $ov.tileScale -and [float]$ov.tileScale -gt 0) { [float]$ov.tileScale } else { 100.0 }
        $tOffX  = if ($null -ne $ov.tileOffsetX) { [float]$ov.tileOffsetX } else { 0.0 }
        $tOffY  = if ($null -ne $ov.tileOffsetY) { [float]$ov.tileOffsetY } else { 0.0 }
        $tFill  = if ($ov.tileFillColor) { [string]$ov.tileFillColor } else { [string]$cfg.colors.tileBgNor }
        $tOp    = if ($null -ne $ov.tileFillOpacity) { [int]$ov.tileFillOpacity } else { [int]$tCfg.fillOpacity }
        $tBord  = if ($ov.tileBorderColor) { [string]$ov.tileBorderColor } else { [string]$tCfg.borderColor }

        Draw-TileBackgroundOnGraphics -G $g -Style $tileMode `
            -CustomFile $tFile -CustomFit $tFit `
            -CustomScale $tScale -CustomOffsetX $tOffX -CustomOffsetY $tOffY `
            -FillHex $tFill -FillOpacity $tOp -BorderHex $tBord -IsPushed $false -AlphaMultiplier 1.0
    }

    # --- 2. Draw App Icon Graphic (Default centered at X=153, Y=103.5, base 99x99) ---
    $effMode = [string]$cfg.icons.defaultMode
    if (-not $effMode) { $effMode = "oem" }
    if ($null -ne $ov -and $ov.mode -and $ov.mode -ne "default") {
        $effMode = [string]$ov.mode
    }

    $customPng = Join-Path $CustomAssetsDir "$cleanKey.png"
    if ($null -ne $ov -and $ov.customFile) {
        $customPng = Join-Path $CustomAssetsDir ([string]$ov.customFile)
    }

    $scalePct = if ($null -ne $ov -and $null -ne $ov.scale -and [float]$ov.scale -gt 0) { [float]$ov.scale } else { [float]$cfg.icons.globalScale }
    if ($scalePct -le 0) { $scalePct = 100.0 }
    $offX = if ($null -ne $ov -and $null -ne $ov.offsetX) { [float]$ov.offsetX } else { [float]$cfg.icons.globalOffsetX }
    $offY = if ($null -ne $ov -and $null -ne $ov.offsetY) { [float]$ov.offsetY } else { [float]$cfg.icons.globalOffsetY }
    $clipR = if ($null -ne $ov -and $null -ne $ov.clipRadius) { [float]$ov.clipRadius } else { [float]$cfg.icons.globalClipRadius }

    $iconBoxW = 99.0 * ($scalePct / 100.0)
    $iconBoxH = 99.0 * ($scalePct / 100.0)
    $iconBoxX = 153.0 - ($iconBoxW / 2.0) + $offX
    $iconBoxY = 103.5 - ($iconBoxH / 2.0) + $offY

    if ($effMode -eq "custom" -and (Test-Path $customPng)) {
        if ($clipR -gt 0) {
            $scaledClip = $clipR * ($scalePct / 100.0)
            $clipPath = New-RoundedRectPath -X $iconBoxX -Y $iconBoxY -W $iconBoxW -H $iconBoxH -R $scaledClip
            $g.SetClip($clipPath)
            $clipPath.Dispose()
        }
        Draw-FittedImageInBox -G $g -ImgPath $customPng -BoxX $iconBoxX -BoxY $iconBoxY -TargetW $iconBoxW -TargetH $iconBoxH `
            -Fit "contain" -ScalePct 100.0 -OffsetX 0.0 -OffsetY 0.0 -Alpha $alphaFloat | Out-Null
        if ($clipR -gt 0) { $g.ResetClip() }
    } elseif ($effMode -eq "oem") {
        # Record for runtime on-car compositing from the vehicle's built-in Launcher_WP3.apk
        [void]$script:CompositeOemIconsList.Add(("{0}:{1}:{2}:{3}" -f $IconName, $scalePct, $offX, $offY))
    } elseif ($effMode -ne "none") {
        $state = $g.Save()
        $g.TranslateTransform(153.0 + $offX, 103.5 + $offY)
        $g.ScaleTransform(($scalePct / 100.0), ($scalePct / 100.0))
        $g.TranslateTransform(-49.5, -49.5)

        $divColor = [System.Drawing.Color]::FromArgb($alphaByte, 255, 170, 0)
        $ringColor = [System.Drawing.Color]::FromArgb($alphaByte, 153, 204, 255)
        $badgeCode = "CMD"
        $glyph = "DELTA"

        if ($null -ne $ov) {
            if ($ov.badge)     { $badgeCode = [string]$ov.badge }
            if ($ov.divColor)  { $divColor  = Parse-HexColor $ov.divColor $alphaByte }
            if ($ov.ringColor) { $ringColor = Parse-HexColor $ov.ringColor $alphaByte }
            if ($ov.glyph)     { $glyph     = [string]$ov.glyph }
        }

        $penRing = New-Object System.Drawing.Pen($ringColor, ([float]$cfg.icons.ringWidth))
        $g.DrawArc($penRing, 8, 8, 83, 83, 130, 190)
        $g.DrawArc($penRing, 8, 8, 83, 83, 340, 120)
        $penRing.Dispose()

        $bOval = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int]($alphaByte * 0.25), $ringColor.R, $ringColor.G, $ringColor.B))
        $pOval = New-Object System.Drawing.Pen($ringColor, 1.5)
        $g.FillEllipse($bOval, 18, 30, 63, 40)
        $g.DrawEllipse($pOval, 18, 30, 63, 40)
        $bOval.Dispose(); $pOval.Dispose()

        $deltaPath = New-StarfleetDeltaPath -Cx 49.5 -Cy 48 -Scale ([float]$cfg.icons.deltaScale)
        $bDelta = New-Object System.Drawing.SolidBrush($divColor)
        $pDelta = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($alphaByte, 255, 245, 210), 2.0)
        $g.FillPath($bDelta, $deltaPath)
        $g.DrawPath($pDelta, $deltaPath)
        $bDelta.Dispose(); $pDelta.Dispose(); $deltaPath.Dispose()

        $pGlyph = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($alphaByte, 10, 14, 26), 2.5)
        $bGlyph = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alphaByte, 10, 14, 26))
        switch ($glyph) {
            "WARP"   { $g.DrawEllipse($pGlyph, 41, 38, 17, 17); $g.FillEllipse($bGlyph, 46, 43, 7, 7) }
            "ORBIT"  { $g.DrawEllipse($pGlyph, 39, 38, 21, 14); $g.FillEllipse($bGlyph, 47, 42, 6, 6) }
            "HELM"   { $g.DrawLine($pGlyph, 49.5, 34, 49.5, 56); $g.DrawLine($pGlyph, 39, 46, 60, 46) }
            "WAVE"   { $g.DrawArc($pGlyph, 40, 38, 19, 19, 200, 140); $g.DrawArc($pGlyph, 44, 42, 11, 11, 200, 140) }
            "HOLO"   { $g.DrawRectangle($pGlyph, 42, 39, 15, 15); $g.DrawLine($pGlyph, 42, 46, 57, 46); $g.DrawLine($pGlyph, 49, 39, 49, 54) }
            "LIFE"   { $g.FillRectangle($bGlyph, 47, 38, 5, 17); $g.FillRectangle($bGlyph, 41, 44, 17, 5) }
            "GEAR"   { $g.DrawEllipse($pGlyph, 42, 39, 15, 15); $g.DrawLine($pGlyph, 49.5, 36, 49.5, 57); $g.DrawLine($pGlyph, 39, 46.5, 60, 46.5) }
            default  { $g.DrawLine($pGlyph, 49.5, 37, 49.5, 55); $g.DrawLine($pGlyph, 41, 46, 58, 46) }
        }
        $pGlyph.Dispose(); $bGlyph.Dispose()

        $py = [float]$cfg.icons.pillY
        $ph = [float]$cfg.icons.pillH
        $pillPath = New-RoundedRectPath -X 22 -Y $py -W 55 -H $ph -R 7
        $bPill = New-Object System.Drawing.SolidBrush($divColor)
        $g.FillPath($bPill, $pillPath)
        $fontTag = New-Object System.Drawing.Font("Arial", 7.2, [System.Drawing.FontStyle]::Bold)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rectF = New-Object System.Drawing.RectangleF(22.0, $py, 55.0, $ph)
        $g.DrawString($badgeCode, $fontTag, [System.Drawing.Brushes]::Black, $rectF, $sf)
        $sf.Dispose(); $fontTag.Dispose(); $bPill.Dispose(); $pillPath.Dispose()

        $g.Restore($state)
    }

    # --- 3. Draw Per-Icon Custom Text Label ---
    $showText = if ($null -ne $cfg.icons.globalShowText) { [bool]$cfg.icons.globalShowText } else { $true }
    if ($null -ne $ov -and $null -ne $ov.showText) {
        $showText = [bool]$ov.showText
    }

    $labelText = if ($null -ne $ov -and $null -ne $ov.label) { [string]$ov.label } else { Get-DefaultFallbackLabel -CleanKey $cleanKey }

    if ($showText -and $labelText -ne "") {
        $txtHex = if ($null -ne $ov -and $ov.textColor) { [string]$ov.textColor } elseif ($cfg.icons.globalTextColor) { [string]$cfg.icons.globalTextColor } else { "#FFFFFF" }
        $txtSizePx = if ($null -ne $ov -and $null -ne $ov.textSize -and [float]$ov.textSize -gt 0) { [float]$ov.textSize } elseif ($cfg.icons.globalTextSize) { [float]$cfg.icons.globalTextSize } else { 25.0 }
        $txtOffX = if ($null -ne $ov -and $null -ne $ov.textOffsetX) { [float]$ov.textOffsetX } else { 0.0 }
        $txtOffY = if ($null -ne $ov -and $null -ne $ov.textOffsetY) { [float]$ov.textOffsetY } elseif ($null -ne $cfg.icons.globalTextOffsetY) { [float]$cfg.icons.globalTextOffsetY } else { 0.0 }

        $txtAlpha = if ($IsDisabled) { 110 } else { 255 }
        $txtCol   = Parse-HexColor $txtHex $txtAlpha
        $bTxt     = New-Object System.Drawing.SolidBrush($txtCol)
        $bShadow  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int]($txtAlpha * 0.65), 0, 0, 0))
        $fontLbl  = New-Object System.Drawing.Font($script:GdiTileFontName, $txtSizePx, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)

        $sfLbl = New-Object System.Drawing.StringFormat
        $sfLbl.Alignment = [System.Drawing.StringAlignment]::Center
        $sfLbl.LineAlignment = [System.Drawing.StringAlignment]::Near

        $lines = $labelText.Replace("\n", "|").Split('|')
        $lineHeight = $txtSizePx * 1.15
        $baseY = if ($lines.Count -gt 1) { 172.0 + $txtOffY } else { 184.0 + $txtOffY }

        for ($li = 0; $li -lt $lines.Count; $li++) {
            $lineStr = $lines[$li]
            $ly = $baseY + ($li * $lineHeight)
            $rectShadow = New-Object System.Drawing.RectangleF((8.0 + $txtOffX + 1.0), ($ly + 1.5), 290.0, ($lineHeight + 8.0))
            $rectMain   = New-Object System.Drawing.RectangleF((8.0 + $txtOffX), $ly, 290.0, ($lineHeight + 8.0))
            $g.DrawString($lineStr, $fontLbl, $bShadow, $rectShadow, $sfLbl)
            $g.DrawString($lineStr, $fontLbl, $bTxt, $rectMain, $sfLbl)
        }

        $sfLbl.Dispose(); $fontLbl.Dispose(); $bTxt.Dispose(); $bShadow.Dispose()
    }

    $g.Dispose()
    return $bmp
}

Write-Host "[5/6] Generating 90+ Full-Tile 306x249 App Icons (with Independent Tile Backgrounds & Labels)..."
$script:CompositeOemIconsList = New-Object 'System.Collections.Generic.List[string]'
$nightSet = New-Object 'System.Collections.Generic.HashSet[string]'
if (Test-Path $nightIconsFile) {
    Get-Content $nightIconsFile | ForEach-Object {
        if ($_.Trim()) { [void]$nightSet.Add($_.Trim()) }
    }
}
$iconBaseNames = @()
if (Test-Path $allAppIconsFile) {
    $iconBaseNames = @(Get-Content $allAppIconsFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
}
foreach ($baseName in $iconBaseNames) {
    $webpName = "$baseName.webp"
    $isDis = $baseName -like "*_dis_*"
    $iconBmp = Draw-AppIcon -IconName $baseName -IsDisabled $isDis
    Save-WebpOrPng -Bitmap $iconBmp -RelPath ("res\drawable-hdpi\" + $webpName)
    if ($nightSet.Count -eq 0 -or $nightSet.Contains($baseName)) {
        Save-WebpOrPng -Bitmap $iconBmp -RelPath ("res\drawable-night-hdpi\" + $webpName)
    }
    $iconBmp.Dispose()
}

# For top-bar All-Apps button icon, only override when LCARS frame/vector style is active
if ($cfg.allApps.showLcarsFrame -eq $true) {
    $appsBtn = New-Object System.Drawing.Bitmap(39, 36, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gApps = [System.Drawing.Graphics]::FromImage($appsBtn)
    $gApps.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gApps.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
    $dApps = New-StarfleetDeltaPath -Cx 19.5 -Cy 18 -Scale 0.40
    $bApps = New-Object System.Drawing.SolidBrush($cOrange)
    $gApps.FillPath($bApps, $dApps)
    $bApps.Dispose(); $dApps.Dispose(); $gApps.Dispose()
    Save-WebpOrPng -Bitmap $appsBtn -RelPath "res\drawable-hdpi\hom_ico_main_apps.png"
    Save-WebpOrPng -Bitmap $appsBtn -RelPath "res\drawable-night-hdpi\hom_ico_main_apps.png"
    $appsBtn.Dispose()
}

function Draw-3DBatterySlabOnGraphics {
    param(
        [System.Drawing.Graphics]$G,
        [double]$Pct,
        [bool]$IsAlertRed
    )
    $clampPct = [Math]::Max(0.0, [Math]::Min(1.0, $Pct))
    $flX = 172.0; $flY = 158.0
    $frX = 395.0; $frY = 133.0
    $nrX = 480.0; $nrY = 173.0
    $nlX = 250.0; $nlY = 202.0
    $spFarX  = [float]($flX + ($frX - $flX) * $clampPct)
    $spFarY  = [float]($flY + ($frY - $flY) * $clampPct)
    $spNearX = [float]($nlX + ($nrX - $nlX) * $clampPct)
    $spNearY = [float]($nlY + ($nrY - $nlY) * $clampPct)
    $slabH   = 10.0

    if ($clampPct -lt 0.999) {
        $bTopUn = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 216, 227, 234))
        $bSideUn = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 154, 168, 180))
        $ptsTopUn = @(
            (New-Object System.Drawing.PointF($spFarX, $spFarY)),
            (New-Object System.Drawing.PointF($frX, $frY)),
            (New-Object System.Drawing.PointF($nrX, $nrY)),
            (New-Object System.Drawing.PointF($spNearX, $spNearY))
        )
        $ptsSideUn = @(
            (New-Object System.Drawing.PointF($spNearX, $spNearY)),
            (New-Object System.Drawing.PointF($nrX, $nrY)),
            (New-Object System.Drawing.PointF($nrX, ($nrY + $slabH))),
            (New-Object System.Drawing.PointF($spNearX, ($spNearY + $slabH)))
        )
        $G.FillPolygon($bTopUn, $ptsTopUn)
        $G.FillPolygon($bSideUn, $ptsSideUn)
        $bTopUn.Dispose(); $bSideUn.Dispose()
    }

    if ($clampPct -gt 0.001) {
        $cTop  = if ($IsAlertRed) { [System.Drawing.Color]::FromArgb(255, 255, 82, 82) } else { [System.Drawing.Color]::FromArgb(255, 67, 243, 176) }
        $cSide = if ($IsAlertRed) { [System.Drawing.Color]::FromArgb(255, 198, 40, 40) } else { [System.Drawing.Color]::FromArgb(255, 30, 199, 136) }
        $cRear = if ($IsAlertRed) { [System.Drawing.Color]::FromArgb(255, 183, 28, 28) } else { [System.Drawing.Color]::FromArgb(255, 37, 184, 138) }
        $bTopC = New-Object System.Drawing.SolidBrush($cTop)
        $bSideC = New-Object System.Drawing.SolidBrush($cSide)
        $bRearC = New-Object System.Drawing.SolidBrush($cRear)

        $ptsTopC = @(
            (New-Object System.Drawing.PointF($flX, $flY)),
            (New-Object System.Drawing.PointF($spFarX, $spFarY)),
            (New-Object System.Drawing.PointF($spNearX, $spNearY)),
            (New-Object System.Drawing.PointF($nlX, $nlY))
        )
        $ptsRearC = @(
            (New-Object System.Drawing.PointF($flX, $flY)),
            (New-Object System.Drawing.PointF($nlX, $nlY)),
            (New-Object System.Drawing.PointF($nlX, ($nlY + $slabH))),
            (New-Object System.Drawing.PointF($flX, ($flY + $slabH)))
        )
        $ptsSideC = @(
            (New-Object System.Drawing.PointF($nlX, $nlY)),
            (New-Object System.Drawing.PointF($spNearX, $spNearY)),
            (New-Object System.Drawing.PointF($spNearX, ($spNearY + $slabH))),
            (New-Object System.Drawing.PointF($nlX, ($nlY + $slabH)))
        )
        $G.FillPolygon($bTopC, $ptsTopC)
        $G.FillPolygon($bRearC, $ptsRearC)
        $G.FillPolygon($bSideC, $ptsSideC)
        $bTopC.Dispose(); $bSideC.Dispose(); $bRearC.Dispose()
    }

    $pCell = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(72, 255, 255, 255), 1.0)
    for ($ci = 1; $ci -le 5; $ci++) {
        $u = $ci / 6.0
        $x1 = [float]($flX + ($frX - $flX) * $u)
        $y1 = [float]($flY + ($frY - $flY) * $u)
        $x2 = [float]($nlX + ($nrX - $nlX) * $u)
        $y2 = [float]($nlY + ($nrY - $nlY) * $u)
        $G.DrawLine($pCell, $x1, $y1, $x2, $y2)
    }
    $pCell.Dispose()
}

function Draw-ShuttleGalileoOnGraphics {
    param(
        [System.Drawing.Graphics]$G,
        [double]$Pct = 0.68,
        [bool]$IsAlertRed = $false,
        [string]$LayerMode = "all", # "all", "bg", or "cover"
        [float]$ScalePct = 100.0,
        [float]$OffsetX = 0.0,
        [float]$OffsetY = 0.0,
        [float]$BoxW = 635.0,
        [float]$BoxH = 318.0
    )
    $stOuter = $G.Save()
    $G.ScaleTransform(($BoxW / 635.0), ($BoxH / 318.0))
    $s = if ($ScalePct -gt 0) { $ScalePct / 100.0 } else { 1.0 }
    $G.TranslateTransform((317.5 + $OffsetX), (159.0 + $OffsetY))
    $G.ScaleTransform($s, $s)
    $G.TranslateTransform(-317.5, -159.0)

    if ($LayerMode -eq "all" -or $LayerMode -eq "bg") {
        # 1. Soft 3D Ground Shadow
        $stSh = $G.Save()
        $G.TranslateTransform(332.0, 198.0)
        $G.RotateTransform(-6.0)
        $bSh1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(95, 0, 0, 0))
        $bSh2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(65, 0, 0, 0))
        $G.FillEllipse($bSh1, -245, -42, 490, 84)
        $G.FillEllipse($bSh2, -185, -30, 370, 60)
        $bSh1.Dispose(); $bSh2.Dispose()
        $G.Restore($stSh)

        # 2. Far-Side (Port / Left) Pylon & Warp Nacelle
        $bPortPyl = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(115, 82, 102, 118))
        $pPortPyl = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(165, 186, 208, 224), 1.4)
        $ptsPortPyl = @(
            (New-Object System.Drawing.PointF(158, 124)),
            (New-Object System.Drawing.PointF(138, 92)),
            (New-Object System.Drawing.PointF(205, 84)),
            (New-Object System.Drawing.PointF(222, 116))
        )
        $G.FillPolygon($bPortPyl, $ptsPortPyl)
        $G.DrawPolygon($pPortPyl, $ptsPortPyl)
        $bPortPyl.Dispose(); $pPortPyl.Dispose()

        $stPN = $G.Save()
        $G.TranslateTransform(215.0, 80.0)
        $G.RotateTransform(-6.6)
        $bPN = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 100, 124, 142))
        $pPN = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(185, 198, 218, 232), 1.5)
        $ptsPN = @(
            (New-Object System.Drawing.PointF(-128, 12)),
            (New-Object System.Drawing.PointF(-116, -12)),
            (New-Object System.Drawing.PointF(112, -12)),
            (New-Object System.Drawing.PointF(112, 12))
        )
        $G.FillPolygon($bPN, $ptsPN)
        $G.DrawPolygon($pPN, $ptsPN)
        $pRing = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 180, 205, 222), 1.1)
        for ($rx = -90; $rx -le 85; $rx += 35) {
            $G.DrawLine($pRing, $rx, -12, ($rx + 3), 12)
        }
        $bBusP = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, 249, 115, 22))
        $pBusP = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 254, 215, 170), 1.4)
        $G.FillPie($bBusP, 100, -12, 24, 24, -90, 180)
        $G.DrawPie($pBusP, 100, -12, 24, 24, -90, 180)
        $bPN.Dispose(); $pPN.Dispose(); $pRing.Dispose(); $bBusP.Dispose(); $pBusP.Dispose()
        $G.Restore($stPN)

        # 3. Under-Chassis Landing Skids (Aft & Forward Ski Pads)
        foreach ($sk in @(@{X=232.0; Y=215.0; W=66.0}, @{X=472.0; Y=184.0; W=62.0})) {
            $stSk = $G.Save()
            $G.TranslateTransform([float]$sk.X, [float]$sk.Y)
            $G.RotateTransform(-6.6)
            $bStrut = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(185, 100, 116, 139))
            $bSki   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 51, 65, 85))
            $pSki   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(195, 203, 213, 225), 1.4)
            $hw = [float]$sk.W / 2.0
            $G.FillRectangle($bStrut, (-$hw * 0.55), -16, 8, 16)
            $G.FillRectangle($bStrut, ($hw * 0.32), -16, 8, 16)
            $G.FillRectangle($bSki, -$hw, -6, [float]$sk.W, 8)
            $G.DrawRectangle($pSki, -$hw, -6, [float]$sk.W, 8)
            $bStrut.Dispose(); $bSki.Dispose(); $pSki.Dispose()
            $G.Restore($stSk)
        }
    }

    if ($LayerMode -eq "all") {
        Draw-3DBatterySlabOnGraphics -G $G -Pct $Pct -IsAlertRed $IsAlertRed
    }

    if ($LayerMode -eq "all" -or $LayerMode -eq "cover") {
        # 5. Translucent 3D Class F Shuttlecraft Galileo Main Hull (Boxy Wedge Fuselage)
        $ptsHull = @(
            (New-Object System.Drawing.PointF(182, 216)),
            (New-Object System.Drawing.PointF(106, 178)),
            (New-Object System.Drawing.PointF(86, 124)),
            (New-Object System.Drawing.PointF(118, 56)),
            (New-Object System.Drawing.PointF(285, 38)),
            (New-Object System.Drawing.PointF(448, 36)),
            (New-Object System.Drawing.PointF(484, 46)),
            (New-Object System.Drawing.PointF(564, 102)),
            (New-Object System.Drawing.PointF(594, 128)),
            (New-Object System.Drawing.PointF(570, 164)),
            (New-Object System.Drawing.PointF(488, 184))
        )
        $bHull = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(110, 34)),
            (New-Object System.Drawing.PointF(560, 216)),
            [System.Drawing.Color]::FromArgb(92, 135, 160, 178),
            [System.Drawing.Color]::FromArgb(102, 105, 132, 150)
        )
        $pHull = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(215, 212, 228, 240), 1.9)
        $G.FillPolygon($bHull, $ptsHull)
        $G.DrawPolygon($pHull, $ptsHull)
        $bHull.Dispose(); $pHull.Dispose()

        # 6. Recessed Aft Impulse Engine Grille
        $ptsImp = @(
            (New-Object System.Drawing.PointF(98, 126)),
            (New-Object System.Drawing.PointF(154, 152)),
            (New-Object System.Drawing.PointF(164, 188)),
            (New-Object System.Drawing.PointF(108, 162))
        )
        $bImp = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(175, 20, 30, 44))
        $pImp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(185, 190, 212, 228), 1.3)
        $G.FillPolygon($bImp, $ptsImp)
        $G.DrawPolygon($pImp, $ptsImp)
        $pVent = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 56, 189, 248), 1.2)
        for ($iv = 1; $iv -le 4; $iv++) {
            $f = $iv / 5.0
            $G.DrawLine($pVent, [float](98 + $f * 10), [float](126 + $f * 36), [float](154 + $f * 10), [float](152 + $f * 36))
        }
        $bImp.Dispose(); $pImp.Dispose(); $pVent.Dispose()

        # 7. X-Ray Wireframe Roof Crease, Mid-Body Chine & Structural Bulkhead Ribs
        $pSeam = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140, 202, 220, 234), 1.3)
        $G.DrawLine($pSeam, 118, 56, 168, 76)
        $G.DrawLine($pSeam, 168, 76, 484, 46)
        $G.DrawLine($pSeam, 168, 76, 154, 152)
        $G.DrawLine($pSeam, 154, 152, 182, 216)
        $G.DrawLine($pSeam, 154, 152, 564, 102)
        $G.DrawLine($pSeam, 564, 102, 594, 128)

        foreach ($bx in @(230.0, 312.0, 392.0)) {
            $t = ($bx - 168.0) / (484.0 - 168.0)
            $topX = [float](118.0 + $t * (448.0 - 118.0))
            $topY = [float](48.0 - [Math]::Sin($t * [Math]::PI) * 10.0)
            $shX  = [float](168.0 + $t * (484.0 - 168.0))
            $shY  = [float](74.0 - $t * 26.0)
            $midX = [float](154.0 + $t * (470.0 - 154.0))
            $midY = [float](152.0 - $t * 38.0)
            $botX = [float](182.0 + $t * (488.0 - 182.0))
            $botY = [float](216.0 - $t * 32.0)
            $G.DrawLine($pSeam, $topX, $topY, $shX, $shY)
            $G.DrawLine($pSeam, $shX, $shY, $midX, $midY)
            $G.DrawLine($pSeam, $midX, $midY, $botX, $botY)
        }
        $pSeam.Dispose()

        # Starboard Side Access Hatch Door
        $ptsDoor = @(
            (New-Object System.Drawing.PointF(278, 76)),
            (New-Object System.Drawing.PointF(342, 69)),
            (New-Object System.Drawing.PointF(336, 178)),
            (New-Object System.Drawing.PointF(272, 186))
        )
        $bDoor = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(36, 148, 172, 190))
        $pDoor = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(175, 218, 232, 244), 1.4)
        $G.FillPolygon($bDoor, $ptsDoor)
        $G.DrawPolygon($pDoor, $ptsDoor)
        $bDoor.Dispose(); $pDoor.Dispose()

        # 8. Iconic Galileo Flat-Paned Cockpit Viewport Windows
        $bWin = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(145, 20, 34, 48))
        $pWin = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 224, 238, 248), 1.6)
        $win1 = @(
            (New-Object System.Drawing.PointF(454, 43)),
            (New-Object System.Drawing.PointF(482, 47)),
            (New-Object System.Drawing.PointF(552, 97)),
            (New-Object System.Drawing.PointF(516, 102))
        )
        $win2 = @(
            (New-Object System.Drawing.PointF(416, 52)),
            (New-Object System.Drawing.PointF(448, 44)),
            (New-Object System.Drawing.PointF(510, 103)),
            (New-Object System.Drawing.PointF(468, 110))
        )
        $win3 = @(
            (New-Object System.Drawing.PointF(376, 62)),
            (New-Object System.Drawing.PointF(410, 54)),
            (New-Object System.Drawing.PointF(460, 111)),
            (New-Object System.Drawing.PointF(392, 118))
        )
        $G.FillPolygon($bWin, $win1); $G.DrawPolygon($pWin, $win1)
        $G.FillPolygon($bWin, $win2); $G.DrawPolygon($pWin, $win2)
        $G.FillPolygon($bWin, $win3); $G.DrawPolygon($pWin, $win3)
        $bWin.Dispose(); $pWin.Dispose()

        # Forward Nose Sensor / Deflector Dish
        $bDef = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 34, 211, 238))
        $pDef = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(215, 226, 242, 252), 1.5)
        $bDefCore = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 251, 191, 36))
        $G.FillEllipse($bDef, 555, 118, 22, 32)
        $G.DrawEllipse($pDef, 555, 118, 22, 32)
        $G.FillEllipse($bDefCore, 563, 127, 8, 14)
        $bDef.Dispose(); $pDef.Dispose(); $bDefCore.Dispose()

        # Starfleet Hull Pennant Stripe
        $bPen = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(145, 251, 191, 36))
        $ptsPen = @(
            (New-Object System.Drawing.PointF(176, 146)),
            (New-Object System.Drawing.PointF(456, 114)),
            (New-Object System.Drawing.PointF(432, 122)),
            (New-Object System.Drawing.PointF(176, 152))
        )
        $G.FillPolygon($bPen, $ptsPen)
        $bPen.Dispose()

        # 9. Near-Side (Starboard / Right) Swept Pylon & Cylindrical Warp Nacelle (Foreground)
        $bStPyl = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 110, 134, 152))
        $pStPyl = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 212, 228, 240), 1.5)
        $ptsStPyl = @(
            (New-Object System.Drawing.PointF(212, 188)),
            (New-Object System.Drawing.PointF(298, 178)),
            (New-Object System.Drawing.PointF(282, 208)),
            (New-Object System.Drawing.PointF(196, 218))
        )
        $G.FillPolygon($bStPyl, $ptsStPyl)
        $G.DrawPolygon($pStPyl, $ptsStPyl)
        $bStPyl.Dispose(); $pStPyl.Dispose()

        $stSN = $G.Save()
        $G.TranslateTransform(292.0, 204.0)
        $G.RotateTransform(-6.6)
        $bEx = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(215, 71, 85, 105))
        $pEx = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(205, 203, 213, 225), 1.4)
        $G.FillEllipse($bEx, -156, -8, 20, 20)
        $G.DrawEllipse($pEx, -156, -8, 20, 20)

        $bSN = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(0, -15)),
            (New-Object System.Drawing.PointF(0, 15)),
            [System.Drawing.Color]::FromArgb(185, 185, 206, 224),
            [System.Drawing.Color]::FromArgb(205, 45, 60, 76)
        )
        $pSN = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 226, 238, 248), 1.8)
        $ptsSN = @(
            (New-Object System.Drawing.PointF(-150, 15)),
            (New-Object System.Drawing.PointF(-134, -15)),
            (New-Object System.Drawing.PointF(138, -15)),
            (New-Object System.Drawing.PointF(138, 15))
        )
        $G.FillPolygon($bSN, $ptsSN)
        $G.DrawPolygon($pSN, $ptsSN)

        $pSRing = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(135, 206, 224, 238), 1.2)
        for ($rx = -110; $rx -le 110; $rx += 32) {
            $G.DrawLine($pSRing, $rx, -15, ($rx + 4), 15)
        }

        $fReg = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
        $bReg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 226, 238, 248))
        $G.DrawString("NCC-1701/7", $fReg, $bReg, -34, -6)
        $fReg.Dispose(); $bReg.Dispose()

        $bBusS = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 249, 115, 22))
        $bBusCore = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 254, 240, 138))
        $pBusS = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235, 254, 226, 226), 1.6)
        $G.FillPie($bBusS, 125, -15, 30, 30, -90, 180)
        $G.FillPie($bBusCore, 131, -8, 16, 16, -90, 180)
        $G.DrawPie($pBusS, 125, -15, 30, 30, -90, 180)

        $bEx.Dispose(); $pEx.Dispose(); $bSN.Dispose(); $pSN.Dispose(); $pSRing.Dispose()
        $bBusS.Dispose(); $bBusCore.Dispose(); $pBusS.Dispose()
        $G.Restore($stSN)
    }

    $G.Restore($stOuter)
}

function Draw-WireframeEvCarOnGraphics {
    param(
        [System.Drawing.Graphics]$G,
        [double]$Pct = 0.68,
        [bool]$IsAlertRed = $false,
        [string]$LayerMode = "all", # "all", "bg", or "cover"
        [float]$ScalePct = 100.0,
        [float]$OffsetX = 0.0,
        [float]$OffsetY = 0.0,
        [float]$BoxW = 635.0,
        [float]$BoxH = 318.0
    )
    $stOuter = $G.Save()
    $G.ScaleTransform(($BoxW / 635.0), ($BoxH / 318.0))
    $s = if ($ScalePct -gt 0) { $ScalePct / 100.0 } else { 1.0 }
    $G.TranslateTransform((317.5 + $OffsetX), (159.0 + $OffsetY))
    $G.ScaleTransform($s, $s)
    $G.TranslateTransform(-317.5, -159.0)

    if ($LayerMode -eq "all" -or $LayerMode -eq "bg") {
        $stSh = $G.Save()
        $G.TranslateTransform(335.0, 194.0)
        $G.RotateTransform(-6.0)
        $bSh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(95, 0, 0, 0))
        $G.FillEllipse($bSh, -240, -40, 480, 80)
        $bSh.Dispose()
        $G.Restore($stSh)

        $bChassis = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, 22, 28, 36))
        $ptsCh = @(
            (New-Object System.Drawing.PointF(78, 165)),
            (New-Object System.Drawing.PointF(165, 145)),
            (New-Object System.Drawing.PointF(420, 122)),
            (New-Object System.Drawing.PointF(585, 162)),
            (New-Object System.Drawing.PointF(490, 192)),
            (New-Object System.Drawing.PointF(240, 226)),
            (New-Object System.Drawing.PointF(158, 222))
        )
        $G.FillPolygon($bChassis, $ptsCh)
        $bChassis.Dispose()
    }

    if ($LayerMode -eq "all") {
        Draw-3DBatterySlabOnGraphics -G $G -Pct $Pct -IsAlertRed $IsAlertRed
    }

    if ($LayerMode -eq "all" -or $LayerMode -eq "cover") {
        $ptsBody = @(
            (New-Object System.Drawing.PointF(160, 232)),
            (New-Object System.Drawing.PointF(85, 195)),
            (New-Object System.Drawing.PointF(66, 148)),
            (New-Object System.Drawing.PointF(76, 98)),
            (New-Object System.Drawing.PointF(112, 52)),
            (New-Object System.Drawing.PointF(220, 22)),
            (New-Object System.Drawing.PointF(308, 16)),
            (New-Object System.Drawing.PointF(385, 32)),
            (New-Object System.Drawing.PointF(515, 58)),
            (New-Object System.Drawing.PointF(568, 82)),
            (New-Object System.Drawing.PointF(596, 114)),
            (New-Object System.Drawing.PointF(594, 176)),
            (New-Object System.Drawing.PointF(564, 184)),
            (New-Object System.Drawing.PointF(486, 194)),
            (New-Object System.Drawing.PointF(250, 235))
        )
        $bBody = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(120, 20)),
            (New-Object System.Drawing.PointF(540, 220)),
            [System.Drawing.Color]::FromArgb(88, 120, 142, 158),
            [System.Drawing.Color]::FromArgb(96, 110, 135, 150)
        )
        $pBody = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 206, 222, 234), 1.8)
        $G.FillPolygon($bBody, $ptsBody)
        $G.DrawPolygon($pBody, $ptsBody)

        $ptsDlo = @(
            (New-Object System.Drawing.PointF(208, 144)),
            (New-Object System.Drawing.PointF(255, 80)),
            (New-Object System.Drawing.PointF(350, 64)),
            (New-Object System.Drawing.PointF(412, 72)),
            (New-Object System.Drawing.PointF(468, 109)),
            (New-Object System.Drawing.PointF(340, 128))
        )
        $bDlo = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(85, 30, 44, 58))
        $pSeam = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140, 200, 218, 230), 1.3)
        $G.FillPolygon($bDlo, $ptsDlo)
        $G.DrawPolygon($pSeam, $ptsDlo)
        $G.DrawLine($pSeam, 328, 66, 340, 128)
        $G.DrawLine($pSeam, 340, 128, 344, 210)
        $G.DrawLine($pSeam, 256, 80, 228, 141)

        foreach ($w in @(@{X=204.0; Y=218.0; RX=41.0; RY=49.0}, @{X=526.0; Y=171.0; RX=37.0; RY=45.0})) {
            $bTire = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(240, 38, 45, 54))
            $bRim  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 203, 213, 225))
            $pRim  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 100, 116, 139), 1.5)
            $G.FillEllipse($bTire, ([float]$w.X - [float]$w.RX), ([float]$w.Y - [float]$w.RY), ([float]$w.RX * 2), ([float]$w.RY * 2))
            $G.DrawEllipse($pRim, ([float]$w.X - [float]$w.RX), ([float]$w.Y - [float]$w.RY), ([float]$w.RX * 2), ([float]$w.RY * 2))
            $rrx = [float]$w.RX * 0.70; $rry = [float]$w.RY * 0.70
            $G.FillEllipse($bRim, ([float]$w.X - $rrx + 2), ([float]$w.Y - $rry + 1), ($rrx * 2), ($rry * 2))
            $G.DrawEllipse($pRim, ([float]$w.X - $rrx + 2), ([float]$w.Y - $rry + 1), ($rrx * 2), ($rry * 2))
            $bTire.Dispose(); $bRim.Dispose(); $pRim.Dispose()
        }
        $bBody.Dispose(); $pBody.Dispose(); $bDlo.Dispose(); $pSeam.Dispose()
    }

    $G.Restore($stOuter)
}

function Draw-BatteryGraphic {
    param([int]$Level, [int]$MaxLevel, [string]$Variant)
    $bw = $cfg.batteryWidget
    $scalePct = if ($null -ne $bw.customScale -and [float]$bw.customScale -gt 0) { [float]$bw.customScale } else { 100.0 }
    $offX = if ($null -ne $bw.customOffsetX) { [float]$bw.customOffsetX } else { 0.0 }
    $offY = if ($null -ne $bw.customOffsetY) { [float]$bw.customOffsetY } else { 0.0 }
    $rangeOffX = if ($null -ne $bw.rangeOffsetX) { [float]$bw.rangeOffsetX } else { 0.0 }
    $rangeOffY = if ($null -ne $bw.rangeOffsetY) { [float]$bw.rangeOffsetY } else { 0.0 }
    $hideRangeBox = ($bw.hideRangeBox -eq $true)

    $bmp = New-Object System.Drawing.Bitmap(798, 318, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

    $pct = [Math]::Max(0.0, [Math]::Min(1.0, ([double]$Level / [double]$MaxLevel)))
    $pctInt = [int][Math]::Round($pct * 100)
    $coreCol = if ($Variant -eq "r" -or $pct -le 0.20) {
        [System.Drawing.Color]::FromArgb(255, 255, 68, 51)
    } else {
        $cCyan
    }

    if ($bw.style -eq "oem") {
        # Vehicle's built-in 3D EV car graphic is composited underneath this overlay at runtime on the headunit
    } elseif ($bw.style -eq "galileo") {
        Draw-ShuttleGalileoOnGraphics -G $g -Pct $pct -IsAlertRed ($Variant -eq "r" -or $pct -le 0.20) -LayerMode "all" `
            -ScalePct $scalePct -OffsetX $offX -OffsetY $offY -BoxW 635.0 -BoxH 318.0
    } elseif ($bw.style -eq "wireframeCar") {
        Draw-WireframeEvCarOnGraphics -G $g -Pct $pct -IsAlertRed ($Variant -eq "r" -or $pct -le 0.20) -LayerMode "all" `
            -ScalePct $scalePct -OffsetX $offX -OffsetY $offY -BoxW 635.0 -BoxH 318.0
    } elseif ($bw.style -eq "custom" -and $bw.customFile) {
        $customFull = Join-Path $CustomAssetsDir ([string]$bw.customFile)
        Draw-FittedImageInBox -G $g -ImgPath $customFull -BoxX 0.0 -BoxY 0.0 -TargetW 620.0 -TargetH 280.0 `
            -Fit "contain" -ScalePct $scalePct -OffsetX $offX -OffsetY $offY | Out-Null
    } elseif ($bw.style -ne "custom") {
        $pShip = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 153, 204, 255), 2.0)
        $bShipFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 40, 80, 140))

        $nx = [float]$bw.nacelleX
        $nTopY = [float]$bw.nacelleTopY
        $nBotY = [float]$bw.nacelleBotY
        $nw = [float]$bw.nacelleW
        $nh = [float]$bw.nacelleH

        $nacelleTop = New-RoundedRectPath -X $nx -Y $nTopY -W $nw -H $nh -R 9
        $nacelleBot = New-RoundedRectPath -X $nx -Y $nBotY -W $nw -H $nh -R 9
        $g.FillPath($bShipFill, $nacelleTop); $g.DrawPath($pShip, $nacelleTop)
        $g.FillPath($bShipFill, $nacelleBot); $g.DrawPath($pShip, $nacelleBot)
        $nacelleTop.Dispose(); $nacelleBot.Dispose()

        $sx = [float]$bw.saucerX
        $sy = [float]$bw.saucerY
        $sw = [float]$bw.saucerW
        $sh = [float]$bw.saucerH
        $g.FillEllipse($bShipFill, $sx, $sy, $sw, $sh)
        $g.DrawEllipse($pShip, $sx, $sy, $sw, $sh)
        $g.DrawEllipse($pShip, ($sx + $sw * 0.34), ($sy + $sh * 0.34), ($sw * 0.32), ($sh * 0.32))

        $bActive = New-Object System.Drawing.SolidBrush($coreCol)
        $bDim    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 153, 204, 255))
        $activeSegs = [int][Math]::Round($pct * 16)
        for ($s = 0; $s -lt 16; $s++) {
            $br = if ($s -lt $activeSegs) { $bActive } else { $bDim }
            $segX = $nx + 10 + ($s * (($nw - 34) / 16.0))
            $g.FillRectangle($br, $segX, ($nTopY + 4), 6.0, ($nh - 8))
            $g.FillRectangle($br, $segX, ($nBotY + 4), 6.0, ($nh - 8))
        }
        $bActive.Dispose(); $bDim.Dispose()

        $bBussard = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 255, 68, 34))
        $g.FillEllipse($bBussard, ($nx + $nw - 18), ($nTopY + 1), 16, ($nh - 2))
        $g.FillEllipse($bBussard, ($nx + $nw - 18), ($nBotY + 1), 16, ($nh - 2))
        $bBussard.Dispose()
        $pShip.Dispose(); $bShipFill.Dispose()
    }

    if ($bw.showDynamicBar -eq $true) {
        $hx = [float]$bw.hullX
        $hy = [float]$bw.hullY
        $hw = [float]$bw.hullW
        $hh = [float]$bw.hullH
        $pBar = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 153, 204, 255), 2.0)
        $bBarFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 15, 25, 45))
        $hullPath = New-RoundedRectPath -X $hx -Y $hy -W $hw -H $hh -R 8
        $g.FillPath($bBarFill, $hullPath)
        $g.DrawPath($pBar, $hullPath)
        $hullPath.Dispose(); $pBar.Dispose(); $bBarFill.Dispose()

        $bActive = New-Object System.Drawing.SolidBrush($coreCol)
        $bDim    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 153, 204, 255))
        $activeSegs = [int][Math]::Round($pct * 16)
        for ($s = 0; $s -lt 16; $s++) {
            $br = if ($s -lt $activeSegs) { $bActive } else { $bDim }
            $barX = $hx + 10 + ($s * (($hw - 20) / 16.0))
            $g.FillRectangle($br, $barX, ($hy + 4), 14.0, ($hh - 8))
        }
        $bActive.Dispose(); $bDim.Dispose()

        if ($bw.labelPrefix) {
            $fontTiny = New-Object System.Drawing.Font("Arial", 8.0, [System.Drawing.FontStyle]::Bold)
            $bGold = New-Object System.Drawing.SolidBrush($cPeach)
            $g.DrawString(("$($bw.labelPrefix) $pctInt%"), $fontTiny, $bGold, $hx, ($hy + $hh + 4))
            $fontTiny.Dispose(); $bGold.Dispose()
        }
    }

    $bTxtOffX = if ($null -ne $bw.battTextOffsetX) { [float]$bw.battTextOffsetX } else { 0.0 }
    $bTxtOffY = if ($null -ne $bw.battTextOffsetY) { [float]$bw.battTextOffsetY } else { 0.0 }

    if ($bw.showCalloutBox -eq $true) {
        $cx = [float]$bw.calloutX + $bTxtOffX
        $cy = [float]$bw.calloutY + $bTxtOffY
        $cw = [float]$bw.calloutW
        $ch = [float]$bw.calloutH
        $cr = [float]$bw.calloutRadius
        $pFrame = New-Object System.Drawing.Pen($cOrange, 2.2)
        $bFrameFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 8, 12, 26))
        $calloutRect = New-RoundedRectPath -X $cx -Y $cy -W $cw -H $ch -R $cr
        $g.FillPath($bFrameFill, $calloutRect)
        $g.DrawPath($pFrame, $calloutRect)
        $calloutRect.Dispose(); $bFrameFill.Dispose(); $pFrame.Dispose()
    }

    if (-not $hideRangeBox) {
        $rx = 578.0 + $rangeOffX
        $ry = 203.0 + $rangeOffY
        $rw = 198.0
        $rh = 87.0
        $pRange = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(215, 168, 176, 186), 1.6)
        $bRange = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(228, 56, 61, 68))
        $rangePath = New-RoundedRectPath -X $rx -Y $ry -W $rw -H $rh -R 12.0
        $g.FillPath($bRange, $rangePath)
        $g.DrawPath($pRange, $rangePath)
        $rangePath.Dispose(); $bRange.Dispose(); $pRange.Dispose()
    }

    $g.Dispose()
    return $bmp
}

Write-Host "[6/6] Generating EV Battery Levels (00..20)..."
$bw = $cfg.batteryWidget
$bwScalePct = if ($null -ne $bw.customScale -and [float]$bw.customScale -gt 0) { [float]$bw.customScale } else { 100.0 }
$bwOffX = if ($null -ne $bw.customOffsetX) { [float]$bw.customOffsetX } else { 0.0 }
$bwOffY = if ($null -ne $bw.customOffsetY) { [float]$bw.customOffsetY } else { 0.0 }
$bwRangeOffX = if ($null -ne $bw.rangeOffsetX) { [float]$bw.rangeOffsetX } else { 0.0 }
$bwRangeOffY = if ($null -ne $bw.rangeOffsetY) { [float]$bw.rangeOffsetY } else { 0.0 }
$bwUnmodifiedOem = ($bw.style -eq "oem" -and $bwScalePct -eq 100.0 -and $bwOffX -eq 0.0 -and $bwOffY -eq 0.0 -and $bwRangeOffX -eq 0.0 -and $bwRangeOffY -eq 0.0 -and ($bw.hideRangeBox -ne $true) -and ($bw.showCalloutBox -ne $true) -and ($bw.showDynamicBar -ne $true))

if (-not $bwUnmodifiedOem) {
    for ($i = 0; $i -le 20; $i++) {
        $num = $i.ToString("00")
        $bNorm = Draw-BatteryGraphic -Level $i -MaxLevel 20 -Variant "n"
        Save-WebpOrPng -Bitmap $bNorm -RelPath "res\drawable-hdpi\home_etc_battery_$num.webp"
        Save-WebpOrPng -Bitmap $bNorm -RelPath "res\drawable-night-hdpi\home_etc_battery_$num.webp"
        $bNorm.Dispose()
        if ($i -le 19) {
            $bYel = Draw-BatteryGraphic -Level $i -MaxLevel 20 -Variant "y"
            Save-WebpOrPng -Bitmap $bYel -RelPath "res\drawable-hdpi\home_etc_battery_y_$num.webp"
            Save-WebpOrPng -Bitmap $bYel -RelPath "res\drawable-night-hdpi\home_etc_battery_y_$num.webp"
            $bYel.Dispose()
        }
    }
    for ($i = 1; $i -le 13; $i++) {
        $num = $i.ToString("00")
        $bRed = Draw-BatteryGraphic -Level $i -MaxLevel 20 -Variant "r"
        Save-WebpOrPng -Bitmap $bRed -RelPath "res\drawable-hdpi\home_etc_battery_r_$num.webp"
        Save-WebpOrPng -Bitmap $bRed -RelPath "res\drawable-night-hdpi\home_etc_battery_r_$num.webp"
        $bRed.Dispose()
    }
}

$tileNor.Dispose(); $bgDay.Dispose()
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ==============================================================================
# [7/7] Generate Optional Sub-APK Overlays: Status Bar, Climate/Warmer, EV Screen
# ==============================================================================
Write-Host "[7/7] Generating Optional Sub-APK Overlays (Status Bar, Climate/Warmer, EV Screen)..."

# --- A. Top Status Bar (SystemUI.apk) ---
$sbCfg = $cfg.statusBar
if ($null -ne $sbCfg) {
    $sbBgMode = if ($sbCfg.bgMode) { [string]$sbCfg.bgMode } else { "oem" }
    $sbBtnStyle = if ($sbCfg.buttonStyle) { [string]$sbCfg.buttonStyle } else { "oem" }
    $sysuiManifest = New-Object 'System.Collections.Generic.List[string]'

    if ($sbBgMode -ne "oem") {
        $bmpSb = New-Object System.Drawing.Bitmap(1920, 90, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gSb = [System.Drawing.Graphics]::FromImage($bmpSb)
        $gSb.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $sbBgHex = if ($sbCfg.bgColor) { [string]$sbCfg.bgColor } else { "#060810" }
        $sbAccHex = if ($sbCfg.accentColor) { [string]$sbCfg.accentColor } else { [string]$cfg.colors.primary }
        $sbSecHex = if ($sbCfg.secondaryColor) { [string]$sbCfg.secondaryColor } else { [string]$cfg.colors.accentBlue }
        $sbBorderH = if ($null -ne $sbCfg.borderHeight) { [int]$sbCfg.borderHeight } else { 4 }

        $bBg = New-Object System.Drawing.SolidBrush((Parse-HexColor $sbBgHex 255))
        $gSb.FillRectangle($bBg, 0, 0, 1920, 90)
        $bBg.Dispose()

        if ($sbBgMode -eq "custom" -and $sbCfg.customBgFile) {
            $cFile = Join-Path $CustomAssetsDir ([string]$sbCfg.customBgFile)
            $cFit = if ($sbCfg.bgFit) { [string]$sbCfg.bgFit } else { "cover" }
            $cScale = if ($null -ne $sbCfg.bgScale) { [float]$sbCfg.bgScale } else { 100.0 }
            $cOffX = if ($null -ne $sbCfg.bgOffsetX) { [float]$sbCfg.bgOffsetX } else { 0.0 }
            $cOffY = if ($null -ne $sbCfg.bgOffsetY) { [float]$sbCfg.bgOffsetY } else { 0.0 }
            Draw-FittedImage -G $gSb -ImgPath $cFile -TargetW 1920 -TargetH 90 -Fit $cFit -ScalePct $cScale -OffsetX $cOffX -OffsetY $cOffY | Out-Null
        }

        if ($sbBgMode -eq "lcars") {
            $bAcc = New-Object System.Drawing.SolidBrush((Parse-HexColor $sbAccHex 255))
            $bSec = New-Object System.Drawing.SolidBrush((Parse-HexColor $sbSecHex 255))
            $bTer = New-Object System.Drawing.SolidBrush($cMagenta)
            $bh = [Math]::Max(2, [Math]::Min(16, $sbBorderH))
            $by = 90 - $bh
            $gSb.FillRectangle($bAcc, 0, $by, 390, $bh)
            $gSb.FillRectangle($bSec, 398, $by, 260, $bh)
            $gSb.FillRectangle($bTer, 666, $by, 180, $bh)
            $gSb.FillRectangle($bAcc, 854, $by, 620, $bh)
            $gSb.FillRectangle($bSec, 1482, $by, 438, $bh)
            $bAcc.Dispose(); $bSec.Dispose(); $bTer.Dispose()
        } elseif ($sbBorderH -gt 0) {
            $bAcc = New-Object System.Drawing.SolidBrush((Parse-HexColor $sbAccHex 255))
            $gSb.FillRectangle($bAcc, 0, (90 - $sbBorderH), 1920, $sbBorderH)
            $bAcc.Dispose()
        }
        $gSb.Dispose()
        Save-WebpOrPng -Bitmap $bmpSb -RelPath "systemui\status_bg.png"
        $bmpSb.Dispose()

        $sysuiManifest.Add("res/drawable-eco-hdpi/co_bg_status.9.png|status_bg.png")
        $sysuiManifest.Add("res/drawable-eco-night-hdpi/co_bg_status.9.png|status_bg.png")
        $sysuiManifest.Add("res/drawable-hdpi/co_bg_status.png|status_bg.png")
        $sysuiManifest.Add("res/drawable-mdpi/co_bg_status.png|status_bg.png")
    }

    if ($sbBtnStyle -ne "oem") {
        $btnBgHex = if ($sbCfg.buttonBgColor) { [string]$sbCfg.buttonBgColor } else { "#141C2B" }
        $btnAccHex = if ($sbCfg.buttonAccentColor) { [string]$sbCfg.buttonAccentColor } else { [string]$cfg.colors.primary }
        $btnGlyphHex = if ($sbCfg.buttonGlyphColor) { [string]$sbCfg.buttonGlyphColor } else { "#FFCC66" }

        function Draw-StatusBarButton([int]$W, [int]$H, [string]$Kind, [bool]$IsPush) {
            $b = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($b)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

            if ($sbBtnStyle -eq "custom") {
                $cf = if ($Kind -eq "home") { [string]$sbCfg.customHomeFile } elseif ($Kind -eq "back") { [string]$sbCfg.customBackFile } else { "" }
                if ($cf) {
                    $cPath = Join-Path $CustomAssetsDir $cf
                    if (Test-Path $cPath) {
                        Draw-FittedImage -G $g -ImgPath $cPath -TargetW $W -TargetH $H -Fit "contain" -ScalePct 100.0 | Out-Null
                        $g.Dispose()
                        return $b
                    }
                }
            }

            $pill = New-RoundedRectPath -X 8 -Y 10 -W ($W - 16) -H ($H - 20) -R 24
            $fillCol = if ($IsPush) { Parse-HexColor $btnAccHex 230 } else { Parse-HexColor $btnBgHex 225 }
            $bordCol = Parse-HexColor $btnAccHex 255
            $glyphCol = if ($IsPush) { [System.Drawing.Color]::FromArgb(255, 10, 12, 18) } else { Parse-HexColor $btnGlyphHex 255 }

            $bFill = New-Object System.Drawing.SolidBrush($fillCol)
            $pBord = New-Object System.Drawing.Pen($bordCol, 2.5)
            $g.FillPath($bFill, $pill)
            $g.DrawPath($pBord, $pill)

            $pGlyph = New-Object System.Drawing.Pen($glyphCol, 3.2)
            $pGlyph.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pGlyph.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pGlyph.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
            $cx = $W / 2.0; $cy = $H / 2.0

            if ($Kind -eq "home") {
                $pts = @(
                    (New-Object System.Drawing.PointF(($cx - 16), ($cy + 2))),
                    (New-Object System.Drawing.PointF($cx, ($cy - 13))),
                    (New-Object System.Drawing.PointF(($cx + 16), ($cy + 2)))
                )
                $g.DrawLines($pGlyph, $pts)
                $g.DrawRectangle($pGlyph, ($cx - 11), ($cy + 1), 22, 13)
            } elseif ($Kind -eq "back") {
                $pts = @(
                    (New-Object System.Drawing.PointF(($cx - 4), ($cy - 11))),
                    (New-Object System.Drawing.PointF(($cx - 15), $cy)),
                    (New-Object System.Drawing.PointF(($cx - 4), ($cy + 11)))
                )
                $g.DrawLines($pGlyph, $pts)
                $g.DrawLine($pGlyph, ($cx - 14), $cy, ($cx + 14), $cy)
            } else {
                $g.DrawLine($pGlyph, ($cx - 18), ($cy - 8), ($cx + 18), ($cy - 8))
                $g.DrawLine($pGlyph, ($cx - 18), $cy, ($cx + 18), $cy)
                $g.DrawLine($pGlyph, ($cx - 18), ($cy + 8), ($cx + 18), ($cy + 8))
            }

            $pGlyph.Dispose(); $bFill.Dispose(); $pBord.Dispose(); $pill.Dispose(); $g.Dispose()
            return $b
        }

        $bHomeNor = Draw-StatusBarButton 180 84 "home" $false
        $bHomePush = Draw-StatusBarButton 180 84 "home" $true
        $bBackNor = Draw-StatusBarButton 180 84 "back" $false
        $bBackPush = Draw-StatusBarButton 180 84 "back" $true
        $bMenuNor = Draw-StatusBarButton 270 84 "menu" $false
        $bMenuPush = Draw-StatusBarButton 270 84 "menu" $true

        Save-WebpOrPng -Bitmap $bHomeNor -RelPath "systemui\btn_home_nor.png"
        Save-WebpOrPng -Bitmap $bHomePush -RelPath "systemui\btn_home_push.png"
        Save-WebpOrPng -Bitmap $bBackNor -RelPath "systemui\btn_back_nor.png"
        Save-WebpOrPng -Bitmap $bBackPush -RelPath "systemui\btn_back_push.png"
        Save-WebpOrPng -Bitmap $bMenuNor -RelPath "systemui\btn_menu_nor.png"
        Save-WebpOrPng -Bitmap $bMenuPush -RelPath "systemui\btn_menu_push.png"
        $bHomeNor.Dispose(); $bHomePush.Dispose(); $bBackNor.Dispose(); $bBackPush.Dispose(); $bMenuNor.Dispose(); $bMenuPush.Dispose()

        foreach ($folder in @("drawable-long-eco-hdpi", "drawable-long-eco-night-hdpi", "drawable-hyundai-hdpi", "drawable-kia-hdpi")) {
            $sysuiManifest.Add("res/$folder/co_btn_home_1920_nor.png|btn_home_nor.png")
            $sysuiManifest.Add("res/$folder/co_btn_home_1920_push.png|btn_home_push.png")
            $sysuiManifest.Add("res/$folder/co_btn_home_1920_focus.png|btn_home_push.png")
            $sysuiManifest.Add("res/$folder/co_btn_back_1920_nor.png|btn_back_nor.png")
            $sysuiManifest.Add("res/$folder/co_btn_back_1920_push.png|btn_back_push.png")
            $sysuiManifest.Add("res/$folder/co_btn_back_1920_focus.png|btn_back_push.png")
        }
        foreach ($folder in @("drawable-long-eco-hdpi", "drawable-long-eco-night-hdpi")) {
            $sysuiManifest.Add("res/$folder/co_btn_bg_menu_nor_new.png|btn_menu_nor.png")
            $sysuiManifest.Add("res/$folder/co_btn_bg_menu_push_new.png|btn_menu_push.png")
            $sysuiManifest.Add("res/$folder/co_btn_bg_menu_focus_new.png|btn_menu_push.png")
        }
        foreach ($folder in @("drawable-hyundai-hdpi", "drawable-kia-hdpi")) {
            $sysuiManifest.Add("res/$folder/co_btn_bg_menu_nor.9.png|btn_menu_nor.png")
            $sysuiManifest.Add("res/$folder/co_btn_bg_menu_push.9.png|btn_menu_push.png")
            $sysuiManifest.Add("res/$folder/co_btn_bg_menu_focus.9.png|btn_menu_push.png")
        }
    }

    if ($sysuiManifest.Count -gt 0) {
        $sysuiDir = Join-Path $themeOutDir "systemui"
        New-Item -ItemType Directory -Force -Path $sysuiDir | Out-Null
        [System.IO.File]::WriteAllLines((Join-Path $sysuiDir "manifest.txt"), $sysuiManifest, $utf8NoBom)
    }
}

# --- B. Climate & Seat Warmer Screen (HKMC_Climate.apk) ---
$clmCfg = $cfg.climateScreen
if ($null -ne $clmCfg) {
    $clmBgMode = if ($clmCfg.bgMode) { [string]$clmCfg.bgMode } else { "oem" }
    $clmBarMode = if ($clmCfg.bottomBarMode) { [string]$clmCfg.bottomBarMode } else { "oem" }
    $clmSeatStyle = if ($clmCfg.seatStyle) { [string]$clmCfg.seatStyle } else { "oem" }
    $clmManifest = New-Object 'System.Collections.Generic.List[string]'
    $clmRuntimeLines = New-Object 'System.Collections.Generic.List[string]'

    $clmBgHex = if ($clmCfg.bgColor) { [string]$clmCfg.bgColor } else { "#070A12" }
    $clmAccHex = if ($clmCfg.accentColor) { [string]$clmCfg.accentColor } else { [string]$cfg.colors.primary }
    $clmSecHex = if ($clmCfg.secondaryColor) { [string]$clmCfg.secondaryColor } else { [string]$cfg.colors.accentBlue }

    if ($clmBgMode -ne "oem") {
        $bmpFull = New-Object System.Drawing.Bitmap(1920, 720, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gFull = [System.Drawing.Graphics]::FromImage($bmpFull)
        $gFull.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $bBg = New-Object System.Drawing.SolidBrush((Parse-HexColor $clmBgHex 255))
        $gFull.FillRectangle($bBg, 0, 0, 1920, 720)
        $bBg.Dispose()

        if ($clmBgMode -eq "custom" -and $clmCfg.customBgFile) {
            $cFile = Join-Path $CustomAssetsDir ([string]$clmCfg.customBgFile)
            $cFit = if ($clmCfg.bgFit) { [string]$clmCfg.bgFit } else { "cover" }
            $cScale = if ($null -ne $clmCfg.bgScale) { [float]$clmCfg.bgScale } else { 100.0 }
            $cOffX = if ($null -ne $clmCfg.bgOffsetX) { [float]$clmCfg.bgOffsetX } else { 0.0 }
            $cOffY = if ($null -ne $clmCfg.bgOffsetY) { [float]$clmCfg.bgOffsetY } else { 0.0 }
            $drew = Draw-FittedImage -G $gFull -ImgPath $cFile -TargetW 1920 -TargetH 720 -Fit $cFit -ScalePct $cScale -OffsetX $cOffX -OffsetY $cOffY
            if ($drew -and ([int]$clmCfg.bgDim) -gt 0) {
                $dAlpha = [int][Math]::Round(([float]$clmCfg.bgDim / 100.0) * 255)
                $bDim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($dAlpha, 0, 0, 0))
                $gFull.FillRectangle($bDim, 0, 0, 1920, 720)
                $bDim.Dispose()
            }
        }

        if ($clmBgMode -eq "lcars" -or $clmCfg.showLcarsFrame -eq $true) {
            $pGrid = New-Object System.Drawing.Pen((Parse-HexColor $clmSecHex 28), 1)
            for ($x = 80; $x -lt 1880; $x += 90) { $gFull.DrawLine($pGrid, $x, 100, $x, 595) }
            for ($y = 120; $y -lt 595; $y += 80) { $gFull.DrawLine($pGrid, 35, $y, 1885, $y) }
            $pGrid.Dispose()

            $bAcc = New-Object System.Drawing.SolidBrush((Parse-HexColor $clmAccHex 255))
            $bSec = New-Object System.Drawing.SolidBrush((Parse-HexColor $clmSecHex 255))
            $bPeach = New-Object System.Drawing.SolidBrush($cPeach)
            $gFull.FillRectangle($bAcc, 10, 96, 16, 200)
            $gFull.FillRectangle($bSec, 10, 304, 16, 160)
            $gFull.FillRectangle($bPeach, 10, 472, 16, 115)
            $gFull.FillRectangle($bAcc, 34, 92, 520, 8)
            $gFull.FillRectangle($bSec, 564, 92, 790, 8)
            $gFull.FillRectangle($bPeach, 1364, 92, 536, 8)
            $bAcc.Dispose(); $bSec.Dispose(); $bPeach.Dispose()
        }

        $gFull.Dispose()
        Save-WebpOrPng -Bitmap $bmpFull -RelPath "climate\co_bg_full.png"

        $bmpClm = New-Object System.Drawing.Bitmap(1280, 630, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gClm = [System.Drawing.Graphics]::FromImage($bmpClm)
        $gClm.DrawImage($bmpFull, (New-Object System.Drawing.Rectangle(0, 0, 1280, 630)), 0, 90, 1280, 630, [System.Drawing.GraphicsUnit]::Pixel)
        $gClm.Dispose()
        Save-WebpOrPng -Bitmap $bmpClm -RelPath "climate\clm_bg_main.webp"
        Save-WebpOrPng -Bitmap $bmpClm -RelPath "climate\clm_bg_main.png"
        $bmpClm.Dispose(); $bmpFull.Dispose()

        $clmManifest.Add("res/drawable-hdpi/clm_bg_type_a.webp|clm_bg_main.webp")
        $clmManifest.Add("res/drawable-night-hdpi/clm_bg_type_a.png|clm_bg_main.png")
        $clmManifest.Add("res/drawable-hdpi/clm_bg_driveronly.webp|clm_bg_main.webp")
        $clmManifest.Add("res/drawable-night-hdpi/clm_bg_driveronly.webp|clm_bg_main.webp")
        $clmManifest.Add("res/drawable-hdpi/co_bg_full.png|co_bg_full.png")
        $clmManifest.Add("res/drawable-night-hdpi/co_bg_full.png|co_bg_full.png")
    }

    if ($clmBarMode -ne "oem") {
        $bmpBot = New-Object System.Drawing.Bitmap(1920, 96, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gBot = [System.Drawing.Graphics]::FromImage($bmpBot)
        $bBotBg = New-Object System.Drawing.SolidBrush((Parse-HexColor $clmBgHex 245))
        $bBotAcc = New-Object System.Drawing.SolidBrush((Parse-HexColor $clmAccHex 255))
        $gBot.FillRectangle($bBotBg, 0, 0, 1920, 96)
        $gBot.FillRectangle($bBotAcc, 0, 0, 1920, 3)
        $bBotBg.Dispose(); $bBotAcc.Dispose(); $gBot.Dispose()
        Save-WebpOrPng -Bitmap $bmpBot -RelPath "climate\clm_bg_bottom.png"
        $bmpBot.Dispose()

        # Top-Center Pill Fan Speed Housing (480x120)
        $bmpFan = New-Object System.Drawing.Bitmap(480, 120, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gFan = [System.Drawing.Graphics]::FromImage($bmpFan)
        $gFan.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gFan.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $pFanPath = New-RoundedRectPath -X 4 -Y 4 -W 472 -H 112 -R 56
        $bFanFill = New-Object System.Drawing.SolidBrush((Parse-HexColor "#121A2A" 230))
        $pFanBord = New-Object System.Drawing.Pen((Parse-HexColor $clmSecHex 235), 2.5)
        $gFan.FillPath($bFanFill, $pFanPath); $gFan.DrawPath($pFanBord, $pFanPath)
        $bFanFill.Dispose(); $pFanBord.Dispose(); $pFanPath.Dispose(); $gFan.Dispose()
        Save-WebpOrPng -Bitmap $bmpFan -RelPath "climate\clm_bg_fan.png"
        $bmpFan.Dispose()

        # Circular buttons (105x102 temp up/down & 129x129 steering wheel / seat warmer shortcut)
        function Draw-ClmCircleBtn([int]$W, [int]$H, [bool]$IsPush) {
            $b = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($b)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $fCol = if ($IsPush) { Parse-HexColor $clmAccHex 210 } else { Parse-HexColor "#141D2E" 230 }
            $bCol = if ($IsPush) { Parse-HexColor "#FFFFFF" 255 } else { Parse-HexColor $clmAccHex 230 }
            $bf = New-Object System.Drawing.SolidBrush($fCol)
            $pb = New-Object System.Drawing.Pen($bCol, 2.4)
            $g.FillEllipse($bf, 6, 6, ($W - 12), ($H - 12))
            $g.DrawEllipse($pb, 6, 6, ($W - 12), ($H - 12))
            $bf.Dispose(); $pb.Dispose(); $g.Dispose()
            return $b
        }

        # Rectangular buttons (Bottom row AUTO/OFF/DRIVER ONLY/AC/HEAT/SYNC, Seat Warmer/Ventilation buttons, Popup OK button)
        function Draw-ClmRectBtn([int]$W, [int]$H, [string]$State) {
            $b = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($b)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $p = New-RoundedRectPath -X 3 -Y 3 -W ($W - 6) -H ($H - 6) -R 14
            $fCol = if ($State -eq "push") { Parse-HexColor $clmAccHex 195 } elseif ($State -eq "sel") { Parse-HexColor $clmSecHex 120 } else { Parse-HexColor "#141D2E" 230 }
            $bCol = if ($State -eq "push") { Parse-HexColor "#FFFFFF" 255 } elseif ($State -eq "sel") { Parse-HexColor $clmAccHex 255 } else { Parse-HexColor $clmSecHex 215 }
            $bf = New-Object System.Drawing.SolidBrush($fCol)
            $pb = New-Object System.Drawing.Pen($bCol, 2.2)
            $g.FillPath($bf, $p)
            if ($clmBarMode -eq "lcars") {
                $g.SetClip($p)
                $bSp = New-Object System.Drawing.SolidBrush((Parse-HexColor $clmAccHex 245))
                $g.FillRectangle($bSp, 3, 3, 10, ($H - 6))
                $bSp.Dispose()
                $g.ResetClip()
            }
            $g.DrawPath($pb, $p)
            $bf.Dispose(); $pb.Dispose(); $p.Dispose(); $g.Dispose()
            return $b
        }

        $bN1 = Draw-ClmCircleBtn 105 102 $false; $bP1 = Draw-ClmCircleBtn 105 102 $true
        $bN2 = Draw-ClmCircleBtn 129 129 $false; $bP2 = Draw-ClmCircleBtn 129 129 $true
        $bDialNor = Draw-ClmCircleBtn 294 294 $false; $bDialPush = Draw-ClmCircleBtn 294 294 $true
        Save-WebpOrPng -Bitmap $bN1 -RelPath "climate\clm_btn_nor.png"
        Save-WebpOrPng -Bitmap $bP1 -RelPath "climate\clm_btn_push.png"
        Save-WebpOrPng -Bitmap $bN2 -RelPath "climate\clm_btn_02_nor.png"
        Save-WebpOrPng -Bitmap $bP2 -RelPath "climate\clm_btn_02_push.png"
        Save-WebpOrPng -Bitmap $bDialNor -RelPath "climate\clm_dial_nor.webp"
        Save-WebpOrPng -Bitmap $bDialPush -RelPath "climate\clm_dial_push.webp"
        $bN1.Dispose(); $bP1.Dispose(); $bN2.Dispose(); $bP2.Dispose(); $bDialNor.Dispose(); $bDialPush.Dispose()

        $bRectNor = Draw-ClmRectBtn 138 78 "nor"
        $bRectPush = Draw-ClmRectBtn 138 78 "push"
        $bRectSel = Draw-ClmRectBtn 138 78 "sel"
        Save-WebpOrPng -Bitmap $bRectNor -RelPath "climate\clm_rect_nor.png"
        Save-WebpOrPng -Bitmap $bRectPush -RelPath "climate\clm_rect_push.png"
        Save-WebpOrPng -Bitmap $bRectSel -RelPath "climate\clm_rect_sel.png"
        $bRectNor.Dispose(); $bRectPush.Dispose(); $bRectSel.Dispose()

        # Floating Warmer/Ventilation Popup Dialog Background (co_bg_popup.9.png)
        $bmpPop = New-Object System.Drawing.Bitmap(816, 595, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gPop = [System.Drawing.Graphics]::FromImage($bmpPop)
        $gPop.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gPop.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $pPop = New-RoundedRectPath -X 4 -Y 4 -W 808 -H 587 -R 18
        $bPopFill = New-Object System.Drawing.SolidBrush((Parse-HexColor $clmBgHex 248))
        $pPopBord = New-Object System.Drawing.Pen((Parse-HexColor $clmAccHex 245), 3.0)
        $pPopDiv  = New-Object System.Drawing.Pen((Parse-HexColor $clmSecHex 180), 2.0)
        $gPop.FillPath($bPopFill, $pPop)
        $gPop.DrawLine($pPopDiv, 28, 92, 788, 92)
        $gPop.DrawPath($pPopBord, $pPop)
        $bPopFill.Dispose(); $pPopBord.Dispose(); $pPopDiv.Dispose(); $pPop.Dispose(); $gPop.Dispose()
        Save-WebpOrPng -Bitmap $bmpPop -RelPath "climate\co_bg_popup.png"
        $bmpPop.Dispose()

        foreach ($folder in @("drawable-hdpi", "drawable-night-hdpi")) {
            $clmManifest.Add("res/$folder/co_bg_bottom.9.png|clm_bg_bottom.png")
            $clmManifest.Add("res/$folder/co_bg_title_bar.9.png|clm_bg_bottom.png")
            $clmManifest.Add("res/$folder/clm_bg_fan.png|clm_bg_fan.png")
            $clmManifest.Add("res/$folder/clm_btn_bg_nor.png|clm_btn_nor.png")
            $clmManifest.Add("res/$folder/clm_btn_bg_push.png|clm_btn_push.png")
            $clmManifest.Add("res/$folder/clm_btn_bg_focus.png|clm_btn_push.png")
            $clmManifest.Add("res/$folder/clm_btn_bg_nor_02.png|clm_btn_02_nor.png")
            $clmManifest.Add("res/$folder/clm_btn_bg_push_02.png|clm_btn_02_push.png")
            $clmManifest.Add("res/$folder/clm_btn_bg_focus_02.png|clm_btn_02_push.png")
            $clmManifest.Add("res/$folder/clm_bg_set_center_nor.webp|clm_dial_nor.webp")
            $clmManifest.Add("res/$folder/clm_bg_set_center_push.webp|clm_dial_push.webp")
            $clmManifest.Add("res/$folder/clm_bg_set_center_focus.webp|clm_dial_push.webp")
            $clmManifest.Add("res/$folder/clm_bg_set_center_sel.webp|clm_dial_push.webp")
            $clmManifest.Add("res/$folder/co_btn_bg_bottom_nor.9.png|clm_rect_nor.png")
            $clmManifest.Add("res/$folder/co_btn_bg_bottom_push.9.png|clm_rect_push.png")
            $clmManifest.Add("res/$folder/co_btn_bg_bottom_focus.9.png|clm_rect_push.png")
            $clmManifest.Add("res/$folder/co_btn_bg_bottom_sel.9.png|clm_rect_sel.png")
            $clmManifest.Add("res/$folder/co_btn_bg_nor.9.png|clm_rect_nor.png")
            $clmManifest.Add("res/$folder/co_btn_bg_push.9.png|clm_rect_push.png")
            $clmManifest.Add("res/$folder/co_bg_popup.9.png|co_bg_popup.png")
        }
        $clmManifest.Add("res/drawable-hdpi/clm_bg_bottom.9.png|clm_bg_bottom.png")
    }

    $sScale = if ($null -ne $clmCfg.seatScale -and [float]$clmCfg.seatScale -gt 0) { [float]$clmCfg.seatScale } else { 100.0 }
    $sOffX = if ($null -ne $clmCfg.seatOffsetX) { [float]$clmCfg.seatOffsetX } else { 0.0 }
    $sOffY = if ($null -ne $clmCfg.seatOffsetY) { [float]$clmCfg.seatOffsetY } else { 0.0 }

    $clmIconStyle = if ($clmCfg.warmerIconStyle) { [string]$clmCfg.warmerIconStyle } else { "oem" }
    $clmHeatHex   = if ($clmCfg.heatColor)       { [string]$clmCfg.heatColor }       else { "#FB923C" }
    $clmVentHex   = if ($clmCfg.ventColor)       { [string]$clmCfg.ventColor }       else { "#38BDF8" }

    if ($clmIconStyle -eq "themed") {
        $cHeat = Parse-HexColor $clmHeatHex 255
        $cVent = Parse-HexColor $clmVentHex 255

        # 1. Seat Warmer Icon (clm_ic_heat_s.webp 78x78) & Seat Ventilation Fan Icon (clm_ic_fan_s.webp 78x78)
        function Draw-WarmerSeatIcon([bool]$IsHeat) {
            $b = New-Object System.Drawing.Bitmap(78, 78, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($b)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $col = if ($IsHeat) { $cHeat } else { $cVent }
            $fillCol = if ($IsHeat) { Parse-HexColor $clmHeatHex 55 } else { Parse-HexColor $clmVentHex 55 }

            $ptsSeat = @(
                (New-Object System.Drawing.PointF(50, 14)),
                (New-Object System.Drawing.PointF(40, 52)),
                (New-Object System.Drawing.PointF(14, 52)),
                (New-Object System.Drawing.PointF(14, 62)),
                (New-Object System.Drawing.PointF(50, 62)),
                (New-Object System.Drawing.PointF(62, 16))
            )
            $bFill = New-Object System.Drawing.SolidBrush($fillCol)
            $pSeat = New-Object System.Drawing.Pen($col, 3.2)
            $pSeat.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
            $g.FillPolygon($bFill, $ptsSeat)
            $g.DrawPolygon($pSeat, $ptsSeat)

            if ($IsHeat) {
                $pWave = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.6)
                $pWave.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                $pWave.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                for ($wi = 0; $wi -lt 3; $wi++) {
                    $wx = 18.0 + ($wi * 9.0)
                    $g.DrawBezier($pWave, $wx, 44.0, ($wx - 4.5), 32.0, ($wx + 4.5), 24.0, $wx, 12.0)
                }
                $pWave.Dispose()
            } else {
                $bFan = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
                $fFan = New-Object System.Drawing.Font("Segoe UI Symbol", 20.0, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
                $sf = New-Object System.Drawing.StringFormat
                $sf.Alignment = [System.Drawing.StringAlignment]::Center
                $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
                $g.DrawString([char]0x2748, $fFan, $bFan, (New-Object System.Drawing.RectangleF(8, 12, 36, 36)), $sf)
                $sf.Dispose(); $fFan.Dispose(); $bFan.Dispose()
            }
            $bFill.Dispose(); $pSeat.Dispose(); $g.Dispose()
            return $b
        }

        $bHeatIc = Draw-WarmerSeatIcon $true
        $bFanIc  = Draw-WarmerSeatIcon $false
        Save-WebpOrPng -Bitmap $bHeatIc -RelPath "climate\clm_ic_heat_s.webp"
        Save-WebpOrPng -Bitmap $bFanIc  -RelPath "climate\clm_ic_fan_s.webp"
        $bHeatIc.Dispose(); $bFanIc.Dispose()

        # 2. Steering Wheel Warmer Icons (54x54 & 129x129)
        function Draw-SteeringWarmerIcon([int]$Sz) {
            $b = New-Object System.Drawing.Bitmap($Sz, $Sz, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($b)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $sc = $Sz / 54.0
            $g.ScaleTransform($sc, $sc)

            $pRim = New-Object System.Drawing.Pen($cHeat, 3.2)
            $g.DrawEllipse($pRim, 11, 18, 28, 28)
            $g.DrawLine($pRim, 13, 31, 37, 31)
            $g.DrawLine($pRim, 25, 31, 25, 45)
            $pWave = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.2)
            for ($wi = 0; $wi -lt 3; $wi++) {
                $wx = 18.0 + ($wi * 7.0)
                $g.DrawBezier($pWave, $wx, 24.0, ($wx - 3.0), 17.0, ($wx + 3.0), 12.0, $wx, 5.0)
            }
            $pWave.Dispose(); $pRim.Dispose(); $g.Dispose()
            return $b
        }
        $bSw54  = Draw-SteeringWarmerIcon 54
        $bSw129 = Draw-SteeringWarmerIcon 129
        Save-WebpOrPng -Bitmap $bSw54  -RelPath "climate\clm_ic_sw_heat_nor.webp"
        Save-WebpOrPng -Bitmap $bSw129 -RelPath "climate\clm_ic_sw_heat_nor_02.png"
        $bSw54.Dispose(); $bSw129.Dispose()

        # 3. 3-Step LED Indicator Bars (36x18, 24x48, 129x30)
        function Draw-WarmerLedBar([int]$W, [int]$H, [System.Drawing.Color]$Col, [bool]$IsLit) {
            $b = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($b)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $padX = [Math]::Max(2.0, [float]($W * 0.14))
            $padY = [Math]::Max(2.0, [float]($H * 0.22))
            $rw = $W - ($padX * 2.0)
            $rh = $H - ($padY * 2.0)
            $p = New-RoundedRectPath -X $padX -Y $padY -W $rw -H $rh -R ([Math]::Min($rw, $rh) * 0.35)
            $bFill = New-Object System.Drawing.SolidBrush($Col)
            $g.FillPath($bFill, $p)
            if ($IsLit) {
                $pRim = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 255, 255, 255), 1.2)
                $g.DrawPath($pRim, $p)
                $pRim.Dispose()
            }
            $bFill.Dispose(); $p.Dispose(); $g.Dispose()
            return $b
        }

        $cOffLed = [System.Drawing.Color]::FromArgb(95, 148, 163, 184)
        $bLed02Heat = Draw-WarmerLedBar 36 18 $cHeat $true
        $bLed02Vent = Draw-WarmerLedBar 36 18 $cVent $true
        $bLed02Off  = Draw-WarmerLedBar 36 18 $cOffLed $false
        Save-WebpOrPng -Bitmap $bLed02Heat -RelPath "climate\clm_btn_led_02_heat.webp"
        Save-WebpOrPng -Bitmap $bLed02Vent -RelPath "climate\clm_btn_led_02_vent.webp"
        Save-WebpOrPng -Bitmap $bLed02Off  -RelPath "climate\clm_btn_led_02_off.webp"
        $bLed02Heat.Dispose(); $bLed02Vent.Dispose(); $bLed02Off.Dispose()

        $bLedVHeat = Draw-WarmerLedBar 24 48 $cHeat $true
        $bLedVVent = Draw-WarmerLedBar 24 48 $cVent $true
        $bLedVOff  = Draw-WarmerLedBar 24 48 $cOffLed $false
        Save-WebpOrPng -Bitmap $bLedVHeat -RelPath "climate\clm_btn_led_heat.webp"
        Save-WebpOrPng -Bitmap $bLedVVent -RelPath "climate\clm_btn_led_vent.webp"
        Save-WebpOrPng -Bitmap $bLedVOff  -RelPath "climate\clm_btn_led_off.webp"
        $bLedVHeat.Dispose(); $bLedVVent.Dispose(); $bLedVOff.Dispose()

        $bLedSwOn  = Draw-WarmerLedBar 129 30 $cHeat $true
        $bLedSwOff = Draw-WarmerLedBar 129 30 $cOffLed $false
        Save-WebpOrPng -Bitmap $bLedSwOn  -RelPath "climate\clm_btn_led_sw_on.png"
        Save-WebpOrPng -Bitmap $bLedSwOff -RelPath "climate\clm_btn_led_sw_off.png"
        $bLedSwOn.Dispose(); $bLedSwOff.Dispose()

        foreach ($folder in @("drawable-hdpi", "drawable-night-hdpi")) {
            $clmManifest.Add("res/$folder/clm_ic_heat_s.webp|clm_ic_heat_s.webp")
            $clmManifest.Add("res/$folder/clm_ic_fan_s.webp|clm_ic_fan_s.webp")
            $clmManifest.Add("res/$folder/clm_ic_sw_heat_nor.webp|clm_ic_sw_heat_nor.webp")
            $clmManifest.Add("res/$folder/clm_ic_sw_heat_nor_02.png|clm_ic_sw_heat_nor_02.png")
            $clmManifest.Add("res/$folder/clm_btn_led_02_red_on.webp|clm_btn_led_02_heat.webp")
            $clmManifest.Add("res/$folder/clm_btn_led_02_blue_on.webp|clm_btn_led_02_vent.webp")
            $clmManifest.Add("res/$folder/clm_btn_led_02_on.webp|clm_btn_led_02_vent.webp")
            $clmManifest.Add("res/$folder/clm_btn_led_02_off.webp|clm_btn_led_02_off.webp")
            $clmManifest.Add("res/$folder/clm_btn_led_red_on.webp|clm_btn_led_heat.webp")
            $clmManifest.Add("res/$folder/clm_btn_led_on.webp|clm_btn_led_vent.webp")
            $clmManifest.Add("res/$folder/clm_btn_led_off.webp|clm_btn_led_off.webp")
            $clmManifest.Add("res/$folder/clm_btn_led_red_on_02.png|clm_btn_led_sw_on.png")
            $clmManifest.Add("res/$folder/clm_btn_led_on_04.png|clm_btn_led_sw_on.png")
            $clmManifest.Add("res/$folder/clm_btn_led_off_04.png|clm_btn_led_sw_off.png")
        }
    }

    function Draw-CaptainsChairOnGraphics {
        param(
            [System.Drawing.Graphics]$G,
            [string]$SeatColHex = "#38BDF8",
            [string]$SeatAccHex = "#3B82F6"
        )
        $cCol = Parse-HexColor $SeatColHex 255
        $cAcc = Parse-HexColor $SeatAccHex 255
        $pDark = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 61, 67, 75), 1.6)
        $pDark.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

        # 1. Ambient Floor Shadow
        $bSh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(95, 0, 0, 0))
        $G.FillEllipse($bSh, 56, 308, 184, 36)
        $bSh.Dispose()

        # 2. Three-Block Angled Trapezoidal Pedestal Base
        $bPed1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 93, 100, 111))
        $ptsPed1 = @(
            (New-Object System.Drawing.PointF(96, 268)),
            (New-Object System.Drawing.PointF(132, 250)),
            (New-Object System.Drawing.PointF(148, 256)),
            (New-Object System.Drawing.PointF(116, 308)),
            (New-Object System.Drawing.PointF(90, 294))
        )
        $G.FillPolygon($bPed1, $ptsPed1); $G.DrawPolygon($pDark, $ptsPed1)

        $bPed2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 108, 116, 128))
        $ptsPed2 = @(
            (New-Object System.Drawing.PointF(106, 278)),
            (New-Object System.Drawing.PointF(148, 256)),
            (New-Object System.Drawing.PointF(166, 264)),
            (New-Object System.Drawing.PointF(146, 324)),
            (New-Object System.Drawing.PointF(126, 314))
        )
        $G.FillPolygon($bPed2, $ptsPed2); $G.DrawPolygon($pDark, $ptsPed2)

        $bPed3Top = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 139, 147, 159))
        $ptsPed3Top = @(
            (New-Object System.Drawing.PointF(134, 286)),
            (New-Object System.Drawing.PointF(182, 260)),
            (New-Object System.Drawing.PointF(222, 278)),
            (New-Object System.Drawing.PointF(176, 308))
        )
        $G.FillPolygon($bPed3Top, $ptsPed3Top); $G.DrawPolygon($pDark, $ptsPed3Top)

        $bPed3R = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 115, 123, 134))
        $ptsPed3R = @(
            (New-Object System.Drawing.PointF(176, 308)),
            (New-Object System.Drawing.PointF(222, 278)),
            (New-Object System.Drawing.PointF(180, 338))
        )
        $G.FillPolygon($bPed3R, $ptsPed3R); $G.DrawPolygon($pDark, $ptsPed3R)

        $bPed3F = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 86, 93, 103))
        $ptsPed3F = @(
            (New-Object System.Drawing.PointF(134, 286)),
            (New-Object System.Drawing.PointF(176, 308)),
            (New-Object System.Drawing.PointF(180, 338)),
            (New-Object System.Drawing.PointF(150, 320))
        )
        $G.FillPolygon($bPed3F, $ptsPed3F); $G.DrawPolygon($pDark, $ptsPed3F)
        $bPed1.Dispose(); $bPed2.Dispose(); $bPed3Top.Dispose(); $bPed3R.Dispose(); $bPed3F.Dispose()

        # 3. Cylindrical Swivel Collar Ring
        $bCollar1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 94, 101, 112))
        $bCollar2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 136, 144, 156))
        $pAccCol  = New-Object System.Drawing.Pen($cAcc, 1.6)
        $G.FillEllipse($bCollar1, 123, 248, 50, 18)
        $G.DrawEllipse($pAccCol, 123, 248, 50, 18)
        $G.FillEllipse($bCollar2, 125, 244, 46, 15)
        $G.DrawEllipse($pDark, 125, 244, 46, 15)
        $bCollar1.Dispose(); $bCollar2.Dispose()

        # 4. Left Wing & Left Armrest Console
        $bLWing = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 96, 104, 115))
        $ptsLWing = @(
            (New-Object System.Drawing.PointF(92, 236)),
            (New-Object System.Drawing.PointF(30, 174)),
            (New-Object System.Drawing.PointF(118, 138)),
            (New-Object System.Drawing.PointF(154, 174)),
            (New-Object System.Drawing.PointF(136, 224))
        )
        $G.FillPolygon($bLWing, $ptsLWing); $G.DrawPolygon($pDark, $ptsLWing)

        $bLTop = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 170, 178, 189))
        $ptsLTop = @(
            (New-Object System.Drawing.PointF(16, 158)),
            (New-Object System.Drawing.PointF(104, 128)),
            (New-Object System.Drawing.PointF(124, 134)),
            (New-Object System.Drawing.PointF(38, 166))
        )
        $G.FillPolygon($bLTop, $ptsLTop); $G.DrawPolygon($pDark, $ptsLTop)

        $bLIn = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 115, 123, 134))
        $ptsLIn = @(
            (New-Object System.Drawing.PointF(38, 166)),
            (New-Object System.Drawing.PointF(124, 134)),
            (New-Object System.Drawing.PointF(120, 146)),
            (New-Object System.Drawing.PointF(36, 178))
        )
        $G.FillPolygon($bLIn, $ptsLIn); $G.DrawPolygon($pDark, $ptsLIn)

        $bLFront = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 141, 149, 161))
        $ptsLFront = @(
            (New-Object System.Drawing.PointF(16, 158)),
            (New-Object System.Drawing.PointF(38, 166)),
            (New-Object System.Drawing.PointF(36, 178)),
            (New-Object System.Drawing.PointF(18, 170))
        )
        $G.FillPolygon($bLFront, $ptsLFront); $G.DrawPolygon($pDark, $ptsLFront)

        $bLPad = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 186, 194, 204))
        $pWireCol = New-Object System.Drawing.Pen($cCol, 1.4)
        $ptsLPad = @(
            (New-Object System.Drawing.PointF(36, 154)),
            (New-Object System.Drawing.PointF(86, 136)),
            (New-Object System.Drawing.PointF(96, 139)),
            (New-Object System.Drawing.PointF(46, 157))
        )
        $G.FillPolygon($bLPad, $ptsLPad); $G.DrawPolygon($pWireCol, $ptsLPad)
        $bLWing.Dispose(); $bLTop.Dispose(); $bLIn.Dispose(); $bLFront.Dispose(); $bLPad.Dispose()

        # 5. Rear Vertical Spine Post
        $bSpine = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 72, 79, 88))
        $G.FillRectangle($bSpine, 194, 42, 16, 148)
        $G.DrawRectangle($pDark, 194, 42, 16, 148)
        $bSpine.Dispose()

        # 6. Three-Tier Segmented Backrest Cushions (Lumbar, Mid Torso, Headrest)
        $bPad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(145, 24)),
            (New-Object System.Drawing.PointF(245, 190)),
            [System.Drawing.Color]::FromArgb(255, 198, 205, 214),
            [System.Drawing.Color]::FromArgb(255, 148, 156, 168)
        )
        $lumbar = New-RoundedRectPath -X 148 -Y 146 -W 86 -H 28 -R 7
        $G.FillPath($bPad, $lumbar); $G.DrawPath($pDark, $lumbar); $lumbar.Dispose()

        $ptsMidBack = @(
            (New-Object System.Drawing.PointF(152, 80)),
            (New-Object System.Drawing.PointF(242, 84)),
            (New-Object System.Drawing.PointF(238, 140)),
            (New-Object System.Drawing.PointF(146, 134))
        )
        $G.FillPolygon($bPad, $ptsMidBack); $G.DrawPolygon($pDark, $ptsMidBack)

        $ptsHeadrest = @(
            (New-Object System.Drawing.PointF(158, 30)),
            (New-Object System.Drawing.PointF(246, 28)),
            (New-Object System.Drawing.PointF(244, 68)),
            (New-Object System.Drawing.PointF(154, 66))
        )
        $G.FillPolygon($bPad, $ptsHeadrest); $G.DrawPolygon($pDark, $ptsHeadrest)
        $G.DrawLine($pWireCol, 158, 65, 240, 67)
        $G.DrawLine($pWireCol, 150, 132, 234, 139)

        # 7. Seat Pan Lip & Contoured Seat Cushion
        $bLip = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 90, 98, 109))
        $ptsLip = @(
            (New-Object System.Drawing.PointF(90, 234)),
            (New-Object System.Drawing.PointF(176, 262)),
            (New-Object System.Drawing.PointF(194, 248)),
            (New-Object System.Drawing.PointF(96, 220))
        )
        $G.FillPolygon($bLip, $ptsLip); $G.DrawPolygon($pDark, $ptsLip); $bLip.Dispose()

        $ptsCush = @(
            (New-Object System.Drawing.PointF(92, 206)),
            (New-Object System.Drawing.PointF(152, 178)),
            (New-Object System.Drawing.PointF(208, 194)),
            (New-Object System.Drawing.PointF(172, 242)),
            (New-Object System.Drawing.PointF(152, 244)),
            (New-Object System.Drawing.PointF(90, 220))
        )
        $G.FillPolygon($bPad, $ptsCush); $G.DrawPolygon($pDark, $ptsCush)
        $bPad.Dispose()

        # 8. Foreground Right Wing & Sloped Right Command Console Armrest
        $bRSide = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(154, 148)),
            (New-Object System.Drawing.PointF(285, 260)),
            [System.Drawing.Color]::FromArgb(255, 124, 133, 145),
            [System.Drawing.Color]::FromArgb(255, 88, 96, 107)
        )
        $ptsRSide = @(
            (New-Object System.Drawing.PointF(154, 204)),
            (New-Object System.Drawing.PointF(278, 148)),
            (New-Object System.Drawing.PointF(290, 158)),
            (New-Object System.Drawing.PointF(230, 234)),
            (New-Object System.Drawing.PointF(176, 262))
        )
        $G.FillPolygon($bRSide, $ptsRSide); $G.DrawPolygon($pDark, $ptsRSide); $bRSide.Dispose()

        $bRTop = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(140, 138)),
            (New-Object System.Drawing.PointF(286, 200)),
            [System.Drawing.Color]::FromArgb(255, 200, 207, 216),
            [System.Drawing.Color]::FromArgb(255, 159, 167, 179)
        )
        $ptsRTop = @(
            (New-Object System.Drawing.PointF(140, 180)),
            (New-Object System.Drawing.PointF(236, 138)),
            (New-Object System.Drawing.PointF(286, 146)),
            (New-Object System.Drawing.PointF(194, 200))
        )
        $G.FillPolygon($bRTop, $ptsRTop); $G.DrawPolygon($pDark, $ptsRTop); $bRTop.Dispose()

        $bRRim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 139, 147, 159))
        $ptsRRim = @(
            (New-Object System.Drawing.PointF(194, 200)),
            (New-Object System.Drawing.PointF(286, 146)),
            (New-Object System.Drawing.PointF(290, 158)),
            (New-Object System.Drawing.PointF(192, 214))
        )
        $G.FillPolygon($bRRim, $ptsRRim); $G.DrawPolygon($pDark, $ptsRRim)

        $ptsRFront = @(
            (New-Object System.Drawing.PointF(138, 180)),
            (New-Object System.Drawing.PointF(194, 200)),
            (New-Object System.Drawing.PointF(192, 214)),
            (New-Object System.Drawing.PointF(140, 195))
        )
        $G.FillPolygon($bRRim, $ptsRFront); $G.DrawPolygon($pDark, $ptsRFront); $bRRim.Dispose()

        $bSlot = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 109, 117, 128))
        $ptsSlot = @(
            (New-Object System.Drawing.PointF(145, 185)),
            (New-Object System.Drawing.PointF(186, 200)),
            (New-Object System.Drawing.PointF(185, 208)),
            (New-Object System.Drawing.PointF(146, 193))
        )
        $G.FillPolygon($bSlot, $ptsSlot); $G.DrawPolygon($pWireCol, $ptsSlot); $bSlot.Dispose()

        # Right Armrest Top Rectangular Control Panel Pad & 3 Command Buttons
        $bRPad = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 186, 194, 204))
        $ptsRPad = @(
            (New-Object System.Drawing.PointF(158, 178)),
            (New-Object System.Drawing.PointF(214, 152)),
            (New-Object System.Drawing.PointF(248, 162)),
            (New-Object System.Drawing.PointF(192, 190))
        )
        $G.FillPolygon($bRPad, $ptsRPad); $G.DrawPolygon($pAccCol, $ptsRPad); $bRPad.Dispose()

        $bBtn1 = New-Object System.Drawing.SolidBrush($cCol)
        $bBtn2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 251, 191, 36))
        $bBtn3 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 239, 68, 68))
        $G.FillEllipse($bBtn1, 218, 145, 8, 5)
        $G.FillEllipse($bBtn2, 229, 148, 8, 5)
        $G.FillEllipse($bBtn3, 226, 141, 8, 5)
        $bBtn1.Dispose(); $bBtn2.Dispose(); $bBtn3.Dispose()

        $pAccCol.Dispose(); $pWireCol.Dispose(); $pDark.Dispose()
    }

    if ($clmSeatStyle -eq "oem") {
        if ($sScale -ne 100.0 -or $sOffX -ne 0.0 -or $sOffY -ne 0.0) {
            $clmRuntimeLines.Add("scaleOemClimateSeat=true")
            $clmRuntimeLines.Add("seatScale=$sScale")
            $clmRuntimeLines.Add("seatOffX=$sOffX")
            $clmRuntimeLines.Add("seatOffY=$sOffY")
        }
    } else {
        $seatColHex = if ($clmCfg.seatColor) { [string]$clmCfg.seatColor } else { [string]$cfg.colors.accentBlue }
        $seatAccHex = if ($clmCfg.seatAccentColor) { [string]$clmCfg.seatAccentColor } else { [string]$cfg.colors.primary }

        # 1. Center 3D Seat Graphic for NewClimateControl (clm_bg_seat.png 309x351, facing 3/4 left like Photo 2)
        $bmpCenterSeat = New-Object System.Drawing.Bitmap(309, 351, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gCS = [System.Drawing.Graphics]::FromImage($bmpCenterSeat)
        $gCS.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gCS.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

        $drewCustomCenter = $false
        if ($clmSeatStyle -eq "custom" -and $clmCfg.customDriverSeatFile) {
            $cPath = Join-Path $CustomAssetsDir ([string]$clmCfg.customDriverSeatFile)
            if (Test-Path $cPath) {
                $drewCustomCenter = Draw-FittedImageInBox -G $gCS -ImgPath $cPath -BoxX 0 -BoxY 0 -TargetW 309 -TargetH 351 -Fit "contain" -ScalePct $sScale -OffsetX $sOffX -OffsetY $sOffY
            }
        }
        if (-not $drewCustomCenter) {
            $stCS = $gCS.Save()
            $gCS.TranslateTransform(154.5 + $sOffX, 175.5 + $sOffY)
            $gCS.ScaleTransform(($sScale / 100.0), ($sScale / 100.0))
            $gCS.TranslateTransform(-154.5, -175.5)

            if ($clmSeatStyle -eq "captainsChair") {
                Draw-CaptainsChairOnGraphics -G $gCS -SeatColHex $seatColHex -SeatAccHex $seatAccHex
            } else {
                $pWire = New-Object System.Drawing.Pen((Parse-HexColor $seatColHex 235), 2.8)
                $pRib  = New-Object System.Drawing.Pen((Parse-HexColor $seatColHex 115), 1.6)
                $pAcc  = New-Object System.Drawing.Pen((Parse-HexColor $seatAccHex 230), 2.4)
                $bFill = New-Object System.Drawing.SolidBrush((Parse-HexColor $seatColHex 48))

                # Headrest (top-right, angled 3/4 left)
                $hr = New-RoundedRectPath -X 162 -Y 16 -W 78 -H 54 -R 16
                $gCS.FillPath($bFill, $hr); $gCS.DrawPath($pAcc, $hr); $hr.Dispose()
                # Backrest (contoured 3/4 left)
                $bk = New-RoundedRectPath -X 138 -Y 76 -W 126 -H 184 -R 26
                $gCS.FillPath($bFill, $bk); $gCS.DrawPath($pWire, $bk); $bk.Dispose()
                $gCS.DrawLine($pRib, 152, 122, 248, 122)
                $gCS.DrawLine($pRib, 150, 166, 246, 166)
                $gCS.DrawLine($pRib, 148, 210, 244, 210)
                # Seat bottom cushion extending forward-left
                $cu = New-RoundedRectPath -X 38 -Y 242 -W 216 -H 74 -R 24
                $gCS.FillPath($bFill, $cu); $gCS.DrawPath($pWire, $cu); $cu.Dispose()
                $gCS.DrawLine($pRib, 92, 252, 92, 306)
                $gCS.DrawLine($pRib, 148, 252, 148, 306)
                # Lower trim rail
                $bs = New-RoundedRectPath -X 64 -Y 318 -W 182 -H 18 -R 7
                $gCS.DrawPath($pAcc, $bs); $bs.Dispose()

                $pWire.Dispose(); $pRib.Dispose(); $pAcc.Dispose(); $bFill.Dispose()
            }
            $gCS.Restore($stCS)
        }
        $gCS.Dispose()
        Save-WebpOrPng -Bitmap $bmpCenterSeat -RelPath "climate\clm_bg_seat.png"
        $bmpCenterSeat.Dispose()

        function Draw-SeatGraphic([bool]$IsPassenger, [string]$Mode, [int]$Level) {
            $bmp = New-Object System.Drawing.Bitmap(540, 432, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

            $drewCustomSeat = $false
            if ($clmSeatStyle -eq "custom") {
                $cf = if ($IsPassenger -and $clmCfg.customPassengerSeatFile) { [string]$clmCfg.customPassengerSeatFile } elseif ($clmCfg.customDriverSeatFile) { [string]$clmCfg.customDriverSeatFile } else { "" }
                if ($cf) {
                    $cPath = Join-Path $CustomAssetsDir $cf
                    if (Test-Path $cPath) {
                        $drewCustomSeat = Draw-FittedImageInBox -G $g -ImgPath $cPath -BoxX 0 -BoxY 0 -TargetW 540 -TargetH 432 -Fit "contain" -ScalePct $sScale -OffsetX $sOffX -OffsetY $sOffY
                    }
                }
            }

            if (-not $drewCustomSeat) {
                $state = $g.Save()
                $g.TranslateTransform(270.0 + $sOffX, 216.0 + $sOffY)
                $dir = if ($IsPassenger) { -1.0 } else { 1.0 }
                $g.ScaleTransform($dir * ($sScale / 100.0), ($sScale / 100.0))
                $g.TranslateTransform(-270.0, -216.0)

                if ($clmSeatStyle -eq "captainsChair") {
                    $stCh = $g.Save()
                    $g.TranslateTransform(88.0, 18.0)
                    $g.ScaleTransform(1.15, 1.12)
                    Draw-CaptainsChairOnGraphics -G $g -SeatColHex $seatColHex -SeatAccHex $seatAccHex
                    $g.Restore($stCh)
                } else {
                    $pWire = New-Object System.Drawing.Pen((Parse-HexColor $seatColHex 230), 2.8)
                    $pRib  = New-Object System.Drawing.Pen((Parse-HexColor $seatColHex 110), 1.6)
                    $pAcc  = New-Object System.Drawing.Pen((Parse-HexColor $seatAccHex 220), 2.4)
                    $bFill = New-Object System.Drawing.SolidBrush((Parse-HexColor $seatColHex 42))

                    $hr = New-RoundedRectPath -X 195 -Y 28 -W 92 -H 62 -R 18
                    $g.FillPath($bFill, $hr); $g.DrawPath($pAcc, $hr); $hr.Dispose()
                    $bk = New-RoundedRectPath -X 175 -Y 98 -W 132 -H 188 -R 24
                    $g.FillPath($bFill, $bk); $g.DrawPath($pWire, $bk); $bk.Dispose()
                    $g.DrawLine($pRib, 195, 145, 287, 145)
                    $g.DrawLine($pRib, 195, 190, 287, 190)
                    $g.DrawLine($pRib, 195, 235, 287, 235)
                    $cu = New-RoundedRectPath -X 185 -Y 284 -W 195 -H 78 -R 22
                    $g.FillPath($bFill, $cu); $g.DrawPath($pWire, $cu); $cu.Dispose()
                    $g.DrawLine($pRib, 235, 294, 235, 352)
                    $g.DrawLine($pRib, 290, 294, 290, 352)
                    $g.DrawLine($pRib, 340, 294, 340, 352)
                    $bs = New-RoundedRectPath -X 195 -Y 366 -W 170 -H 22 -R 8
                    $g.DrawPath($pAcc, $bs); $bs.Dispose()

                    $pWire.Dispose(); $pRib.Dispose(); $pAcc.Dispose(); $bFill.Dispose()
                }
                $g.Restore($state)
            }

            if ($Level -gt 0) {
                $wCol = if ($Mode -eq "heat") { [System.Drawing.Color]::FromArgb(235, 255, 95, 35) } else { [System.Drawing.Color]::FromArgb(235, 56, 189, 248) }
                $pWave = New-Object System.Drawing.Pen($wCol, 4.5)
                $pWave.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                $pWave.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                for ($wi = 0; $wi -lt $Level; $wi++) {
                    $wx = 225 + ($wi * 36)
                    $g.DrawBezier($pWave, $wx, 295, ($wx - 14), 255, ($wx + 14), 215, $wx, 175)
                }
                $pWave.Dispose()
            }

            $g.Dispose()
            return $bmp
        }

        $bDrv = Draw-SeatGraphic $false "norm" 0
        $bPas = Draw-SeatGraphic $true  "norm" 0
        Save-WebpOrPng -Bitmap $bDrv -RelPath "climate\driver_seat.webp"
        Save-WebpOrPng -Bitmap $bPas -RelPath "climate\passenger_seat.webp"

        $bSeatL = New-Object System.Drawing.Bitmap(477, 270, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gSL = [System.Drawing.Graphics]::FromImage($bSeatL); $gSL.DrawImage($bDrv, 40, 0, 397, 270); $gSL.Dispose()
        $bSeatR = New-Object System.Drawing.Bitmap(477, 270, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gSR = [System.Drawing.Graphics]::FromImage($bSeatR); $gSR.DrawImage($bPas, 40, 0, 397, 270); $gSR.Dispose()
        Save-WebpOrPng -Bitmap $bSeatL -RelPath "climate\seat_l.webp"
        Save-WebpOrPng -Bitmap $bSeatR -RelPath "climate\seat_r.webp"
        $bSeatL.Dispose(); $bSeatR.Dispose(); $bDrv.Dispose(); $bPas.Dispose()

        for ($lv = 1; $lv -le 3; $lv++) {
            $n = $lv.ToString("00")
            $dh = Draw-SeatGraphic $false "heat" $lv; Save-WebpOrPng -Bitmap $dh -RelPath "climate\driver_heat_$n.webp"; $dh.Dispose()
            $dv = Draw-SeatGraphic $false "vent" $lv; Save-WebpOrPng -Bitmap $dv -RelPath "climate\driver_vent_$n.webp"; $dv.Dispose()
            $ph = Draw-SeatGraphic $true  "heat" $lv; Save-WebpOrPng -Bitmap $ph -RelPath "climate\passenger_heat_$n.webp"; $ph.Dispose()
            $pv = Draw-SeatGraphic $true  "vent" $lv; Save-WebpOrPng -Bitmap $pv -RelPath "climate\passenger_vent_$n.webp"; $pv.Dispose()
        }

        foreach ($folder in @("drawable-hdpi", "drawable-night-hdpi")) {
            $clmManifest.Add("res/$folder/clm_bg_seat.png|clm_bg_seat.png")
            $clmManifest.Add("res/$folder/clm_bg_driver_seat.webp|driver_seat.webp")
            $clmManifest.Add("res/$folder/clm_bg_passenger_seat.webp|passenger_seat.webp")
            $clmManifest.Add("res/$folder/clm_bg_seat_l.webp|seat_l.webp")
            $clmManifest.Add("res/$folder/clm_bg_seat_r.webp|seat_r.webp")
            for ($lv = 1; $lv -le 3; $lv++) {
                $n = $lv.ToString("00")
                $clmManifest.Add("res/$folder/clm_bg_driver_heat_$n.webp|driver_heat_$n.webp")
                $clmManifest.Add("res/$folder/clm_bg_driver_vent_$n.webp|driver_vent_$n.webp")
                $clmManifest.Add("res/$folder/clm_bg_passenger_heat_$n.webp|passenger_heat_$n.webp")
                $clmManifest.Add("res/$folder/clm_bg_passenger_vent_$n.webp|passenger_vent_$n.webp")
            }
        }
    }

    if ($null -ne $hsCfg -and $hsCfg.applyFontToClimate -eq $true -and $script:ResolvedThemeFontFile -and (Test-Path $script:ResolvedThemeFontFile)) {
        $clmDirFont = Join-Path $themeOutDir "climate"
        New-Item -ItemType Directory -Force -Path $clmDirFont | Out-Null
        Copy-Item $script:ResolvedThemeFontFile (Join-Path $clmDirFont "CubeB.ttf") -Force
        $clmManifest.Add("assets/CubeB.ttf|CubeB.ttf")
    }

    if ($clmManifest.Count -gt 0 -or $clmRuntimeLines.Count -gt 0) {
        $clmDir = Join-Path $themeOutDir "climate"
        New-Item -ItemType Directory -Force -Path $clmDir | Out-Null
        [System.IO.File]::WriteAllLines((Join-Path $clmDir "manifest.txt"), $clmManifest, $utf8NoBom)
        if ($clmRuntimeLines.Count -gt 0) {
            [System.IO.File]::WriteAllLines((Join-Path $clmDir "runtime-composite.txt"), $clmRuntimeLines, $utf8NoBom)
        }
    }
}

# --- C. EV Screen (HKMC_TAppEV3.apk) ---
$evCfg = $cfg.evScreen
if ($null -ne $evCfg) {
    $evBgMode = if ($evCfg.bgMode) { [string]$evCfg.bgMode } else { "oem" }
    $evCarStyle = if ($evCfg.carStyle) { [string]$evCfg.carStyle } else { "oem" }
    $evCardStyle = if ($evCfg.cardStyle) { [string]$evCfg.cardStyle } else { "oem" }
    $evHideRadar = ($evCfg.hideRangeRadar -eq $true)
    $evManifest = New-Object 'System.Collections.Generic.List[string]'
    $evRuntimeLines = New-Object 'System.Collections.Generic.List[string]'

    $evBgHex = if ($evCfg.bgColor) { [string]$evCfg.bgColor } else { "#060911" }
    $evAccHex = if ($evCfg.accentColor) { [string]$evCfg.accentColor } else { [string]$cfg.colors.primary }
    $evSecHex = if ($evCfg.secondaryColor) { [string]$evCfg.secondaryColor } else { [string]$cfg.colors.accentBlue }

    if ($evBgMode -ne "oem") {
        $bmpEvBg = New-Object System.Drawing.Bitmap(1920, 720, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gEv = [System.Drawing.Graphics]::FromImage($bmpEvBg)
        $gEv.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $bBg = New-Object System.Drawing.SolidBrush((Parse-HexColor $evBgHex 255))
        $gEv.FillRectangle($bBg, 0, 0, 1920, 720)
        $bBg.Dispose()

        if ($evBgMode -eq "custom" -and $evCfg.customBgFile) {
            $cFile = Join-Path $CustomAssetsDir ([string]$evCfg.customBgFile)
            $cFit = if ($evCfg.bgFit) { [string]$evCfg.bgFit } else { "cover" }
            $cScale = if ($null -ne $evCfg.bgScale) { [float]$evCfg.bgScale } else { 100.0 }
            $cOffX = if ($null -ne $evCfg.bgOffsetX) { [float]$evCfg.bgOffsetX } else { 0.0 }
            $cOffY = if ($null -ne $evCfg.bgOffsetY) { [float]$evCfg.bgOffsetY } else { 0.0 }
            $drew = Draw-FittedImage -G $gEv -ImgPath $cFile -TargetW 1920 -TargetH 720 -Fit $cFit -ScalePct $cScale -OffsetX $cOffX -OffsetY $cOffY
            if ($drew -and ([int]$evCfg.bgDim) -gt 0) {
                $dAlpha = [int][Math]::Round(([float]$evCfg.bgDim / 100.0) * 255)
                $bDim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($dAlpha, 0, 0, 0))
                $gEv.FillRectangle($bDim, 0, 0, 1920, 720)
                $bDim.Dispose()
            }
        }

        if ($evBgMode -eq "lcars" -or $evCfg.showLcarsFrame -eq $true) {
            $pGrid = New-Object System.Drawing.Pen((Parse-HexColor $evSecHex 28), 1)
            for ($x = 80; $x -lt 1880; $x += 90) { $gEv.DrawLine($pGrid, $x, 170, $x, 565) }
            for ($y = 180; $y -lt 565; $y += 80) { $gEv.DrawLine($pGrid, 35, $y, 1885, $y) }
            $pGrid.Dispose()

            $bAcc = New-Object System.Drawing.SolidBrush((Parse-HexColor $evAccHex 255))
            $bSec = New-Object System.Drawing.SolidBrush((Parse-HexColor $evSecHex 255))
            $bPeach = New-Object System.Drawing.SolidBrush($cPeach)
            $gEv.FillRectangle($bAcc, 10, 168, 16, 160)
            $gEv.FillRectangle($bSec, 10, 336, 16, 130)
            $gEv.FillRectangle($bPeach, 10, 474, 16, 85)
            $gEv.FillRectangle($bAcc, 34, 162, 520, 6)
            $gEv.FillRectangle($bSec, 562, 162, 790, 6)
            $gEv.FillRectangle($bPeach, 1360, 162, 535, 6)
            $bAcc.Dispose(); $bSec.Dispose(); $bPeach.Dispose()
        }

        $gEv.Dispose()
        Save-WebpOrPng -Bitmap $bmpEvBg -RelPath "ev\co_bg_main.png"
        $bmpEvBg.Dispose()

        $bmpTitle = New-Object System.Drawing.Bitmap(1920, 82, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gTit = [System.Drawing.Graphics]::FromImage($bmpTitle)
        $bTitBg = New-Object System.Drawing.SolidBrush((Parse-HexColor $evBgHex 250))
        $bTitAcc = New-Object System.Drawing.SolidBrush((Parse-HexColor $evAccHex 255))
        $gTit.FillRectangle($bTitBg, 0, 0, 1920, 82)
        $gTit.FillRectangle($bTitAcc, 0, 78, 1920, 4)
        $bTitBg.Dispose(); $bTitAcc.Dispose(); $gTit.Dispose()
        Save-WebpOrPng -Bitmap $bmpTitle -RelPath "ev\co_bg_title_bar.png"
        $bmpTitle.Dispose()

        $evManifest.Add("res/drawable-nodpi/co_bg_main.png|co_bg_main.png")
        $evManifest.Add("res/drawable-nodpi/co_bg_title_bar.9.png|co_bg_title_bar.png")
        $evManifest.Add("res/drawable-night-nodpi/co_bg_title_bar.9.png|co_bg_title_bar.png")
    }

    if ($evCardStyle -ne "oem") {
        $bmpBar = New-Object System.Drawing.Bitmap(1720, 118, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gBar = [System.Drawing.Graphics]::FromImage($bmpBar)
        $gBar.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gBar.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $pBar = New-RoundedRectPath -X 3 -Y 3 -W 1714 -H 112 -R 20
        $bBarBg = New-Object System.Drawing.SolidBrush((Parse-HexColor $evBgHex 235))
        $pBarAcc = New-Object System.Drawing.Pen((Parse-HexColor $evAccHex 235), 2.5)
        $gBar.FillPath($bBarBg, $pBar)
        $gBar.DrawPath($pBarAcc, $pBar)
        $bBarBg.Dispose(); $pBarAcc.Dispose(); $pBar.Dispose(); $gBar.Dispose()
        Save-WebpOrPng -Bitmap $bmpBar -RelPath "ev\ev_btn_main_nor.png"
        $bmpBar.Dispose()

        function Draw-EvCardBox([bool]$IsPush) {
            $b = New-Object System.Drawing.Bitmap(550, 92, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($b)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $p = New-RoundedRectPath -X 4 -Y 4 -W 542 -H 84 -R 16
            $fCol = if ($IsPush) { Parse-HexColor $evAccHex 95 } else { Parse-HexColor "#101827" 230 }
            $bCol = if ($IsPush) { Parse-HexColor $evAccHex 255 } else { Parse-HexColor $evSecHex 225 }
            $bf = New-Object System.Drawing.SolidBrush($fCol)
            $pb = New-Object System.Drawing.Pen($bCol, 2.2)
            $g.FillPath($bf, $p)
            if ($evCardStyle -eq "lcars") {
                $g.SetClip($p)
                $bSpine = New-Object System.Drawing.SolidBrush((Parse-HexColor $evAccHex 255))
                $g.FillRectangle($bSpine, 4, 4, 12, 84)
                $bSpine.Dispose()
                $g.ResetClip()
            }
            $g.DrawPath($pb, $p)
            $bf.Dispose(); $pb.Dispose(); $p.Dispose(); $g.Dispose()
            return $b
        }

        $bCardNor = Draw-EvCardBox $false
        $bCardPush = Draw-EvCardBox $true
        Save-WebpOrPng -Bitmap $bCardNor -RelPath "ev\co_bg_box_nor.png"
        Save-WebpOrPng -Bitmap $bCardPush -RelPath "ev\co_bg_box_push.png"
        $bCardNor.Dispose(); $bCardPush.Dispose()

        foreach ($folder in @("drawable-nodpi", "drawable-night-nodpi")) {
            $evManifest.Add("res/$folder/ev_btn_main_nor.9.png|ev_btn_main_nor.png")
            $evManifest.Add("res/$folder/co_bg_box_nor.9.png|co_bg_box_nor.png")
            $evManifest.Add("res/$folder/co_bg_box_push.9.png|co_bg_box_push.png")
            $evManifest.Add("res/$folder/co_bg_box_focus.9.png|co_bg_box_push.png")
            $evManifest.Add("res/$folder/ev_btn_bottom_bg_nor.9.png|co_bg_box_nor.png")
            $evManifest.Add("res/$folder/ev_btn_bottom_bg_push.9.png|co_bg_box_push.png")
            $evManifest.Add("res/$folder/ev_btn_bottom_bg_nor_l.9.png|co_bg_box_nor.png")
            $evManifest.Add("res/$folder/ev_btn_bottom_bg_push_l.9.png|co_bg_box_push.png")
            $evManifest.Add("res/$folder/ev_btn_bottom_bg_nor_r.9.png|co_bg_box_nor.png")
            $evManifest.Add("res/$folder/ev_btn_bottom_bg_push_r.9.png|co_bg_box_push.png")
            $evManifest.Add("res/$folder/co_btn_title_bg_nor.9.png|co_bg_box_nor.png")
            $evManifest.Add("res/$folder/co_btn_title_bg_push.9.png|co_bg_box_push.png")
            $evManifest.Add("res/$folder/co_btn_title_bg_focus.9.png|co_bg_box_push.png")
            $evManifest.Add("res/$folder/co_btn_title_bg_sel.9.png|co_bg_box_push.png")
        }
    }

    $effCarStyle = $evCarStyle
    $effCarFile = if ($evCfg.customCarFile) { [string]$evCfg.customCarFile } else { "" }
    $effCarScale = if ($null -ne $evCfg.carScale -and [float]$evCfg.carScale -gt 0) { [float]$evCfg.carScale } else { 100.0 }
    $effCarOffX = if ($null -ne $evCfg.carOffsetX) { [float]$evCfg.carOffsetX } else { 0.0 }
    $effCarOffY = if ($null -ne $evCfg.carOffsetY) { [float]$evCfg.carOffsetY } else { 0.0 }

    if ($evCarStyle -eq "sameAsHome") {
        $effCarStyle = if ($bw.style) { [string]$bw.style } else { "oem" }
        $effCarFile = if ($bw.customFile) { [string]$bw.customFile } else { "" }
        $effCarScale = $bwScalePct
        $effCarOffX = $bwOffX
        $effCarOffY = $bwOffY
    }

    if ($effCarStyle -eq "oem") {
        if ($effCarScale -ne 100.0 -or $effCarOffX -ne 0.0 -or $effCarOffY -ne 0.0) {
            $evRuntimeLines.Add("scaleOemEvCar=true")
            $evRuntimeLines.Add("evCarScale=$effCarScale")
            $evRuntimeLines.Add("evCarOffX=$effCarOffX")
            $evRuntimeLines.Add("evCarOffY=$effCarOffY")
        }
    } else {
        $bmpEvCar = New-Object System.Drawing.Bitmap(450, 255, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gCar = [System.Drawing.Graphics]::FromImage($bmpEvCar)
        $gCar.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gCar.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

        $bmpCover = New-Object System.Drawing.Bitmap(450, 255, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gCov = [System.Drawing.Graphics]::FromImage($bmpCover)
        $gCov.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gCov.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

        if ($effCarStyle -eq "custom" -and $effCarFile) {
            $cPath = Join-Path $CustomAssetsDir $effCarFile
            Draw-FittedImageInBox -G $gCar -ImgPath $cPath -BoxX 0 -BoxY 0 -TargetW 450 -TargetH 255 -Fit "contain" -ScalePct $effCarScale -OffsetX $effCarOffX -OffsetY $effCarOffY | Out-Null
        } elseif ($effCarStyle -eq "galileo") {
            Draw-ShuttleGalileoOnGraphics -G $gCar -LayerMode "bg" -ScalePct $effCarScale -OffsetX $effCarOffX -OffsetY $effCarOffY -BoxW 450.0 -BoxH 255.0
            Draw-ShuttleGalileoOnGraphics -G $gCov -LayerMode "cover" -ScalePct $effCarScale -OffsetX $effCarOffX -OffsetY $effCarOffY -BoxW 450.0 -BoxH 255.0
        } elseif ($effCarStyle -eq "wireframeCar") {
            Draw-WireframeEvCarOnGraphics -G $gCar -LayerMode "bg" -ScalePct $effCarScale -OffsetX $effCarOffX -OffsetY $effCarOffY -BoxW 450.0 -BoxH 255.0
            Draw-WireframeEvCarOnGraphics -G $gCov -LayerMode "cover" -ScalePct $effCarScale -OffsetX $effCarOffX -OffsetY $effCarOffY -BoxW 450.0 -BoxH 255.0
        } else {
            # LCARS 3/4 Front-Right EV Crossover Wireframe (450x255, matching Ioniq 5 angle on EV screen)
            $state = $gCar.Save()
            $gCar.TranslateTransform(225.0 + $effCarOffX, 127.5 + $effCarOffY)
            $gCar.ScaleTransform(($effCarScale / 100.0), ($effCarScale / 100.0))
            $gCar.TranslateTransform(-225.0, -127.5)

            $pBody = New-Object System.Drawing.Pen((Parse-HexColor $evSecHex 235), 2.5)
            $pAcc  = New-Object System.Drawing.Pen((Parse-HexColor $evAccHex 235), 2.2)
            $bBody = New-Object System.Drawing.SolidBrush((Parse-HexColor $evSecHex 48))
            $bGlass = New-Object System.Drawing.SolidBrush((Parse-HexColor $evSecHex 32))

            $silhouette = @(
                (New-Object System.Drawing.PointF(32, 165)),
                (New-Object System.Drawing.PointF(38, 108)),
                (New-Object System.Drawing.PointF(108, 52)),
                (New-Object System.Drawing.PointF(248, 46)),
                (New-Object System.Drawing.PointF(342, 92)),
                (New-Object System.Drawing.PointF(422, 118)),
                (New-Object System.Drawing.PointF(426, 168)),
                (New-Object System.Drawing.PointF(378, 186)),
                (New-Object System.Drawing.PointF(108, 206)),
                (New-Object System.Drawing.PointF(42, 192))
            )
            $gCar.FillPolygon($bBody, $silhouette)
            $gCar.DrawPolygon($pBody, $silhouette)

            $greenhouse = @(
                (New-Object System.Drawing.PointF(78, 105)),
                (New-Object System.Drawing.PointF(122, 62)),
                (New-Object System.Drawing.PointF(242, 56)),
                (New-Object System.Drawing.PointF(328, 94)),
                (New-Object System.Drawing.PointF(248, 108))
            )
            $gCar.FillPolygon($bGlass, $greenhouse)
            $gCar.DrawPolygon($pAcc, $greenhouse)

            # Rear & Front wheels
            $bWheel = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(240, 18, 24, 36))
            $gCar.FillEllipse($bWheel, 82, 152, 66, 66)
            $gCar.DrawEllipse($pAcc, 82, 152, 66, 66)
            $gCar.DrawEllipse($pBody, 98, 168, 34, 34)
            $gCar.FillEllipse($bWheel, 324, 134, 62, 62)
            $gCar.DrawEllipse($pAcc, 324, 134, 62, 62)
            $gCar.DrawEllipse($pBody, 340, 150, 30, 30)

            $bWheel.Dispose(); $pBody.Dispose(); $pAcc.Dispose(); $bBody.Dispose(); $bGlass.Dispose()
            $gCar.Restore($state)
        }
        $gCar.Dispose(); $gCov.Dispose()
        Save-WebpOrPng -Bitmap $bmpEvCar -RelPath "ev\ev_car.webp"
        Save-WebpOrPng -Bitmap $bmpCover -RelPath "ev\ev_cover_blank.webp"
        $bmpEvCar.Dispose(); $bmpCover.Dispose()

        $bgVariants = @("ev_ic_battery_bg.webp", "ev_ic_battery_bg_1ttruck_nor.webp", "ev_ic_battery_bg_1ttruck_war.webp", "ev_ic_battery_bg_ce_sedan_nor.webp", "ev_ic_battery_bg_ce_sedan_war.webp", "ev_ic_battery_bg_hatch_nor.webp", "ev_ic_battery_bg_hatch_war.webp", "ev_ic_battery_bg_nor.webp", "ev_ic_battery_bg_sedan_nor.webp", "ev_ic_battery_bg_sedan_war.webp", "ev_ic_battery_bg_suv_nor.webp", "ev_ic_battery_bg_suv_war.webp", "ev_ic_battery_bg_war.webp")
        $covVariants = @("ev_ic_battery_cover.webp", "ev_ic_battery_cover_1ttruck.webp", "ev_ic_battery_cover_ce_sedan.webp", "ev_ic_battery_cover_hatch.webp", "ev_ic_battery_cover_sedan.webp", "ev_ic_battery_cover_suv.webp")
        foreach ($folder in @("drawable-nodpi", "drawable-night-nodpi")) {
            foreach ($bv in $bgVariants) { $evManifest.Add("res/$folder/$bv|ev_car.webp") }
            foreach ($cv in $covVariants) { $evManifest.Add("res/$folder/$cv|ev_cover_blank.webp") }
        }
    }

    if ($evHideRadar) {
        $bmpRad = New-Object System.Drawing.Bitmap(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gRad = [System.Drawing.Graphics]::FromImage($bmpRad)
        $gRad.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $gRad.Dispose()
        Save-WebpOrPng -Bitmap $bmpRad -RelPath "ev\ev_radar_blank.webp"
        $bmpRad.Dispose()

        $cases = @(
            "case1_01","case1_02","case1_03","case1_04","case1_05","case1_06",
            "case2_07","case2_08","case2_09","case2_10","case2_11",
            "case3_12","case3_13","case3_14","case3_15","case3_16",
            "case4_17","case4_18","case4_19","case4_20","case4_21","case4_22","case5_loading"
        )
        foreach ($folder in @("drawable-nodpi", "drawable-night-nodpi")) {
            foreach ($cs in $cases) {
                $evManifest.Add("res/$folder/ev_etc_main_$cs.webp|ev_radar_blank.webp")
                $evManifest.Add("res/$folder/ev_etc_main_c_$cs.webp|ev_radar_blank.webp")
            }
        }
    }

    if ($evManifest.Count -gt 0 -or $evRuntimeLines.Count -gt 0) {
        $evDir = Join-Path $themeOutDir "ev"
        New-Item -ItemType Directory -Force -Path $evDir | Out-Null
        [System.IO.File]::WriteAllLines((Join-Path $evDir "manifest.txt"), $evManifest, $utf8NoBom)
        if ($evRuntimeLines.Count -gt 0) {
            [System.IO.File]::WriteAllLines((Join-Path $evDir "runtime-composite.txt"), $evRuntimeLines, $utf8NoBom)
        }
    }
}

if (Test-Path $tempPngDir) { Remove-Item -Recurse -Force $tempPngDir }

$runtimeCompositeLines = @(
    ("batteryStyle=" + [string]$bw.style),
    ("batteryScale=" + $bwScalePct),
    ("batteryOffX=" + $bwOffX),
    ("batteryOffY=" + $bwOffY),
    ("mediaOffX=" + $medOffX),
    ("mediaOffY=" + $medOffY),
    ("mediaFontScale=" + $medScale),
    ("compositeOemIcons=" + ($script:CompositeOemIconsList -join ","))
)
[System.IO.File]::WriteAllLines((Join-Path $themeOutDir "runtime-composite.txt"), $runtimeCompositeLines, $utf8NoBom)

$resRootDir = Join-Path $themeOutDir "res"
$allThemeFiles = @(Get-ChildItem $resRootDir -Recurse -File | ForEach-Object {
    $_.FullName.Substring($themeOutDir.Length + 1).Replace('\', '/')
})
$assetsRootDir = Join-Path $themeOutDir "assets"
if (Test-Path $assetsRootDir) {
    $allThemeFiles += @(Get-ChildItem $assetsRootDir -Recurse -File | ForEach-Object {
        $_.FullName.Substring($themeOutDir.Length + 1).Replace('\', '/')
    })
}
[System.IO.File]::WriteAllLines((Join-Path $themeOutDir "manifest.txt"), $allThemeFiles, $utf8NoBom)
$tNameStr = if ($cfg.themeName) { [string]$cfg.themeName } else { "Custom Theme" }
[System.IO.File]::WriteAllText((Join-Path $themeOutDir "theme-name.txt"), $tNameStr, $utf8NoBom)

$totalGenerated = $allThemeFiles.Count
$totalBytes = (Get-ChildItem $themeOutDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("SUCCESS: Generated $totalGenerated theme files ({0:N1} KB) in $themeOutDir" -f ($totalBytes / 1024.0))
