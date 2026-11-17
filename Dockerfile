FROM mcr.microsoft.com/powershell:ubuntu-24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip libgdiplus webp zipalign \
    fonts-liberation fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# shortcut: the existing GDI+ renderer needs Drawing 6's Unix implementation;
# replace this compatibility assembly when the renderer moves to a portable API.
RUN curl -fsSL https://api.nuget.org/v3-flatcontainer/system.drawing.common/6.0.0/system.drawing.common.6.0.0.nupkg -o /tmp/drawing.zip \
    && unzip -p /tmp/drawing.zip runtimes/unix/lib/net6.0/System.Drawing.Common.dll > /opt/microsoft/powershell/7/System.Drawing.Common.dll \
    && rm /tmp/drawing.zip

RUN pwsh -NoProfile -Command '$p = "/opt/microsoft/powershell/7/pwsh.runtimeconfig.json"; $c = Get-Content $p -Raw | ConvertFrom-Json; $c.runtimeOptions.configProperties | Add-Member -NotePropertyName System.Drawing.EnableUnixSupport -NotePropertyValue $true; $c | ConvertTo-Json -Depth 10 | Set-Content $p'

WORKDIR /workspace
ENTRYPOINT ["pwsh", "-NoProfile", "-File", "scripts/start-theme-studio.ps1", "-NoBrowser"]
