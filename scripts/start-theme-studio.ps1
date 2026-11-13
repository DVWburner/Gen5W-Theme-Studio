#Requires -Version 5.1
param(
    [int]$Port = 8470,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$StudioVersion = "1.1.0"
$SchemaVersion = 3

function Ensure-ThemeConfigDefaults($CfgObj) {
    if ($null -eq $CfgObj) { return }
    if ($null -ne $CfgObj.homeScreen) {
        if (-not $CfgObj.homeScreen.PSObject.Properties["bgFit"])              { $CfgObj.homeScreen | Add-Member -NotePropertyName "bgFit"              -NotePropertyValue "cover" }
        if (-not $CfgObj.homeScreen.PSObject.Properties["mapFadeMode"])        { $CfgObj.homeScreen | Add-Member -NotePropertyName "mapFadeMode"        -NotePropertyValue "feather" }
        if (-not $CfgObj.homeScreen.PSObject.Properties["mapFadeWidth"])       { $CfgObj.homeScreen | Add-Member -NotePropertyName "mapFadeWidth"       -NotePropertyValue 75 }
        if (-not $CfgObj.homeScreen.PSObject.Properties["mapCenterOpacity"])   { $CfgObj.homeScreen | Add-Member -NotePropertyName "mapCenterOpacity"   -NotePropertyValue 0 }
        if (-not $CfgObj.homeScreen.PSObject.Properties["fontFamily"])         { $CfgObj.homeScreen | Add-Member -NotePropertyName "fontFamily"         -NotePropertyValue "oem" }
        if (-not $CfgObj.homeScreen.PSObject.Properties["customFontFile"])     { $CfgObj.homeScreen | Add-Member -NotePropertyName "customFontFile"     -NotePropertyValue "" }
        if (-not $CfgObj.homeScreen.PSObject.Properties["applyFontToClimate"]) { $CfgObj.homeScreen | Add-Member -NotePropertyName "applyFontToClimate" -NotePropertyValue $false }
        if (-not $CfgObj.homeScreen.PSObject.Properties["clockOffsetX"])       { $CfgObj.homeScreen | Add-Member -NotePropertyName "clockOffsetX"       -NotePropertyValue 0 }
        if (-not $CfgObj.homeScreen.PSObject.Properties["clockOffsetY"])       { $CfgObj.homeScreen | Add-Member -NotePropertyName "clockOffsetY"       -NotePropertyValue 0 }
        if (-not $CfgObj.homeScreen.PSObject.Properties["clockFontScale"])     { $CfgObj.homeScreen | Add-Member -NotePropertyName "clockFontScale"     -NotePropertyValue 100 }
        if (-not $CfgObj.homeScreen.PSObject.Properties["mediaOffsetX"])       { $CfgObj.homeScreen | Add-Member -NotePropertyName "mediaOffsetX"       -NotePropertyValue 0 }
        if (-not $CfgObj.homeScreen.PSObject.Properties["mediaOffsetY"])       { $CfgObj.homeScreen | Add-Member -NotePropertyName "mediaOffsetY"       -NotePropertyValue 0 }
        if (-not $CfgObj.homeScreen.PSObject.Properties["mediaFontScale"])     { $CfgObj.homeScreen | Add-Member -NotePropertyName "mediaFontScale"     -NotePropertyValue 100 }
    }
    if ($null -ne $CfgObj.batteryWidget) {
        if (-not $CfgObj.batteryWidget.PSObject.Properties["rangeOffsetX"])    { $CfgObj.batteryWidget | Add-Member -NotePropertyName "rangeOffsetX"    -NotePropertyValue 0 }
        if (-not $CfgObj.batteryWidget.PSObject.Properties["rangeOffsetY"])    { $CfgObj.batteryWidget | Add-Member -NotePropertyName "rangeOffsetY"    -NotePropertyValue 0 }
        if (-not $CfgObj.batteryWidget.PSObject.Properties["battTextOffsetX"]) { $CfgObj.batteryWidget | Add-Member -NotePropertyName "battTextOffsetX" -NotePropertyValue 0 }
        if (-not $CfgObj.batteryWidget.PSObject.Properties["battTextOffsetY"]) { $CfgObj.batteryWidget | Add-Member -NotePropertyName "battTextOffsetY" -NotePropertyValue 0 }
    }
    if (-not $CfgObj.PSObject.Properties["statusBar"] -or $null -eq $CfgObj.statusBar) {
        $CfgObj | Add-Member -Force -NotePropertyName "statusBar" -NotePropertyValue ([PSCustomObject]@{
            bgMode = "oem"; customBgFile = ""; bgFit = "cover"; bgScale = 100; bgOffsetX = 0; bgOffsetY = 0;
            bgColor = "#060810"; accentColor = "#3B82F6"; secondaryColor = "#38BDF8"; borderHeight = 4;
            buttonStyle = "oem"; buttonBgColor = "#141C2B"; buttonAccentColor = "#3B82F6"; buttonGlyphColor = "#FFCC66";
            customHomeFile = ""; customBackFile = ""
        })
    }
    if (-not $CfgObj.PSObject.Properties["climateScreen"] -or $null -eq $CfgObj.climateScreen) {
        $CfgObj | Add-Member -Force -NotePropertyName "climateScreen" -NotePropertyValue ([PSCustomObject]@{
            bgMode = "oem"; customBgFile = ""; bgFit = "cover"; bgScale = 100; bgOffsetX = 0; bgOffsetY = 0; bgDim = 0;
            bgColor = "#070A12"; accentColor = "#3B82F6"; secondaryColor = "#38BDF8"; showLcarsFrame = $false;
            bottomBarMode = "oem"; warmerIconStyle = "oem"; heatColor = "#FB923C"; ventColor = "#38BDF8";
            seatStyle = "oem"; seatColor = "#38BDF8"; seatAccentColor = "#3B82F6";
            seatScale = 100; seatOffsetX = 0; seatOffsetY = 0; customDriverSeatFile = ""; customPassengerSeatFile = ""
        })
    } else {
        if (-not $CfgObj.climateScreen.PSObject.Properties["warmerIconStyle"]) { $CfgObj.climateScreen | Add-Member -NotePropertyName "warmerIconStyle" -NotePropertyValue "oem" }
        if (-not $CfgObj.climateScreen.PSObject.Properties["heatColor"])       { $CfgObj.climateScreen | Add-Member -NotePropertyName "heatColor"       -NotePropertyValue "#FB923C" }
        if (-not $CfgObj.climateScreen.PSObject.Properties["ventColor"])       { $CfgObj.climateScreen | Add-Member -NotePropertyName "ventColor"       -NotePropertyValue "#38BDF8" }
    }
    if (-not $CfgObj.PSObject.Properties["evScreen"] -or $null -eq $CfgObj.evScreen) {
        $CfgObj | Add-Member -Force -NotePropertyName "evScreen" -NotePropertyValue ([PSCustomObject]@{
            bgMode = "oem"; customBgFile = ""; bgFit = "cover"; bgScale = 100; bgOffsetX = 0; bgOffsetY = 0; bgDim = 0;
            bgColor = "#060911"; accentColor = "#3B82F6"; secondaryColor = "#38BDF8"; showLcarsFrame = $false;
            carStyle = "oem"; customCarFile = ""; carScale = 100; carOffsetX = 0; carOffsetY = 0;
            cardStyle = "oem"; hideRangeRadar = $false
        })
    }
}

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

Add-Type -ReferencedAssemblies "System.dll", "System.Web.dll" -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;

public class StudioResponseStream : MemoryStream {
    private StudioHttpResponse _resp;
    private bool _sent = false;
    public StudioResponseStream(StudioHttpResponse resp) { _resp = resp; }
    public override void Close() {
        if (!_sent) {
            _sent = true;
            _resp.SendToClient(this.ToArray());
        }
        base.Close();
    }
}

public class StudioHttpRequest {
    public string HttpMethod;
    public Uri Url;
    public NameValueCollection QueryString;
    public Stream InputStream;
}

public class StudioHttpResponse {
    private TcpClient _client;
    private NetworkStream _netStream;
    public int StatusCode = 200;
    public string ContentType = "text/plain; charset=utf-8";
    public long ContentLength64 = 0;
    public Dictionary<string, string> Headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    public StudioResponseStream OutputStream;

    public StudioHttpResponse(TcpClient client, NetworkStream netStream) {
        _client = client;
        _netStream = netStream;
        OutputStream = new StudioResponseStream(this);
    }

    public void AddHeader(string name, string value) {
        Headers[name] = value;
    }

    public void SendToClient(byte[] body) {
        try {
            string statusText = StatusCode == 200 ? "OK" : (StatusCode == 404 ? "Not Found" : "Internal Server Error");
            StringBuilder sb = new StringBuilder();
            sb.AppendFormat("HTTP/1.1 {0} {1}\r\n", StatusCode, statusText);
            sb.AppendFormat("Content-Type: {0}\r\n", ContentType);
            sb.AppendFormat("Content-Length: {0}\r\n", body.Length);
            sb.Append("Access-Control-Allow-Origin: *\r\n");
            sb.Append("Connection: close\r\n");
            foreach (KeyValuePair<string, string> kv in Headers) {
                if (!kv.Key.Equals("Content-Type", StringComparison.OrdinalIgnoreCase) &&
                    !kv.Key.Equals("Content-Length", StringComparison.OrdinalIgnoreCase)) {
                    sb.AppendFormat("{0}: {1}\r\n", kv.Key, kv.Value);
                }
            }
            sb.Append("\r\n");
            byte[] headerBytes = Encoding.UTF8.GetBytes(sb.ToString());
            _netStream.Write(headerBytes, 0, headerBytes.Length);
            if (body.Length > 0) {
                _netStream.Write(body, 0, body.Length);
            }
            _netStream.Flush();
        } catch {
        } finally {
            try { _netStream.Close(); } catch {}
            try { _client.Close(); } catch {}
        }
    }
}

public class StudioHttpContext {
    public StudioHttpRequest Request;
    public StudioHttpResponse Response;
}

public class StudioHttpListener {
    private TcpListener _listener;
    private int _port;
    public bool IsListening = false;

    public StudioHttpListener(int port) {
        _port = port;
        _listener = new TcpListener(IPAddress.Any, port);
    }

    public void Start() {
        _listener.Start();
        IsListening = true;
    }

    public void Stop() {
        IsListening = false;
        try { _listener.Stop(); } catch {}
    }

    public void Close() {
        Stop();
    }

    public StudioHttpContext GetContext() {
        while (IsListening) {
            TcpClient client = _listener.AcceptTcpClient();
            client.ReceiveTimeout = 30000;
            client.SendTimeout = 30000;
            try {
                NetworkStream ns = client.GetStream();
                MemoryStream ms = new MemoryStream();
                byte[] buf = new byte[8192];
                int headerEnd = -1;
                while (headerEnd < 0) {
                    int r = ns.Read(buf, 0, buf.Length);
                    if (r <= 0) break;
                    ms.Write(buf, 0, r);
                    byte[] cur = ms.ToArray();
                    for (int i = 0; i <= cur.Length - 4; i++) {
                        if (cur[i] == 13 && cur[i+1] == 10 && cur[i+2] == 13 && cur[i+3] == 10) {
                            headerEnd = i + 4;
                            break;
                        }
                    }
                    if (cur.Length > 65536) break;
                }
                if (headerEnd < 0) {
                    client.Close();
                    continue;
                }

                byte[] allRead = ms.ToArray();
                string headerStr = Encoding.UTF8.GetString(allRead, 0, headerEnd);
                string[] lines = headerStr.Split(new string[] { "\r\n" }, StringSplitOptions.RemoveEmptyEntries);
                if (lines.Length == 0) {
                    client.Close();
                    continue;
                }

                string[] reqParts = lines[0].Split(' ');
                string method = reqParts.Length > 0 ? reqParts[0].Trim().ToUpperInvariant() : "GET";
                string rawTarget = reqParts.Length > 1 ? reqParts[1].Trim() : "/";

                long contentLen = 0;
                bool expectContinue = false;
                for (int l = 1; l < lines.Length; l++) {
                    int colon = lines[l].IndexOf(':');
                    if (colon > 0) {
                        string hk = lines[l].Substring(0, colon).Trim();
                        string hv = lines[l].Substring(colon + 1).Trim();
                        if (hk.Equals("Content-Length", StringComparison.OrdinalIgnoreCase)) {
                            long.TryParse(hv, out contentLen);
                        } else if (hk.Equals("Expect", StringComparison.OrdinalIgnoreCase) && hv.IndexOf("100-continue", StringComparison.OrdinalIgnoreCase) >= 0) {
                            expectContinue = true;
                        }
                    }
                }

                if (expectContinue) {
                    byte[] cont = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n");
                    ns.Write(cont, 0, cont.Length);
                    ns.Flush();
                }

                MemoryStream bodyStream = new MemoryStream();
                int alreadyBody = allRead.Length - headerEnd;
                if (alreadyBody > 0) {
                    bodyStream.Write(allRead, headerEnd, alreadyBody);
                }
                while (bodyStream.Length < contentLen) {
                    int toRead = (int)Math.Min((long)buf.Length, contentLen - bodyStream.Length);
                    int r = ns.Read(buf, 0, toRead);
                    if (r <= 0) break;
                    bodyStream.Write(buf, 0, r);
                }
                bodyStream.Position = 0;

                Uri uri = new Uri("http://localhost:" + _port + (rawTarget.StartsWith("/") ? rawTarget : "/" + rawTarget));
                NameValueCollection qs = new NameValueCollection();
                string q = uri.Query;
                if (!string.IsNullOrEmpty(q) && q.StartsWith("?")) {
                    string[] pairs = q.Substring(1).Split('&');
                    foreach (string p in pairs) {
                        if (string.IsNullOrEmpty(p)) continue;
                        int eq = p.IndexOf('=');
                        if (eq >= 0) {
                            qs[Uri.UnescapeDataString(p.Substring(0, eq))] = Uri.UnescapeDataString(p.Substring(eq + 1));
                        } else {
                            qs[Uri.UnescapeDataString(p)] = "";
                        }
                    }
                }

                StudioHttpRequest req = new StudioHttpRequest();
                req.HttpMethod = method;
                req.Url = uri;
                req.QueryString = qs;
                req.InputStream = bodyStream;

                StudioHttpResponse resp = new StudioHttpResponse(client, ns);
                StudioHttpContext ctx = new StudioHttpContext();
                ctx.Request = req;
                ctx.Response = resp;
                return ctx;
            } catch {
                try { client.Close(); } catch {}
            }
        }
        throw new InvalidOperationException("Listener stopped");
    }
}
"@

$Url = "http://localhost:$Port/"
$Listener = New-Object StudioHttpListener($Port)
$Listener.Start()

$LanIps = @(
    [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
    Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and -not $_.IPAddressToString.StartsWith("127.") } |
    ForEach-Object { "http://$($_.IPAddressToString):$Port/" }
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Gen5W Theme Studio running at: $Url" -ForegroundColor Green
if ($LanIps.Count -gt 0) {
    Write-Host "  Network / LAN URLs           : $($LanIps -join ', ')" -ForegroundColor Green
}
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
                $cfgObj = Get-Content $actCfg -Raw | ConvertFrom-Json
                Ensure-ThemeConfigDefaults $cfgObj
                Send-Json $Res 200 $cfgObj
            }
            elseif ($Req.HttpMethod -eq "GET" -and $Path.StartsWith("/custom-assets/")) {
                $FileName = [System.IO.Path]::GetFileName($Path)
                $Mime = if ($FileName -match "\.(ttf|otf)$") { "font/ttf" } else { "image/png" }
                $actId = Get-ActiveThemeId
                $ThemeAssetPath = Join-Path $ThemesDir "$actId\assets\$FileName"
                if (Test-Path $ThemeAssetPath) {
                    Send-File $Res $ThemeAssetPath $Mime
                } else {
                    Send-File $Res (Join-Path $CustomDir $FileName) $Mime
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
                Ensure-ThemeConfigDefaults $cfgObj
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

                    # Ensure any newly introduced fields have safe defaults on older imported themes
                    Ensure-ThemeConfigDefaults $ImpCfg

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
                        if ($ze.FullName -match "(^|/)assets/([^/]+\.(png|jpg|jpeg|webp|ttf|otf))$") {
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
                if ($SlotKey -eq "custom_font" -and $DataUrl -match "^data:[^;]*;base64,(.+)$") {
                    $Base64 = $Matches[1]
                    $Bytes = [Convert]::FromBase64String($Base64)
                    $actId = Get-ActiveThemeId
                    $actAssetsDir = Join-Path $ThemesDir "$actId\assets"
                    New-Item -ItemType Directory -Force -Path $actAssetsDir | Out-Null
                    $OutTtf = Join-Path $actAssetsDir "$SlotKey.ttf"
                    [System.IO.File]::WriteAllBytes($OutTtf, $Bytes)
                    Copy-Item $OutTtf (Join-Path $CustomDir "$SlotKey.ttf") -Force
                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Uploaded custom font to theme '$actId': $SlotKey.ttf" -ForegroundColor Cyan
                    Send-Json $Res 200 @{ ok = $true; file = "$SlotKey.ttf" }
                } elseif ($DataUrl -match "^data:image/([a-zA-Z0-9+.-]+);base64,(.+)$") {
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
