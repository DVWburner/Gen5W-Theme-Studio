# Changelog — Gen5W Theme Studio & Safe RAM Launcher Themer

## [v1.1.0] — 2026-11-12

### 🚀 On-Car Auto-Launch on Boot & 5-Layer Failsafe Architecture
- **Optional Auto-Boot on Reboot (`[4. AUTO-BOOT: OFF -> ON ✓]`)**:
  - Once a theme is active and confirmed on the headunit, you can toggle **`[4. AUTO-BOOT]`** inside the on-car **Gen5W Themer** app to cache your confirmed theme APKs into `/data/data/com.gen5w.themer/autostart/`.
  - On subsequent headunit boots, `themer-helper.sh` automatically bind-mounts your cached theme in RAM 15 seconds after Android finishes booting—still with **zero modifications to the `/system` flash partition**.
- **Pinhole Reset Escape Hatch (15s Boot Grace Window + 2-Strike Crash/Reset Watchdog)**:
  - On every startup with Auto-Boot enabled, `themer-helper.sh` immediately increments a persistent `boot_strikes` counter on disk *before* mounting anything, waits a **15-second grace window**, mounts the theme, and monitors `com.android.launcher3` PID stability for **60 continuous seconds** before resetting `boot_strikes = 0`.
  - Pressing the **dashboard pinhole reset button** during startup or within 60 seconds of the theme loading (or if `com.android.launcher3` crashes twice) triggers `boot_strikes >= 2` on the next start, automatically disarming Auto-Boot and booting **100% Factory Stock**.
- **USB "Panic / Safe-Mode" Kill-Switch (`REVERT_THEME.txt`)**:
  - Plugging in any FAT32/exFAT USB stick containing an empty file named **`REVERT_THEME.txt`** (or `SAFE_MODE.txt` / `DISABLE_THEME.txt`) at the root of the drive immediately unmounts all theme overlays, disables Auto-Boot, and restores **100% Factory Stock** within 1–2 seconds—no touchscreen interaction required.

### 🎨 Sub-Menu Theming (`SystemUI`, `HKMC_Climate`, `HKMC_TAppEV3`)
- **4. Top Status Bar (`SystemUI.apk`)**:
  - Customize the global `1920×93` top status bar background (`status_bar_bg.webp`) and top-left Back (`status_back_n/p.webp`), Home (`status_home_n/p.webp`), and Menu (`status_menu_n/p.webp`) buttons across all screens.
- **5. EV Screen (`HKMC_TAppEV3.apk`)**:
  - Full-screen `1920×720` EV Energy Information screen preview (`⚡ EV Screen` toolbar view) and theming (`ev_bg_main.webp`, `ev_bg_bottom_btn_nor/push.9.webp`, `ev_img_car_01.webp`, `ev_img_car_glow.webp`).
  - Toggle to hide the diagonal cyan range radar road slab (`hideRangeRadar`).
- **6. Climate & Floating Seat Warmer/Ventilation (`HKMC_Climate.apk`)**:
  - Dedicated preview modes for both the full-screen **❄️ Climate** screen and the **🔥 Seat Warmer** floating popup (`640×462` modal overlay over the dimmed All-Apps grid).
  - Customize the Climate background (`clm_bg_main.webp`), Floating Warmer popup frame (`co_bg_popup_a.9.webp`), bottom HVAC buttons (`clm_btn_bottom_*`), fan speed pill (`clm_bg_fan.webp`), Seat Warmer/Ventilation & Steering Wheel Warmer icons (`clm_ic_heat_s.webp`, `clm_ic_fan_s.webp`, `clm_ic_sw_heat_nor.webp`), and 3-stage Heat/Cool LED indicator bars (`clm_btn_led_*`).

### 🖖 New 3D/Vector Graphics, Split-Screen Widgets & Fonts
- **Star Trek Shuttlecraft Galileo (`NCC-1701/7`) & Wireframe EV Car**:
  - Added **Shuttlecraft Galileo (`NCC-1701/7`)** (`galileo`) and **Wireframe / Translucent EV Car** (`wireframeCar`) to both **3. Home EV** and **5. EV Screen**, with dynamic battery fill bar and red low-battery warning state.
- **Star Trek Captain's Chair (`captainsChair`)**:
  - Added 3D isometric **Star Trek Captain's Chair** option (pedestal base, angled console armrests with status indicators, and 3-tier backrest) in **6. Climate & Seats**.
- **Home Split-Screen Clock/Date & Media Display Offsets + Fonts**:
  - Added X/Y position sliders and font scaling (`50%–160%`) for both the Home Split-Screen Clock/Date (`widget_digital_clock_small_v3_large.xml`) and Media/Radio display (`widget_av_main_*.xml`).
  - Added Home Screen Font Family selector (`Orbitron`, `Rajdhani`, `Chakra Petch`, `Share Tech Mono`, `Audiowide`, `Michroma`, `Exo 2`, `Oxanium`) + custom `.ttf`/`.otf` font upload (`assets/fonts/CubeN.ttf` and optional `assets/CubeB.ttf` in `HKMC_Climate.apk`).

### 🌐 Studio Server & Quality-of-Life Improvements
- **LAN Access on Port `8470`**:
  - Replaced `HttpListener` host-header binding with a custom `TcpListener(IPAddress.Any, 8470)` HTTP server in `scripts/start-theme-studio.ps1` so accessing the Studio from other machines on your local network (`http://<LAN-IP>:8470/`) works without `Bad Request - Invalid Hostname`.
- **Silent GitHub Update Indicator**:
  - Checks `DVWburner/Gen5W-Theme-Studio/releases/latest` on startup and displays a non-intrusive **`⬆ Update`** badge in the header only when a newer release is available (fails silently offline).
- **Backward-Compatible `.gen5wtheme` Import/Export**:
  - Existing v1.0.0 `.gen5wtheme` files import seamlessly with automatic default population for all new v1.1.0 sub-menu and font settings.

---

## [v1.0.0] — 2026-11-12
- Initial public release of **Gen5W Theme Studio** & **Gen5W Themer** with zero-OEM asset distribution, runtime on-car stock asset compositing, 45-second deadman rollback timer, multi-theme APK bundling, and `.gen5wtheme` sharing.
