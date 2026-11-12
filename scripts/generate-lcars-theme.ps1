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
    $dp = [Math]::Max(0, [int][Math]::Round($BaseDp + ($OffsetPx / 1.5)))
    $bytes = [BitConverter]::GetBytes([uint32](($dp -shl 8) -bor 1))
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
$utf8NoBomInit = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $themeOutDir "layout-patches.txt"), $layoutPatchLines, $utf8NoBomInit)

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
        $fontLbl  = New-Object System.Drawing.Font("Segoe UI", $txtSizePx, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)

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
if (Test-Path $tempPngDir) { Remove-Item -Recurse -Force $tempPngDir }

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$runtimeCompositeLines = @(
    ("batteryStyle=" + [string]$bw.style),
    ("batteryScale=" + $bwScalePct),
    ("batteryOffX=" + $bwOffX),
    ("batteryOffY=" + $bwOffY),
    ("compositeOemIcons=" + ($script:CompositeOemIconsList -join ","))
)
[System.IO.File]::WriteAllLines((Join-Path $themeOutDir "runtime-composite.txt"), $runtimeCompositeLines, $utf8NoBom)

$allThemeFiles = Get-ChildItem $themeOutDir -Recurse -File | Where-Object {
    $_.Name -ne "manifest.txt" -and $_.Name -ne "theme-name.txt" -and $_.Name -ne "layout-patches.txt" -and $_.Name -ne "runtime-composite.txt"
} | ForEach-Object {
    $_.FullName.Substring($themeOutDir.Length + 1).Replace('\', '/')
}
[System.IO.File]::WriteAllLines((Join-Path $themeOutDir "manifest.txt"), $allThemeFiles, $utf8NoBom)
$tNameStr = if ($cfg.themeName) { [string]$cfg.themeName } else { "Custom Theme" }
[System.IO.File]::WriteAllText((Join-Path $themeOutDir "theme-name.txt"), $tNameStr, $utf8NoBom)

$totalGenerated = $allThemeFiles.Count
$totalBytes = (Get-ChildItem $themeOutDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("SUCCESS: Generated $totalGenerated theme files ({0:N1} KB) in $themeOutDir" -f ($totalBytes / 1024.0))
