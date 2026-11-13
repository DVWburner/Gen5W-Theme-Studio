package com.gen5w.themer;

import android.app.Activity;
import android.content.Intent;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.widget.Button;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FilterOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.zip.CRC32;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

public class MainActivity extends Activity {

    private static final String NEMESIS_BIN = "/system/xbin/nemesis";
    private static final String HELPER_SVC = "gen5w.nemesis.themer/themer-helper";
    private static final String HELPER_SH = "/data/nemesis/apps/gen5w.nemesis.themer/svc/themer-helper.sh";

    private static final String WORK_DIR = "/mnt/asec/gen5w_themer";
    private static final String CMD_FILE = WORK_DIR + "/cmd";
    private static final String STATUS_FILE = WORK_DIR + "/status";
    private static final String COUNTDOWN_FILE = WORK_DIR + "/countdown";
    private static final String ACTIVE_FILE = WORK_DIR + "/active_state";
    private static final String ACTIVE_THEME_NAME_FILE = WORK_DIR + "/active_theme_name";
    private static final String AUTOSTART_STATE_FILE = WORK_DIR + "/autostart_state";
    private static final String LOG_FILE = WORK_DIR + "/helper.log";
    private static final String PERSIST_DIR = "/data/data/com.gen5w.themer/autostart";
    private static final String AUTOSTART_ENABLED_FILE = PERSIST_DIR + "/enabled";
    private static final String AUTOSTART_STRIKES_FILE = PERSIST_DIR + "/boot_strikes";
    private static final String AUTOSTART_THEME_FILE = PERSIST_DIR + "/theme_name";
    private static final String THEMED_APK = WORK_DIR + "/Launcher_WP3_themed.apk";
    private static final String STOCK_APK = WORK_DIR + "/Launcher_WP3_stock.apk";
    private static final String TARGET_APK = "/system/app/Launcher_WP3.apk";

    private static final String THEMED_SYSUI = WORK_DIR + "/SystemUI_themed.apk";
    private static final String STOCK_SYSUI = WORK_DIR + "/SystemUI_stock.apk";
    private static final String TARGET_SYSUI = "/system/priv-app/SystemUI.apk";

    private static final String THEMED_CLIMATE = WORK_DIR + "/HKMC_Climate_themed.apk";
    private static final String STOCK_CLIMATE = WORK_DIR + "/HKMC_Climate_stock.apk";
    private static final String TARGET_CLIMATE = "/system/app/HKMC_Climate.apk";

    private static final String THEMED_EV = WORK_DIR + "/HKMC_TAppEV3_themed.apk";
    private static final String STOCK_EV = WORK_DIR + "/HKMC_TAppEV3_stock.apk";
    private static final String TARGET_EV = "/system/app/HKMC_TAppEV3.apk";

    private TextView statusBanner;
    private TextView countdownBanner;
    private TextView titleView;
    private TextView logView;
    private ScrollView logScroll;
    private Button applyLcarsBtn;
    private Button confirmKeepBtn;
    private Button revertStockBtn;
    private Button autoBootBtn;
    private Button scanBtn;

    private static class ThemeEntry {
        final String slug;
        final String name;
        Button pillBtn;

        ThemeEntry(String slug, String name) {
            this.slug = slug;
            this.name = name;
        }
    }

    private final List<ThemeEntry> bundledThemes = new ArrayList<ThemeEntry>();
    private String selectedThemeSlug = "lcars";
    private String bundledThemeName = "Custom Theme";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private volatile boolean isBusy = false;
    private boolean pollActive = false;

    private final Runnable statusPoller = new Runnable() {
        @Override
        public void run() {
            updateLiveStatusBanner();
            if (pollActive) {
                mainHandler.postDelayed(this, 1000);
            }
        }
    };

    private static class CountingOutputStream extends FilterOutputStream {
        private long count = 0;

        public CountingOutputStream(OutputStream out) {
            super(out);
        }

        @Override
        public void write(int b) throws IOException {
            out.write(b);
            count++;
        }

        @Override
        public void write(byte[] b, int off, int len) throws IOException {
            out.write(b, off, len);
            count += len;
        }

        public long getCount() {
            return count;
        }
    }

    private static class CmdResult {
        final int rc;
        final String out;

        CmdResult(int rc, String out) {
            this.rc = rc;
            this.out = out != null ? out : "";
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        loadBundledThemesList();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0B0F17"));
        root.setPadding(24, 14, 24, 14);

        // Top Header Bar
        LinearLayout headerRow = new LinearLayout(this);
        headerRow.setOrientation(LinearLayout.HORIZONTAL);
        headerRow.setGravity(Gravity.CENTER_VERTICAL);
        headerRow.setPadding(0, 0, 0, 8);

        TextView pillBadge = new TextView(this);
        pillBadge.setText(" GEN5W THEMER ");
        pillBadge.setTextSize(TypedValue.COMPLEX_UNIT_PX, 21);
        pillBadge.setTypeface(Typeface.DEFAULT_BOLD);
        pillBadge.setTextColor(Color.parseColor("#050811"));
        GradientDrawable pillBg = new GradientDrawable();
        pillBg.setColor(Color.parseColor("#38BDF8"));
        pillBg.setCornerRadius(16f);
        pillBadge.setBackground(pillBg);
        pillBadge.setPadding(16, 7, 16, 7);
        headerRow.addView(pillBadge);

        titleView = new TextView(this);
        titleView.setText("  OEM LAUNCHER THEME MANAGER  (" + bundledThemes.size() + " THEME" + (bundledThemes.size() == 1 ? "" : "S") + " BUNDLED)");
        titleView.setTextSize(TypedValue.COMPLEX_UNIT_PX, 23);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setTextColor(Color.parseColor("#E2E8F0"));
        LinearLayout.LayoutParams titleLp = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        headerRow.addView(titleView, titleLp);

        statusBanner = new TextView(this);
        statusBanner.setText("STATUS: CHECKING...");
        statusBanner.setTextSize(TypedValue.COMPLEX_UNIT_PX, 19);
        statusBanner.setTypeface(Typeface.DEFAULT_BOLD);
        statusBanner.setTextColor(Color.parseColor("#38BDF8"));
        statusBanner.setPadding(0, 0, 18, 0);
        headerRow.addView(statusBanner);

        Button exitBtn = new Button(this);
        exitBtn.setText("✕ EXIT TO HOME");
        exitBtn.setTextSize(TypedValue.COMPLEX_UNIT_PX, 18);
        exitBtn.setTypeface(Typeface.DEFAULT_BOLD);
        exitBtn.setTextColor(Color.parseColor("#FFFFFF"));
        exitBtn.setPadding(20, 8, 20, 8);
        GradientDrawable exitBg = new GradientDrawable();
        exitBg.setColor(Color.parseColor("#334155"));
        exitBg.setStroke(2, Color.parseColor("#EF4444"));
        exitBg.setCornerRadius(14f);
        exitBtn.setBackground(exitBg);
        exitBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                try {
                    Intent homeIntent = new Intent(Intent.ACTION_MAIN);
                    homeIntent.addCategory(Intent.CATEGORY_HOME);
                    homeIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(homeIntent);
                } catch (Exception ignored) {
                }
                finish();
            }
        });
        headerRow.addView(exitBtn);

        root.addView(headerRow);

        // Prominent Countdown / Safety Banner
        countdownBanner = new TextView(this);
        countdownBanner.setText("SAFETY GUARANTEE: Theme mounts in RAM (/mnt/asec) only when clicked. Reboot or pinhole reset ALWAYS reverts 100% to factory stock.");
        countdownBanner.setTextSize(TypedValue.COMPLEX_UNIT_PX, 19);
        countdownBanner.setTypeface(Typeface.DEFAULT_BOLD);
        countdownBanner.setTextColor(Color.parseColor("#050811"));
        countdownBanner.setGravity(Gravity.CENTER_VERTICAL);
        countdownBanner.setPadding(18, 10, 18, 10);
        GradientDrawable bannerBg = new GradientDrawable();
        bannerBg.setColor(Color.parseColor("#38BDF8"));
        bannerBg.setCornerRadius(12f);
        countdownBanner.setBackground(bannerBg);
        LinearLayout.LayoutParams bannerLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        bannerLp.setMargins(0, 0, 0, 10);
        root.addView(countdownBanner, bannerLp);

        // Multi-Theme Picker Row
        LinearLayout pickerBar = new LinearLayout(this);
        pickerBar.setOrientation(LinearLayout.HORIZONTAL);
        pickerBar.setGravity(Gravity.CENTER_VERTICAL);
        pickerBar.setPadding(14, 8, 14, 8);
        GradientDrawable pickerBarBg = new GradientDrawable();
        pickerBarBg.setColor(Color.parseColor("#131B2A"));
        pickerBarBg.setStroke(2, Color.parseColor("#2A364B"));
        pickerBarBg.setCornerRadius(14f);
        pickerBar.setBackground(pickerBarBg);

        TextView pickerLabel = new TextView(this);
        pickerLabel.setText("SELECT THEME:  ");
        pickerLabel.setTextSize(TypedValue.COMPLEX_UNIT_PX, 18);
        pickerLabel.setTypeface(Typeface.DEFAULT_BOLD);
        pickerLabel.setTextColor(Color.parseColor("#94A3B8"));
        pickerBar.addView(pickerLabel);

        HorizontalScrollView themeScroll = new HorizontalScrollView(this);
        themeScroll.setHorizontalScrollBarEnabled(false);
        LinearLayout themePillsRow = new LinearLayout(this);
        themePillsRow.setOrientation(LinearLayout.HORIZONTAL);
        themePillsRow.setGravity(Gravity.CENTER_VERTICAL);

        for (int i = 0; i < bundledThemes.size(); i++) {
            final ThemeEntry te = bundledThemes.get(i);
            Button pBtn = new Button(this);
            pBtn.setText(te.name);
            pBtn.setTextSize(TypedValue.COMPLEX_UNIT_PX, 18);
            pBtn.setTypeface(Typeface.DEFAULT_BOLD);
            pBtn.setPadding(22, 8, 22, 8);
            pBtn.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    selectThemeEntry(te, true);
                }
            });
            te.pillBtn = pBtn;
            LinearLayout.LayoutParams pLp = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            pLp.setMargins(0, 0, 10, 0);
            themePillsRow.addView(pBtn, pLp);
        }
        themeScroll.addView(themePillsRow);
        LinearLayout.LayoutParams tsLp = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        pickerBar.addView(themeScroll, tsLp);

        LinearLayout.LayoutParams pickerLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        pickerLp.setMargins(0, 0, 0, 10);
        root.addView(pickerBar, pickerLp);

        // Action Buttons Row
        LinearLayout btnRow = new LinearLayout(this);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setPadding(0, 0, 0, 10);

        applyLcarsBtn = createActionButton(
                "1. TEST '" + bundledThemeName.toUpperCase() + "'\n(45s Safe Rollback Timer)",
                "#38BDF8", "#050811");
        applyLcarsBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                applyLcarsThemeAsync(false);
            }
        });

        confirmKeepBtn = createActionButton(
                "2. APPLY & KEEP '" + bundledThemeName.toUpperCase() + "'\n(Confirm or Skip 45s Timer)",
                "#10B981", "#050811");
        confirmKeepBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                onConfirmOrApplyDirectClicked();
            }
        });

        revertStockBtn = createActionButton(
                "3. REVERT TO STOCK NOW\n(Instant OEM Restore)",
                "#EF4444", "#FFFFFF");
        revertStockBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                executeThemeActionAsync("REVERT_STOCK", "DIRECT_REVERT");
            }
        });

        autoBootBtn = createActionButton(
                "4. AUTO-BOOT: OFF\n(Tap After Confirming Theme)",
                "#334155", "#E2E8F0");
        autoBootBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                onAutoBootToggleClicked();
            }
        });

        scanBtn = createActionButton(
                "5. DIAGNOSTICS & LOGS\n(Inspect Mounts & Helper)",
                "#6366F1", "#FFFFFF");
        scanBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                runDiagnosticsAsync();
            }
        });

        LinearLayout.LayoutParams btnLp = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        btnLp.setMargins(0, 0, 10, 0);
        btnRow.addView(applyLcarsBtn, btnLp);
        btnRow.addView(confirmKeepBtn, btnLp);
        btnRow.addView(revertStockBtn, btnLp);
        btnRow.addView(autoBootBtn, btnLp);

        LinearLayout.LayoutParams lastBtnLp = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 0.85f);
        btnRow.addView(scanBtn, lastBtnLp);

        root.addView(btnRow);

        // Console Output Scroll Area
        logScroll = new ScrollView(this);
        GradientDrawable logBg = new GradientDrawable();
        logBg.setColor(Color.parseColor("#111722"));
        logBg.setStroke(2, Color.parseColor("#2A364B"));
        logBg.setCornerRadius(14f);
        logScroll.setBackground(logBg);
        logScroll.setPadding(20, 16, 20, 16);

        logView = new TextView(this);
        logView.setTypeface(Typeface.MONOSPACE);
        logView.setTextSize(TypedValue.COMPLEX_UNIT_PX, 19);
        logView.setTextColor(Color.parseColor("#E2F1FF"));
        logScroll.addView(logView);

        LinearLayout.LayoutParams scrollLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f);
        root.addView(logScroll, scrollLp);

        setContentView(root);
        if (!bundledThemes.isEmpty()) {
            selectThemeEntry(bundledThemes.get(0), false);
        }

        appendLog("==========================================================================");
        appendLog(" GEN5W OEM LAUNCHER THEME MANAGER v1.1.0 // " + bundledThemes.size() + " THEME(S) IN PACK");
        appendLog("==========================================================================");
        appendLog(" - Selected Theme: " + bundledThemeName + " (tap any theme button above to switch)");
        appendLog(" - Theme Storage: Built on-device in RAM (" + WORK_DIR + ") - NO USB stick needed!");
        appendLog(" - Auto-Boot on Reboot: Optional toggle with 5-Layer Failsafe (Pinhole 2-Strike + USB REVERT_THEME.txt)");
        appendLog("==========================================================================\n");
    }

    @Override
    protected void onResume() {
        super.onResume();
        pollActive = true;
        mainHandler.removeCallbacks(statusPoller);
        mainHandler.post(statusPoller);
    }

    @Override
    protected void onPause() {
        super.onPause();
        pollActive = false;
        mainHandler.removeCallbacks(statusPoller);
    }

    private void loadBundledThemesList() {
        bundledThemes.clear();
        AssetManager am = getAssets();
        InputStream in = null;
        try {
            in = am.open("themes/themes-index.txt");
            BufferedReader br = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            String line;
            while ((line = br.readLine()) != null) {
                String trimmed = line.trim();
                if (!trimmed.isEmpty()) {
                    int pipeIdx = trimmed.indexOf('|');
                    if (pipeIdx > 0) {
                        String slug = trimmed.substring(0, pipeIdx).trim();
                        String name = trimmed.substring(pipeIdx + 1).trim();
                        if (!slug.isEmpty()) {
                            bundledThemes.add(new ThemeEntry(slug, name.isEmpty() ? slug : name));
                        }
                    }
                }
            }
            br.close();
        } catch (Exception ignored) {
        } finally {
            if (in != null) {
                try { in.close(); } catch (Exception ignored) {}
            }
        }

        if (bundledThemes.isEmpty()) {
            try {
                String[] dirs = am.list("themes");
                if (dirs != null) {
                    for (int i = 0; i < dirs.length; i++) {
                        String sub = dirs[i];
                        if (sub == null || sub.isEmpty() || sub.endsWith(".txt")) continue;
                        String tName = readAssetFirstLine("themes/" + sub + "/theme-name.txt");
                        if (tName == null || tName.isEmpty()) tName = sub;
                        bundledThemes.add(new ThemeEntry(sub, tName));
                    }
                }
            } catch (Exception ignored) {
            }
        }

        if (bundledThemes.isEmpty()) {
            String fallbackName = readAssetFirstLine("themes/lcars/theme-name.txt");
            if (fallbackName == null || fallbackName.isEmpty()) fallbackName = "Custom Theme";
            bundledThemes.add(new ThemeEntry("lcars", fallbackName));
        }

        selectedThemeSlug = bundledThemes.get(0).slug;
        bundledThemeName = bundledThemes.get(0).name;
    }

    private void selectThemeEntry(ThemeEntry chosen, boolean logSelection) {
        selectedThemeSlug = chosen.slug;
        bundledThemeName = chosen.name;
        for (int i = 0; i < bundledThemes.size(); i++) {
            ThemeEntry te = bundledThemes.get(i);
            if (te.pillBtn == null) continue;
            boolean isSel = te.slug.equals(selectedThemeSlug);
            GradientDrawable bg = new GradientDrawable();
            if (isSel) {
                bg.setColor(Color.parseColor("#38BDF8"));
                bg.setStroke(2, Color.parseColor("#E0F2FE"));
                te.pillBtn.setTextColor(Color.parseColor("#050811"));
                te.pillBtn.setText("✓ " + te.name);
            } else {
                bg.setColor(Color.parseColor("#1E293B"));
                bg.setStroke(2, Color.parseColor("#334155"));
                te.pillBtn.setTextColor(Color.parseColor("#E2E8F0"));
                te.pillBtn.setText(te.name);
            }
            bg.setCornerRadius(12f);
            te.pillBtn.setBackground(bg);
        }
        if (applyLcarsBtn != null) {
            applyLcarsBtn.setText("1. TEST '" + bundledThemeName.toUpperCase() + "'\n(45s Safe Rollback Timer)");
        }
        if (confirmKeepBtn != null) {
            confirmKeepBtn.setText("2. APPLY & KEEP '" + bundledThemeName.toUpperCase() + "'\n(Confirm or Skip 45s Timer)");
        }
        if (logSelection) {
            appendLog("Selected theme to apply: '" + bundledThemeName + "' (pack: themes/" + selectedThemeSlug + ")");
        }
        updateLiveStatusBanner();
    }

    private String readAssetFirstLine(String assetPath) {
        InputStream in = null;
        try {
            in = getAssets().open(assetPath);
            BufferedReader br = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            String line = br.readLine();
            br.close();
            if (line != null && !line.trim().isEmpty()) {
                return line.trim();
            }
        } catch (Exception ignored) {
        } finally {
            if (in != null) {
                try { in.close(); } catch (Exception ignored) {}
            }
        }
        return "";
    }

    private Button createActionButton(String text, String bgHex, String fgHex) {
        Button btn = new Button(this);
        btn.setText(text);
        btn.setTextSize(TypedValue.COMPLEX_UNIT_PX, 20);
        btn.setTypeface(Typeface.DEFAULT_BOLD);
        btn.setTextColor(Color.parseColor(fgHex));
        btn.setPadding(16, 18, 16, 18);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor(bgHex));
        bg.setCornerRadius(18f);
        btn.setBackground(bg);
        return btn;
    }

    private void setBannerStyle(String text, String bgHex, String fgHex) {
        countdownBanner.setText(text);
        countdownBanner.setTextColor(Color.parseColor(fgHex));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor(bgHex));
        bg.setCornerRadius(12f);
        countdownBanner.setBackground(bg);
    }

    private boolean isAutoBootCurrentlyEnabled() {
        String state = readFirstLine(new File(AUTOSTART_STATE_FILE));
        if (state != null && state.startsWith("ENABLED")) {
            return true;
        }
        String en = readFirstLine(new File(AUTOSTART_ENABLED_FILE));
        return "1".equals(en);
    }

    private void updateAutoBootButtonStyle(boolean themed, int remaining, String activeThemeOnCar) {
        if (autoBootBtn == null) return;
        String autoState = readFirstLine(new File(AUTOSTART_STATE_FILE));
        boolean enabled = isAutoBootCurrentlyEnabled();
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(18f);

        if (enabled) {
            String bootTheme = activeThemeOnCar;
            if (autoState != null && autoState.startsWith("ENABLED|") && autoState.length() > 8) {
                bootTheme = autoState.substring(8).trim();
            } else {
                String persistedTheme = readFirstLine(new File(AUTOSTART_THEME_FILE));
                if (persistedTheme != null && !persistedTheme.isEmpty()) {
                    bootTheme = persistedTheme;
                }
            }
            bg.setColor(Color.parseColor("#F59E0B"));
            bg.setStroke(2, Color.parseColor("#FEF3C7"));
            autoBootBtn.setTextColor(Color.parseColor("#050811"));
            autoBootBtn.setText("4. AUTO-BOOT: ON ✓\n('" + bootTheme + "' - Tap to Disable)");
        } else if (autoState != null && autoState.startsWith("TRIPPED")) {
            String reason = "Failsafe Tripped";
            int bar = autoState.indexOf('|');
            if (bar > 0 && bar + 1 < autoState.length()) {
                reason = autoState.substring(bar + 1).trim();
            }
            bg.setColor(Color.parseColor("#F97316"));
            bg.setStroke(2, Color.parseColor("#FFEDD5"));
            autoBootBtn.setTextColor(Color.parseColor("#050811"));
            autoBootBtn.setText("4. AUTO-BOOT: TRIPPED!\n(" + reason + ")");
        } else if (themed && remaining == 0) {
            bg.setColor(Color.parseColor("#1E293B"));
            bg.setStroke(2, Color.parseColor("#38BDF8"));
            autoBootBtn.setTextColor(Color.parseColor("#38BDF8"));
            autoBootBtn.setText("4. AUTO-BOOT: OFF\n(Tap to Auto-Launch '" + activeThemeOnCar + "')");
        } else {
            bg.setColor(Color.parseColor("#334155"));
            bg.setStroke(2, Color.parseColor("#475569"));
            autoBootBtn.setTextColor(Color.parseColor("#CBD5E1"));
            autoBootBtn.setText("4. AUTO-BOOT: OFF\n(Confirm Theme First to Enable)");
        }
        autoBootBtn.setBackground(bg);
    }

    private void onAutoBootToggleClicked() {
        if (isAutoBootCurrentlyEnabled()) {
            appendLog("Disabling Auto-Boot on Reboot...");
            executeThemeActionAsync("DISABLE_AUTOSTART", "DIRECT_DISABLE_AUTOSTART");
            return;
        }
        String countText = readFirstLine(new File(COUNTDOWN_FILE));
        int remaining = 0;
        if (countText != null) {
            try {
                remaining = Integer.parseInt(countText.trim());
            } catch (Exception ignored) {
            }
        }
        if (!isLauncherCurrentlyThemed() || remaining > 0) {
            appendLog("SAFEGUARD: Please apply & confirm your theme first ([1. TEST] -> [2. CONFIRM] or [2. APPLY & KEEP]) before enabling Auto-Boot on Reboot.");
            setBannerStyle(
                    "CONFIRM THEME FIRST: Apply & Confirm your theme before arming Auto-Boot on Reboot!",
                    "#F59E0B",
                    "#050811");
            return;
        }
        appendLog("Arming Auto-Boot on Reboot for confirmed theme (with Pinhole 2-Strike & USB REVERT_THEME.txt failsafes)...");
        executeThemeActionAsync("ENABLE_AUTOSTART", "DIRECT_ENABLE_AUTOSTART");
    }

    private void updateLiveStatusBanner() {
        boolean themed = isLauncherCurrentlyThemed();
        boolean autoBootOn = isAutoBootCurrentlyEnabled();
        String statusText = readFirstLine(new File(STATUS_FILE));
        String countText = readFirstLine(new File(COUNTDOWN_FILE));
        String activeThemeOnCar = readFirstLine(new File(ACTIVE_THEME_NAME_FILE));
        if (activeThemeOnCar == null || activeThemeOnCar.isEmpty()) {
            activeThemeOnCar = bundledThemeName;
        }

        int remaining = 0;
        if (countText != null) {
            try {
                remaining = Integer.parseInt(countText.trim());
            } catch (Exception ignored) {
            }
        }

        updateAutoBootButtonStyle(themed, remaining, activeThemeOnCar);

        if (remaining > 0) {
            statusBanner.setText("STATUS: TESTING (" + remaining + "s)");
            statusBanner.setTextColor(Color.parseColor("#FFCC00"));
            setBannerStyle(
                    "DEADMAN TIMER ACTIVE: " + remaining + " SECONDS REMAINING! Tap [2. CONFIRM & KEEP THEME] now to keep '" + activeThemeOnCar + "' active!",
                    (remaining % 2 == 0) ? "#FFD600" : "#FF9100",
                    "#000000");
        } else if (themed) {
            statusBanner.setText(autoBootOn ? "STATUS: ACTIVE + AUTO-BOOT ON" : "STATUS: THEME ACTIVE");
            statusBanner.setTextColor(Color.parseColor("#10B981"));
            String autoMsg = autoBootOn
                    ? "AUTO-BOOT ON (Failsafes: Pinhole Reset x2 or USB 'REVERT_THEME.txt'). Tap [4. AUTO-BOOT] to disable or [3. REVERT TO STOCK]."
                    : "Tap [4. AUTO-BOOT: OFF] to auto-launch across reboots, or [3. REVERT TO STOCK].";
            setBannerStyle(
                    "CUSTOM THEME ACTIVE ('" + activeThemeOnCar + "' confirmed). " + autoMsg,
                    "#10B981",
                    "#000000");
        } else {
            statusBanner.setText("STATUS: FACTORY STOCK");
            statusBanner.setTextColor(Color.parseColor("#38BDF8"));
            String msg = (statusText != null && !statusText.isEmpty())
                    ? "CURRENT STATE: " + statusText + "  |  Select a theme below and tap [1. TEST] or [2. APPLY & KEEP]."
                    : "CURRENT STATE: STOCK (Unmodified)  |  Select a theme below and tap [1. TEST] or [2. APPLY & KEEP].";
            setBannerStyle(msg, "#38BDF8", "#050811");
        }
    }

    private boolean isLauncherCurrentlyThemed() {
        if (!isLauncherBindMounted()) return false;
        String activeState = readFirstLine(new File(ACTIVE_FILE));
        return !"STOCK".equalsIgnoreCase(activeState);
    }

    private boolean isLauncherBindMounted() {
        return isTargetBindMounted(TARGET_APK);
    }

    private boolean isTargetBindMounted(String targetPath) {
        File mounts = new File("/proc/mounts");
        if (!mounts.exists()) return false;
        BufferedReader br = null;
        try {
            br = new BufferedReader(new InputStreamReader(new FileInputStream(mounts)));
            String line;
            while ((line = br.readLine()) != null) {
                if (line.contains(targetPath)) {
                    return true;
                }
            }
        } catch (Exception ignored) {
        } finally {
            if (br != null) {
                try { br.close(); } catch (Exception ignored) {}
            }
        }
        return false;
    }

    private CmdResult execNemesis(String... args) {
        try {
            String[] cmd = new String[args.length + 1];
            cmd[0] = NEMESIS_BIN;
            System.arraycopy(args, 0, cmd, 1, args.length);
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            InputStream in = p.getInputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            in.close();
            int rc = p.waitFor();
            return new CmdResult(rc, bos.toString("UTF-8").trim());
        } catch (Exception e) {
            return new CmdResult(-1, "ERR: " + e.toString());
        }
    }

    private void onConfirmOrApplyDirectClicked() {
        String countText = readFirstLine(new File(COUNTDOWN_FILE));
        int remaining = 0;
        if (countText != null) {
            try {
                remaining = Integer.parseInt(countText.trim());
            } catch (Exception ignored) {
            }
        }
        String activeThemeOnCar = readFirstLine(new File(ACTIVE_THEME_NAME_FILE));
        if (remaining > 0 && isLauncherCurrentlyThemed() && bundledThemeName.equals(activeThemeOnCar)) {
            executeThemeActionAsync("CONFIRM_KEEP", "DIRECT_CONFIRM");
        } else {
            applyLcarsThemeAsync(true);
        }
    }

    private void applyLcarsThemeAsync(final boolean skipCountdown) {
        if (isBusy) return;
        isBusy = true;
        applyLcarsBtn.setEnabled(false);
        confirmKeepBtn.setEnabled(false);
        final String targetSlug = selectedThemeSlug;
        final String targetName = bundledThemeName;

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    long t0 = System.currentTimeMillis();
                    appendLog("\n>>> [STEP 1/3] Building Custom Launcher APK ('" + targetName + "') in RAM (" + THEMED_APK + ")...");

                    File workDir = new File(WORK_DIR);
                    if (!workDir.exists()) {
                        workDir.mkdirs();
                    }
                    workDir.setReadable(true, false);
                    workDir.setWritable(true, false);
                    workDir.setExecutable(true, false);

                    File stockApk = new File(TARGET_APK);
                    if (!stockApk.exists()) {
                        appendLog("ERROR: Stock launcher not found at " + TARGET_APK);
                        return;
                    }

                    File cleanStockBackup = new File(STOCK_APK);
                    if (!cleanStockBackup.exists() && !isLauncherBindMounted()) {
                        appendLog("Saving clean RAM reference copy of stock Launcher_WP3.apk...");
                        copyFile(stockApk, cleanStockBackup);
                        cleanStockBackup.setReadable(true, false);
                    }
                    File sourceApk = cleanStockBackup.exists() ? cleanStockBackup : stockApk;

                    File outApkTmp = new File(WORK_DIR, "Launcher_WP3_themed.apk.tmp");
                    int replacedCount = buildThemedLauncherApk(sourceApk, outApkTmp, "themes/" + targetSlug);

                    File outApk = new File(THEMED_APK);
                    if (outApk.exists()) {
                        outApk.delete();
                    }
                    if (!outApkTmp.renameTo(outApk)) {
                        copyFile(outApkTmp, outApk);
                        outApkTmp.delete();
                    }
                    outApk.setReadable(true, false);

                    try {
                        File nameFile = new File(ACTIVE_THEME_NAME_FILE);
                        FileOutputStream nFos = new FileOutputStream(nameFile);
                        nFos.write((targetName + "\n").getBytes("UTF-8"));
                        nFos.flush();
                        nFos.close();
                        nameFile.setReadable(true, false);
                    } catch (Exception ignored) {
                    }

                    long elapsed = System.currentTimeMillis() - t0;
                    appendLog("SUCCESS: Patched " + replacedCount + " Launcher resources into "
                            + outApk.getAbsolutePath() + " (" + (outApk.length() / 1024) + " KB) in " + elapsed + " ms.");

                    // Optional Sub-APKs: Status Bar (SystemUI), Climate & Warmer (HKMC_Climate), EV Screen (HKMC_TAppEV3)
                    stageOptionalSubApk("Status Bar (SystemUI)", TARGET_SYSUI, STOCK_SYSUI, THEMED_SYSUI, "themes/" + targetSlug + "/systemui");
                    stageOptionalSubApk("Climate & Warmer (HKMC_Climate)", TARGET_CLIMATE, STOCK_CLIMATE, THEMED_CLIMATE, "themes/" + targetSlug + "/climate");
                    stageOptionalSubApk("EV Screen (HKMC_TAppEV3)", TARGET_EV, STOCK_EV, THEMED_EV, "themes/" + targetSlug + "/ev");

                    appendLog(">>> [STEP 2/3] Ensuring Root Helper Service is active...");
                    CmdResult svcRes = execNemesis("service", "start", HELPER_SVC);
                    appendLog("nemesis service start rc=" + svcRes.rc + (svcRes.out.isEmpty() ? "" : (" (" + svcRes.out + ")")));

                    if (skipCountdown) {
                        appendLog(">>> [STEP 3/3] Mounting Custom Theme Directly in CONFIRMED Mode (skipping 45s timer)...");
                        CmdResult applyRes = execNemesis("root", "-c", "sh " + HELPER_SH + " DIRECT_APPLY_CONFIRMED");
                        appendLog("DIRECT_APPLY_CONFIRMED rc=" + applyRes.rc + (applyRes.out.isEmpty() ? "" : ("\n" + applyRes.out)));
                        if (!isLauncherCurrentlyThemed()) {
                            writeHelperCommandFile("APPLY_CONFIRMED");
                            Thread.sleep(1200);
                        }
                    } else {
                        appendLog(">>> [STEP 3/3] Mounting Custom Theme in RAM & starting 45s Deadman Timer...");
                        CmdResult applyRes = execNemesis("root", "-c", "sh " + HELPER_SH + " DIRECT_APPLY");
                        appendLog("DIRECT_APPLY rc=" + applyRes.rc + (applyRes.out.isEmpty() ? "" : ("\n" + applyRes.out)));
                        if (!isLauncherCurrentlyThemed()) {
                            writeHelperCommandFile("APPLY_TEST");
                            Thread.sleep(1200);
                        }
                    }

                    String logTail = readFileText(new File(LOG_FILE), 2000);
                    if (!logTail.isEmpty()) {
                        appendLog("--- Helper Log ---\n" + logTail.trim());
                    }
                } catch (Throwable t) {
                    appendLog("ERROR building/applying theme: " + t.toString());
                    for (StackTraceElement el : t.getStackTrace()) {
                        appendLog("  at " + el.toString());
                    }
                } finally {
                    isBusy = false;
                    mainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            applyLcarsBtn.setEnabled(true);
                            confirmKeepBtn.setEnabled(true);
                            updateLiveStatusBanner();
                        }
                    });
                }
            }
        }).start();
    }

    private void executeThemeActionAsync(final String daemonCmd, final String directArg) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    appendLog("\n>>> Executing action: " + daemonCmd + "...");
                    writeHelperCommandFile(daemonCmd);
                    CmdResult res = execNemesis("root", "-c", "sh " + HELPER_SH + " " + directArg);
                    appendLog(directArg + " rc=" + res.rc + (res.out.isEmpty() ? "" : (" (" + res.out + ")")));
                    String logTail = readFileText(new File(LOG_FILE), 1800);
                    if (!logTail.isEmpty()) {
                        appendLog("--- Helper Log ---\n" + logTail.trim());
                    }
                    mainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            updateLiveStatusBanner();
                        }
                    });
                } catch (Exception e) {
                    appendLog("ERROR executing " + daemonCmd + ": " + e.toString());
                }
            }
        }).start();
    }

    private int buildThemedLauncherApk(File sourceApk, File destApk, String assetThemePrefix) throws Exception {
        AssetManager am = getAssets();
        Set<String> themeEntries = new HashSet<String>();
        InputStream manifestIn = am.open(assetThemePrefix + "/manifest.txt");
        BufferedReader br = new BufferedReader(new InputStreamReader(manifestIn, "UTF-8"));
        String line;
        while ((line = br.readLine()) != null) {
            String trimmed = line.trim();
            if (!trimmed.isEmpty() && !trimmed.equals("manifest.txt") && !trimmed.equals("layout-patches.txt") && !trimmed.equals("runtime-composite.txt")) {
                themeEntries.add(trimmed);
            }
        }
        br.close();

        Map<String, String> layoutPatches = new HashMap<String, String>();
        try {
            InputStream lpIn = am.open(assetThemePrefix + "/layout-patches.txt");
            BufferedReader lpBr = new BufferedReader(new InputStreamReader(lpIn, "UTF-8"));
            String lpLine;
            while ((lpLine = lpBr.readLine()) != null) {
                String t = lpLine.trim();
                int bar = t.indexOf('|');
                if (bar > 0) {
                    layoutPatches.put(t.substring(0, bar).trim(), t.substring(bar + 1).trim());
                }
            }
            lpBr.close();
        } catch (Exception ignored) {
        }

        Map<String, String> runtimeCfg = new HashMap<String, String>();
        try {
            InputStream rcIn = am.open(assetThemePrefix + "/runtime-composite.txt");
            BufferedReader rcBr = new BufferedReader(new InputStreamReader(rcIn, "UTF-8"));
            String rcLine;
            while ((rcLine = rcBr.readLine()) != null) {
                String t = rcLine.trim();
                int eq = t.indexOf('=');
                if (eq > 0) {
                    runtimeCfg.put(t.substring(0, eq).trim(), t.substring(eq + 1).trim());
                }
            }
            rcBr.close();
        } catch (Exception ignored) {
        }
        boolean compositeOemBattery = "oem".equalsIgnoreCase(runtimeCfg.get("batteryStyle"));
        float batScale = parseFloatSafe(runtimeCfg.get("batteryScale"), 100.0f);
        float batOffX = parseFloatSafe(runtimeCfg.get("batteryOffX"), 0.0f);
        float batOffY = parseFloatSafe(runtimeCfg.get("batteryOffY"), 0.0f);
        Set<String> compositeOemIcons = new HashSet<String>();
        String oemIconList = runtimeCfg.get("compositeOemIcons");
        if (oemIconList != null && !oemIconList.trim().isEmpty()) {
            String[] parts = oemIconList.split(",");
            for (int pi = 0; pi < parts.length; pi++) {
                String k = parts[pi].trim();
                if (!k.isEmpty()) compositeOemIcons.add(k);
            }
        }
        float globalIconScale = parseFloatSafe(runtimeCfg.get("globalIconScale"), 100.0f);
        float globalIconOffX = parseFloatSafe(runtimeCfg.get("globalIconOffX"), 0.0f);
        float globalIconOffY = parseFloatSafe(runtimeCfg.get("globalIconOffY"), 0.0f);
        float mediaOffX = parseFloatSafe(runtimeCfg.get("mediaOffX"), 0.0f);
        float mediaOffY = parseFloatSafe(runtimeCfg.get("mediaOffY"), 0.0f);
        float mediaFontScale = parseFloatSafe(runtimeCfg.get("mediaFontScale"), 100.0f);
        boolean transformAvMain = (mediaOffX != 0.0f || mediaOffY != 0.0f || mediaFontScale != 100.0f);

        int replaced = 0;
        ZipFile origZip = new ZipFile(sourceApk);
        FileOutputStream fos = new FileOutputStream(destApk);
        BufferedOutputStream bos = new BufferedOutputStream(fos, 65536);
        CountingOutputStream cos = new CountingOutputStream(bos);
        ZipOutputStream zos = new ZipOutputStream(cos);

        byte[] buf = new byte[65536];
        try {
            Enumeration<? extends ZipEntry> entries = origZip.entries();
            while (entries.hasMoreElements()) {
                ZipEntry origEntry = entries.nextElement();
                String name = origEntry.getName();

                if (themeEntries.contains(name)) {
                    byte[] replacementBytes = readAssetBytes(am, assetThemePrefix + "/" + name);
                    if (compositeOemBattery && name.contains("home_etc_battery_") && name.endsWith(".webp")) {
                        try {
                            byte[] stockBytes = readStreamBytes(origZip.getInputStream(origEntry));
                            byte[] merged = compositeOemCarWithOverlay(stockBytes, replacementBytes, batScale, batOffX, batOffY);
                            if (merged != null) {
                                replacementBytes = merged;
                            }
                        } catch (Exception ignored) {
                        }
                    } else if (!compositeOemIcons.isEmpty() && name.contains("/hom_") && name.endsWith("_66.webp")) {
                        int slash = name.lastIndexOf('/');
                        int dot = name.lastIndexOf('.');
                        String baseIcon = (slash >= 0 && dot > slash) ? name.substring(slash + 1, dot) : "";
                        if (compositeOemIcons.contains(baseIcon) || compositeOemIcons.contains("ALL")) {
                            try {
                                float iScale = parseFloatSafe(runtimeCfg.get("iconScale." + baseIcon), globalIconScale);
                                float iOffX = parseFloatSafe(runtimeCfg.get("iconOffX." + baseIcon), globalIconOffX);
                                float iOffY = parseFloatSafe(runtimeCfg.get("iconOffY." + baseIcon), globalIconOffY);
                                byte[] stockIconBytes = readStreamBytes(origZip.getInputStream(origEntry));
                                byte[] mergedIcon = compositeOemIconWithTile(stockIconBytes, replacementBytes, iScale, iOffX, iOffY);
                                if (mergedIcon != null) {
                                    replacementBytes = mergedIcon;
                                }
                            } catch (Exception ignored) {
                            }
                        }
                    }
                    writeAlignedStoredEntry(zos, cos, name, replacementBytes);
                    replaced++;
                } else if (layoutPatches.containsKey(name)) {
                    byte[] rawXml = readStreamBytes(origZip.getInputStream(origEntry));
                    String spec = layoutPatches.get(name);
                    if (spec != null && !spec.isEmpty()) {
                        String[] pairs = spec.split(",");
                        for (int pi = 0; pi < pairs.length; pi++) {
                            String pair = pairs[pi].trim();
                            int colon = pair.indexOf(':');
                            if (colon > 0) {
                                int offset = Integer.parseInt(pair.substring(0, colon));
                                int val = Integer.parseInt(pair.substring(colon + 1), 16) & 0xFF;
                                if (offset >= 0 && offset < rawXml.length) {
                                    rawXml[offset] = (byte) val;
                                }
                            }
                        }
                    }
                    ZipEntry outEntry = new ZipEntry(name);
                    outEntry.setMethod(ZipEntry.DEFLATED);
                    outEntry.setExtra(null);
                    zos.putNextEntry(outEntry);
                    zos.write(rawXml);
                    zos.closeEntry();
                    replaced++;
                } else if (transformAvMain && name.startsWith("res/layout/widget_av_main_") && name.endsWith(".xml")) {
                    byte[] rawXml = readStreamBytes(origZip.getInputStream(origEntry));
                    rawXml = transformAvMainLayoutXml(
                            rawXml,
                            Math.round(mediaOffX / 1.5f),
                            Math.round(mediaOffY / 1.5f),
                            mediaFontScale);
                    ZipEntry outEntry = new ZipEntry(name);
                    outEntry.setMethod(ZipEntry.DEFLATED);
                    outEntry.setExtra(null);
                    zos.putNextEntry(outEntry);
                    zos.write(rawXml);
                    zos.closeEntry();
                    replaced++;
                } else if (origEntry.getMethod() == ZipEntry.STORED || name.equals("resources.arsc")) {
                    ZipEntry outEntry = new ZipEntry(name);
                    outEntry.setMethod(ZipEntry.STORED);
                    long size = origEntry.getSize();
                    long crc = origEntry.getCrc();
                    if (size < 0 || crc < 0) {
                        byte[] raw = readStreamBytes(origZip.getInputStream(origEntry));
                        writeAlignedStoredEntry(zos, cos, name, raw);
                    } else {
                        outEntry.setSize(size);
                        outEntry.setCompressedSize(size);
                        outEntry.setCrc(crc);
                        int nameLen = name.getBytes("UTF-8").length;
                        long headerEnd = cos.getCount() + 30L + nameLen;
                        int pad = (int) ((4L - (headerEnd % 4L)) % 4L);
                        if (pad > 0) {
                            outEntry.setExtra(new byte[pad]);
                        } else {
                            outEntry.setExtra(null);
                        }
                        zos.putNextEntry(outEntry);
                        InputStream in = origZip.getInputStream(origEntry);
                        int r;
                        while ((r = in.read(buf)) != -1) {
                            zos.write(buf, 0, r);
                        }
                        in.close();
                        zos.closeEntry();
                    }
                } else {
                    ZipEntry outEntry = new ZipEntry(name);
                    outEntry.setMethod(ZipEntry.DEFLATED);
                    outEntry.setExtra(null);
                    zos.putNextEntry(outEntry);
                    InputStream in = origZip.getInputStream(origEntry);
                    int r;
                    while ((r = in.read(buf)) != -1) {
                        zos.write(buf, 0, r);
                    }
                    in.close();
                    zos.closeEntry();
                }
            }
        } finally {
            zos.close();
            origZip.close();
        }
        return replaced;
    }

    private void stageOptionalSubApk(String label, String targetSystemPath, String stockBackupPath, String themedOutPath, String assetSubPrefix) {
        AssetManager am = getAssets();
        Map<String, String> entryMap = new HashMap<String, String>();
        InputStream manifestIn = null;
        try {
            manifestIn = am.open(assetSubPrefix + "/manifest.txt");
            BufferedReader br = new BufferedReader(new InputStreamReader(manifestIn, "UTF-8"));
            String line;
            while ((line = br.readLine()) != null) {
                String t = line.trim();
                if (!t.isEmpty() && !t.equals("manifest.txt") && !t.equals("runtime-composite.txt")) {
                    int bar = t.indexOf('|');
                    if (bar > 0) {
                        entryMap.put(t.substring(0, bar).trim(), t.substring(bar + 1).trim());
                    } else {
                        entryMap.put(t, t);
                    }
                }
            }
            br.close();
        } catch (Exception ignored) {
        } finally {
            if (manifestIn != null) {
                try { manifestIn.close(); } catch (Exception ignored) {}
            }
        }

        Map<String, String> runtimeCfg = new HashMap<String, String>();
        InputStream rcIn = null;
        try {
            rcIn = am.open(assetSubPrefix + "/runtime-composite.txt");
            BufferedReader rcBr = new BufferedReader(new InputStreamReader(rcIn, "UTF-8"));
            String rcLine;
            while ((rcLine = rcBr.readLine()) != null) {
                String t = rcLine.trim();
                int eq = t.indexOf('=');
                if (eq > 0) {
                    runtimeCfg.put(t.substring(0, eq).trim(), t.substring(eq + 1).trim());
                }
            }
            rcBr.close();
        } catch (Exception ignored) {
        } finally {
            if (rcIn != null) {
                try { rcIn.close(); } catch (Exception ignored) {}
            }
        }

        boolean hasOemScaleTransform = "true".equalsIgnoreCase(runtimeCfg.get("scaleOemEvCar"))
                || "true".equalsIgnoreCase(runtimeCfg.get("scaleOemClimateSeat"));
        File outApk = new File(themedOutPath);

        if (entryMap.isEmpty() && !hasOemScaleTransform) {
            if (outApk.exists()) {
                outApk.delete();
            }
            appendLog(" - " + label + ": Factory Stock (OEM unmodified)");
            return;
        }

        File stockApk = new File(targetSystemPath);
        if (!stockApk.exists()) {
            if (outApk.exists()) outApk.delete();
            appendLog(" - " + label + ": Not present on vehicle (" + targetSystemPath + "), skipping.");
            return;
        }

        try {
            long t0 = System.currentTimeMillis();
            File cleanStockBackup = new File(stockBackupPath);
            if (!cleanStockBackup.exists() && !isTargetBindMounted(targetSystemPath)) {
                copyFile(stockApk, cleanStockBackup);
                cleanStockBackup.setReadable(true, false);
            }
            File sourceApk = cleanStockBackup.exists() ? cleanStockBackup : stockApk;
            File outTmp = new File(themedOutPath + ".tmp");
            int count = buildThemedSubApk(sourceApk, outTmp, assetSubPrefix, entryMap, runtimeCfg);
            if (outApk.exists()) outApk.delete();
            if (!outTmp.renameTo(outApk)) {
                copyFile(outTmp, outApk);
                outTmp.delete();
            }
            outApk.setReadable(true, false);
            long dt = System.currentTimeMillis() - t0;
            appendLog(" - " + label + ": Patched " + count + " resources into " + outApk.getName() + " (" + (outApk.length() / 1024) + " KB) in " + dt + " ms.");
        } catch (Exception e) {
            if (outApk.exists()) outApk.delete();
            appendLog(" - WARNING (" + label + "): Failed to stage sub-APK: " + e.toString());
        }
    }

    private int buildThemedSubApk(File sourceApk, File destApk, String assetSubPrefix, Map<String, String> entryMap, Map<String, String> runtimeCfg) throws Exception {
        AssetManager am = getAssets();
        Map<String, byte[]> assetCache = new HashMap<String, byte[]>();
        boolean scaleOemEvCar = "true".equalsIgnoreCase(runtimeCfg.get("scaleOemEvCar"));
        float evCarScale = parseFloatSafe(runtimeCfg.get("evCarScale"), 100.0f);
        float evCarOffX = parseFloatSafe(runtimeCfg.get("evCarOffX"), 0.0f);
        float evCarOffY = parseFloatSafe(runtimeCfg.get("evCarOffY"), 0.0f);

        boolean scaleOemClimateSeat = "true".equalsIgnoreCase(runtimeCfg.get("scaleOemClimateSeat"));
        float seatScale = parseFloatSafe(runtimeCfg.get("seatScale"), 100.0f);
        float seatOffX = parseFloatSafe(runtimeCfg.get("seatOffX"), 0.0f);
        float seatOffY = parseFloatSafe(runtimeCfg.get("seatOffY"), 0.0f);

        int replaced = 0;
        ZipFile origZip = new ZipFile(sourceApk);
        FileOutputStream fos = new FileOutputStream(destApk);
        BufferedOutputStream bos = new BufferedOutputStream(fos, 65536);
        CountingOutputStream cos = new CountingOutputStream(bos);
        ZipOutputStream zos = new ZipOutputStream(cos);

        byte[] buf = new byte[65536];
        try {
            Enumeration<? extends ZipEntry> entries = origZip.entries();
            while (entries.hasMoreElements()) {
                ZipEntry origEntry = entries.nextElement();
                String name = origEntry.getName();

                if (entryMap.containsKey(name)) {
                    String relAsset = entryMap.get(name);
                    byte[] replacementBytes = assetCache.get(relAsset);
                    if (replacementBytes == null) {
                        replacementBytes = readAssetBytes(am, assetSubPrefix + "/" + relAsset);
                        assetCache.put(relAsset, replacementBytes);
                    }
                    writeAlignedStoredEntry(zos, cos, name, replacementBytes);
                    replaced++;
                } else if (scaleOemEvCar && (name.contains("ev_ic_battery_bg") || name.contains("ev_ic_battery_cover")) && name.endsWith(".webp")) {
                    byte[] stockBytes = readStreamBytes(origZip.getInputStream(origEntry));
                    byte[] transformed = scaleOffsetOemImage(stockBytes, 450, 255, evCarScale, evCarOffX, evCarOffY, false);
                    writeAlignedStoredEntry(zos, cos, name, transformed != null ? transformed : stockBytes);
                    replaced++;
                } else if (scaleOemClimateSeat && name.endsWith("clm_bg_seat.png")) {
                    byte[] stockBytes = readStreamBytes(origZip.getInputStream(origEntry));
                    byte[] transformed = scaleOffsetOemImage(stockBytes, 309, 351, seatScale, seatOffX, seatOffY, true);
                    writeAlignedStoredEntry(zos, cos, name, transformed != null ? transformed : stockBytes);
                    replaced++;
                } else if (origEntry.getMethod() == ZipEntry.STORED || name.equals("resources.arsc")) {
                    ZipEntry outEntry = new ZipEntry(name);
                    outEntry.setMethod(ZipEntry.STORED);
                    long size = origEntry.getSize();
                    long crc = origEntry.getCrc();
                    if (size < 0 || crc < 0) {
                        byte[] raw = readStreamBytes(origZip.getInputStream(origEntry));
                        writeAlignedStoredEntry(zos, cos, name, raw);
                    } else {
                        outEntry.setSize(size);
                        outEntry.setCompressedSize(size);
                        outEntry.setCrc(crc);
                        int nameLen = name.getBytes("UTF-8").length;
                        long headerEnd = cos.getCount() + 30L + nameLen;
                        int pad = (int) ((4L - (headerEnd % 4L)) % 4L);
                        if (pad > 0) {
                            outEntry.setExtra(new byte[pad]);
                        } else {
                            outEntry.setExtra(null);
                        }
                        zos.putNextEntry(outEntry);
                        InputStream in = origZip.getInputStream(origEntry);
                        int r;
                        while ((r = in.read(buf)) != -1) {
                            zos.write(buf, 0, r);
                        }
                        in.close();
                        zos.closeEntry();
                    }
                } else {
                    ZipEntry outEntry = new ZipEntry(name);
                    outEntry.setMethod(ZipEntry.DEFLATED);
                    outEntry.setExtra(null);
                    zos.putNextEntry(outEntry);
                    InputStream in = origZip.getInputStream(origEntry);
                    int r;
                    while ((r = in.read(buf)) != -1) {
                        zos.write(buf, 0, r);
                    }
                    in.close();
                    zos.closeEntry();
                }
            }
        } finally {
            zos.close();
            origZip.close();
        }
        return replaced;
    }

    private byte[] scaleOffsetOemImage(byte[] stockBytes, int targetW, int targetH, float scalePct, float offX, float offY, boolean asPng) {
        Bitmap stockBmp = BitmapFactory.decodeByteArray(stockBytes, 0, stockBytes.length);
        if (stockBmp == null) return null;
        try {
            Bitmap outBmp = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888);
            Canvas outCanvas = new Canvas(outBmp);
            Paint p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
            float s = (scalePct > 0f ? scalePct : 100f) / 100.0f;
            float dw = targetW * s;
            float dh = targetH * s;
            float dx = (targetW / 2.0f - dw / 2.0f) + offX;
            float dy = (targetH / 2.0f - dh / 2.0f) + offY;
            RectF dstRect = new RectF(dx, dy, dx + dw, dy + dh);
            outCanvas.drawBitmap(stockBmp, null, dstRect, p);
            ByteArrayOutputStream baos = new ByteArrayOutputStream(16384);
            if (asPng || !outBmp.compress(Bitmap.CompressFormat.WEBP, 100, baos)) {
                baos.reset();
                outBmp.compress(Bitmap.CompressFormat.PNG, 100, baos);
            }
            outBmp.recycle();
            return baos.toByteArray();
        } finally {
            stockBmp.recycle();
        }
    }

    private void writeAlignedStoredEntry(ZipOutputStream zos, CountingOutputStream cos, String name, byte[] data) throws IOException {
        ZipEntry outEntry = new ZipEntry(name);
        outEntry.setMethod(ZipEntry.STORED);
        outEntry.setSize(data.length);
        outEntry.setCompressedSize(data.length);
        CRC32 crc = new CRC32();
        crc.update(data);
        outEntry.setCrc(crc.getValue());

        int nameLen = name.getBytes("UTF-8").length;
        long headerEnd = cos.getCount() + 30L + nameLen;
        int pad = (int) ((4L - (headerEnd % 4L)) % 4L);
        if (pad > 0) {
            outEntry.setExtra(new byte[pad]);
        } else {
            outEntry.setExtra(null);
        }

        zos.putNextEntry(outEntry);
        zos.write(data);
        zos.closeEntry();
    }

    private float parseFloatSafe(String val, float def) {
        if (val == null || val.trim().isEmpty()) return def;
        try {
            return Float.parseFloat(val.trim());
        } catch (Exception e) {
            return def;
        }
    }

    private static int readUInt16LE(byte[] b, int off) {
        return (b[off] & 0xFF) | ((b[off + 1] & 0xFF) << 8);
    }

    private static void writeUInt16LE(byte[] b, int off, int val) {
        b[off] = (byte) (val & 0xFF);
        b[off + 1] = (byte) ((val >> 8) & 0xFF);
    }

    private static int readInt32LE(byte[] b, int off) {
        return (b[off] & 0xFF)
                | ((b[off + 1] & 0xFF) << 8)
                | ((b[off + 2] & 0xFF) << 16)
                | ((b[off + 3] & 0xFF) << 24);
    }

    private static void writeInt32LE(byte[] b, int off, int val) {
        b[off] = (byte) (val & 0xFF);
        b[off + 1] = (byte) ((val >> 8) & 0xFF);
        b[off + 2] = (byte) ((val >> 16) & 0xFF);
        b[off + 3] = (byte) ((val >> 24) & 0xFF);
    }

    private byte[] transformAvMainLayoutXml(byte[] rawXml, int offXDp, int offYDp, float scalePct) {
        if (rawXml == null || rawXml.length < 64) return rawXml;
        try {
            if (readUInt16LE(rawXml, 0) != 0x0003) return rawXml;
            int strPoolOff = 8;
            if (readUInt16LE(rawXml, strPoolOff) != 0x0001) return rawXml;
            int strPoolSize = readInt32LE(rawXml, strPoolOff + 4);
            int strCount = readInt32LE(rawXml, strPoolOff + 8);

            int resMapOff = strPoolOff + strPoolSize;
            if (resMapOff + 8 > rawXml.length || readUInt16LE(rawXml, resMapOff) != 0x0180) return rawXml;
            int resMapSize = readInt32LE(rawXml, resMapOff + 4);
            int resMapCount = (resMapSize - 8) / 4;

            // 1. Scale textSize (0x01010095) and fixed text row layout_height (0x010100F5) across all elements
            int firstStartElemOff = -1;
            int pos = resMapOff + resMapSize;
            float sFactor = (scalePct > 0f ? scalePct : 100f) / 100.0f;
            while (pos + 8 <= rawXml.length) {
                int cType = readUInt16LE(rawXml, pos);
                int cSize = readInt32LE(rawXml, pos + 4);
                if (cSize <= 0 || pos + cSize > rawXml.length) break;
                if (cType == 0x0102) {
                    if (firstStartElemOff < 0) firstStartElemOff = pos;
                    if (Math.abs(scalePct - 100.0f) > 0.5f) {
                        int attrCount = readUInt16LE(rawXml, pos + 28);
                        int aBase = pos + 36;
                        for (int ai = 0; ai < attrCount; ai++) {
                            int aOff = aBase + ai * 20;
                            if (aOff + 20 > pos + cSize) break;
                            int nameIdx = readInt32LE(rawXml, aOff + 4);
                            int resId = (nameIdx >= 0 && nameIdx < resMapCount)
                                    ? readInt32LE(rawXml, resMapOff + 8 + nameIdx * 4) : 0;
                            int dType = rawXml[aOff + 15] & 0xFF;
                            int data = readInt32LE(rawXml, aOff + 16);
                            if (resId == 0x01010095) { // android:textSize
                                if (dType == 5) {
                                    int unit = data & 0x0F;
                                    int baseVal = data >> 8;
                                    int newVal = Math.max(8, Math.round(baseVal * sFactor));
                                    writeInt32LE(rawXml, aOff + 16, ((newVal & 0xFFFFFF) << 8) | unit);
                                } else if (dType == 1) {
                                    // Convert @dimen reference (stock 22sp) to direct sp dimension
                                    int newSp = Math.max(8, Math.round(22.0f * sFactor));
                                    rawXml[aOff + 15] = 5;
                                    writeInt32LE(rawXml, aOff + 16, ((newSp & 0xFFFFFF) << 8) | 2);
                                }
                            } else if (resId == 0x010100F5 && sFactor > 1.0f && dType == 5) { // android:layout_height
                                int unit = data & 0x0F;
                                int baseVal = data >> 8;
                                if (baseVal >= 18 && baseVal <= 120) {
                                    int newVal = Math.round(baseVal * sFactor);
                                    writeInt32LE(rawXml, aOff + 16, ((newVal & 0xFFFFFF) << 8) | unit);
                                }
                            }
                        }
                    }
                }
                pos += cSize;
            }

            // 2. Inject android:translationX (0x01010320) & android:translationY (0x01010321) into root StartElement
            if ((offXDp != 0 || offYDp != 0) && firstStartElemOff > 0 && strCount >= resMapCount + 2) {
                int rootAttrCount = readUInt16LE(rawXml, firstStartElemOff + 28);
                if (rootAttrCount > 0) {
                    int nsIdx = readInt32LE(rawXml, firstStartElemOff + 36);
                    int insIdx = rootAttrCount;
                    for (int ai = 0; ai < rootAttrCount; ai++) {
                        int aOff = firstStartElemOff + 36 + ai * 20;
                        int nameIdx = readInt32LE(rawXml, aOff + 4);
                        int resId = (nameIdx >= 0 && nameIdx < resMapCount)
                                ? readInt32LE(rawXml, resMapOff + 8 + nameIdx * 4) : 0x7FFFFFFF;
                        if (resId > 0x01010320) {
                            insIdx = ai;
                            break;
                        }
                    }

                    int resMapInsertPos = resMapOff + resMapSize;
                    int attrInsertPos = firstStartElemOff + 36 + insIdx * 20;
                    byte[] out = new byte[rawXml.length + 48];

                    // Copy up to end of existing ResourceMap
                    System.arraycopy(rawXml, 0, out, 0, resMapInsertPos);
                    // Append 0x01010320 (translationX) and 0x01010321 (translationY) to ResourceMap (+8 bytes)
                    writeInt32LE(out, resMapInsertPos, 0x01010320);
                    writeInt32LE(out, resMapInsertPos + 4, 0x01010321);

                    // Copy from end of ResourceMap up to attribute insertion point in root StartElement
                    System.arraycopy(rawXml, resMapInsertPos, out, resMapInsertPos + 8, attrInsertPos - resMapInsertPos);

                    // Write two 20-byte ResXMLTree_attribute structs (+40 bytes)
                    int newAttrPos = attrInsertPos + 8;
                    // Attribute 1: android:translationX (nameIdx = resMapCount)
                    writeInt32LE(out, newAttrPos, nsIdx);
                    writeInt32LE(out, newAttrPos + 4, resMapCount);
                    writeInt32LE(out, newAttrPos + 8, -1);
                    writeUInt16LE(out, newAttrPos + 12, 8);
                    out[newAttrPos + 14] = 0;
                    out[newAttrPos + 15] = 5; // TYPE_DIMENSION
                    writeInt32LE(out, newAttrPos + 16, ((offXDp & 0xFFFFFF) << 8) | 1);

                    // Attribute 2: android:translationY (nameIdx = resMapCount + 1)
                    writeInt32LE(out, newAttrPos + 20, nsIdx);
                    writeInt32LE(out, newAttrPos + 24, resMapCount + 1);
                    writeInt32LE(out, newAttrPos + 28, -1);
                    writeUInt16LE(out, newAttrPos + 32, 8);
                    out[newAttrPos + 34] = 0;
                    out[newAttrPos + 35] = 5; // TYPE_DIMENSION
                    writeInt32LE(out, newAttrPos + 36, ((offYDp & 0xFFFFFF) << 8) | 1);

                    // Copy remainder of XML
                    System.arraycopy(rawXml, attrInsertPos, out, newAttrPos + 40, rawXml.length - attrInsertPos);

                    // Update chunk headers: total file size (+48), ResourceMap size (+8), root StartElement size (+40) & attrCount (+2)
                    writeInt32LE(out, 4, rawXml.length + 48);
                    writeInt32LE(out, resMapOff + 4, resMapSize + 8);
                    int newRootOff = firstStartElemOff + 8;
                    int oldRootSize = readInt32LE(out, newRootOff + 4);
                    writeInt32LE(out, newRootOff + 4, oldRootSize + 40);
                    writeUInt16LE(out, newRootOff + 28, rootAttrCount + 2);
                    int idIdx1Based = readUInt16LE(out, newRootOff + 30);
                    if (idIdx1Based > insIdx) {
                        writeUInt16LE(out, newRootOff + 30, idIdx1Based + 2);
                    }
                    return out;
                }
            }
            return rawXml;
        } catch (Exception e) {
            return rawXml;
        }
    }

    private byte[] compositeOemCarWithOverlay(byte[] stockBytes, byte[] overlayBytes, float scalePct, float offX, float offY) {
        Bitmap stockBmp = BitmapFactory.decodeByteArray(stockBytes, 0, stockBytes.length);
        Bitmap overlayBmp = BitmapFactory.decodeByteArray(overlayBytes, 0, overlayBytes.length);
        if (stockBmp == null || overlayBmp == null) {
            if (stockBmp != null) stockBmp.recycle();
            if (overlayBmp != null) overlayBmp.recycle();
            return null;
        }
        try {
            Bitmap carOnly = Bitmap.createBitmap(635, 318, Bitmap.Config.ARGB_8888);
            Canvas carCanvas = new Canvas(carOnly);
            Path carClip = new Path();
            carClip.moveTo(0f, 0f);
            carClip.lineTo(635f, 0f);
            carClip.lineTo(635f, 202f);
            carClip.lineTo(577f, 202f);
            carClip.lineTo(577f, 318f);
            carClip.lineTo(0f, 318f);
            carClip.close();
            carCanvas.clipPath(carClip);
            Paint p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
            carCanvas.drawBitmap(stockBmp, 0f, 0f, p);

            Bitmap outBmp = Bitmap.createBitmap(798, 318, Bitmap.Config.ARGB_8888);
            Canvas outCanvas = new Canvas(outBmp);
            float s = (scalePct > 0f ? scalePct : 100f) / 100.0f;
            float dw = 635.0f * s;
            float dh = 318.0f * s;
            float dx = (317.5f - dw / 2.0f) + offX;
            float dy = (159.0f - dh / 2.0f) + offY;
            RectF dstRect = new RectF(dx, dy, dx + dw, dy + dh);
            outCanvas.drawBitmap(carOnly, null, dstRect, p);
            outCanvas.drawBitmap(overlayBmp, 0f, 0f, p);

            ByteArrayOutputStream baos = new ByteArrayOutputStream(32768);
            if (!outBmp.compress(Bitmap.CompressFormat.WEBP, 100, baos)) {
                baos.reset();
                outBmp.compress(Bitmap.CompressFormat.PNG, 100, baos);
            }
            carOnly.recycle();
            outBmp.recycle();
            return baos.toByteArray();
        } finally {
            stockBmp.recycle();
            overlayBmp.recycle();
        }
    }

    private byte[] compositeOemIconWithTile(byte[] stockIconBytes, byte[] tileBytes, float scalePct, float offX, float offY) {
        Bitmap stockIconBmp = BitmapFactory.decodeByteArray(stockIconBytes, 0, stockIconBytes.length);
        Bitmap tileBmp = BitmapFactory.decodeByteArray(tileBytes, 0, tileBytes.length);
        if (stockIconBmp == null || tileBmp == null) {
            if (stockIconBmp != null) stockIconBmp.recycle();
            if (tileBmp != null) tileBmp.recycle();
            return null;
        }
        try {
            Bitmap outBmp = Bitmap.createBitmap(306, 249, Bitmap.Config.ARGB_8888);
            Canvas outCanvas = new Canvas(outBmp);
            Paint p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
            outCanvas.drawBitmap(tileBmp, 0f, 0f, p);
            float s = (scalePct > 0f ? scalePct : 100f) / 100.0f;
            float boxW = 99.0f * s;
            float boxH = 99.0f * s;
            float boxX = 153.0f - (boxW / 2.0f) + offX;
            float boxY = 103.5f - (boxH / 2.0f) + offY;
            RectF dstRect = new RectF(boxX, boxY, boxX + boxW, boxY + boxH);
            outCanvas.drawBitmap(stockIconBmp, null, dstRect, p);

            ByteArrayOutputStream baos = new ByteArrayOutputStream(16384);
            if (!outBmp.compress(Bitmap.CompressFormat.WEBP, 100, baos)) {
                baos.reset();
                outBmp.compress(Bitmap.CompressFormat.PNG, 100, baos);
            }
            outBmp.recycle();
            return baos.toByteArray();
        } finally {
            stockIconBmp.recycle();
            tileBmp.recycle();
        }
    }

    private byte[] readAssetBytes(AssetManager am, String assetPath) throws IOException {
        InputStream in = am.open(assetPath);
        try {
            return readStreamBytes(in);
        } finally {
            in.close();
        }
    }

    private byte[] readStreamBytes(InputStream in) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream(16384);
        byte[] buf = new byte[16384];
        int r;
        while ((r = in.read(buf)) != -1) {
            baos.write(buf, 0, r);
        }
        return baos.toByteArray();
    }

    private void writeHelperCommandFile(String cmd) throws IOException {
        File dir = new File(WORK_DIR);
        if (!dir.exists()) {
            dir.mkdirs();
        }
        dir.setReadable(true, false);
        dir.setWritable(true, false);
        dir.setExecutable(true, false);

        File tmp = new File(WORK_DIR, "cmd.tmp");
        FileOutputStream fos = new FileOutputStream(tmp);
        fos.write((cmd + "\n").getBytes("UTF-8"));
        fos.flush();
        fos.close();
        tmp.setReadable(true, false);
        tmp.setWritable(true, false);

        File dst = new File(CMD_FILE);
        if (dst.exists()) {
            dst.delete();
        }
        tmp.renameTo(dst);
        dst.setReadable(true, false);
        dst.setWritable(true, false);
    }

    private void runDiagnosticsAsync() {
        if (isBusy) return;
        isBusy = true;
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    StringBuilder sb = new StringBuilder();
                    sb.append("\n=== GEN5W THEMER DIAGNOSTICS ===\n");
                    sb.append("Bundled Theme Name        : ").append(bundledThemeName).append("\n");
                    sb.append("Launcher Currently Themed : ").append(isLauncherCurrentlyThemed() ? "YES (Custom Theme Active)" : "NO (Factory Stock)").append("\n");
                    sb.append("Launcher in /proc/mounts  : ").append(isLauncherBindMounted() ? "YES" : "NO").append("\n");
                    sb.append("SystemUI in /proc/mounts  : ").append(isTargetBindMounted(TARGET_SYSUI) ? "YES" : "NO").append("\n");
                    sb.append("Climate in /proc/mounts   : ").append(isTargetBindMounted(TARGET_CLIMATE) ? "YES" : "NO").append("\n");
                    sb.append("EV App in /proc/mounts    : ").append(isTargetBindMounted(TARGET_EV) ? "YES" : "NO").append("\n");
                    sb.append("Active State File         : ").append(readFirstLine(new File(ACTIVE_FILE))).append("\n");
                    sb.append("Auto-Boot State           : ").append(readFirstLine(new File(AUTOSTART_STATE_FILE))).append(" (enabled=").append(readFirstLine(new File(AUTOSTART_ENABLED_FILE))).append(", strikes=").append(readFirstLine(new File(AUTOSTART_STRIKES_FILE))).append(")\n");
                    sb.append("Helper Status File        : ").append(readFirstLine(new File(STATUS_FILE))).append("\n");
                    sb.append("Countdown File            : ").append(readFirstLine(new File(COUNTDOWN_FILE))).append("\n");

                    File themed = new File(THEMED_APK);
                    sb.append("RAM Staged APK            : ").append(themed.exists() ? (themed.length() / 1024 + " KB") : "Not built yet").append("\n");

                    CmdResult pingRes = execNemesis("ping");
                    sb.append("Nemesis Root Socket Ping  : rc=").append(pingRes.rc).append("\n");

                    CmdResult svcStat = execNemesis("service", "status", HELPER_SVC);
                    sb.append("Helper Service Status     : ").append(svcStat.out).append(" (rc=").append(svcStat.rc).append(")\n");

                    CmdResult svcLog = execNemesis("log", "service", HELPER_SVC);
                    if (!svcLog.out.isEmpty()) {
                        sb.append("\n--- Nemesis Service Log ---\n").append(svcLog.out).append("\n");
                    }

                    sb.append("\n--- Helper Log (" + LOG_FILE + ") ---\n");
                    String hlog = readFileText(new File(LOG_FILE), 4000);
                    sb.append(hlog.isEmpty() ? "(No helper.log entries yet)" : hlog);

                    appendLog(sb.toString());
                } finally {
                    isBusy = false;
                }
            }
        }).start();
    }

    private void copyFile(File src, File dst) throws IOException {
        File parent = dst.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }
        FileInputStream fis = new FileInputStream(src);
        FileOutputStream fos = new FileOutputStream(dst);
        byte[] buf = new byte[65536];
        int r;
        try {
            while ((r = fis.read(buf)) != -1) {
                fos.write(buf, 0, r);
            }
            fos.flush();
        } finally {
            try { fis.close(); } catch (Exception ignored) {}
            try { fos.close(); } catch (Exception ignored) {}
        }
    }

    private String readFirstLine(File f) {
        if (!f.exists()) return "";
        BufferedReader br = null;
        try {
            br = new BufferedReader(new InputStreamReader(new FileInputStream(f), "UTF-8"));
            String line = br.readLine();
            return line != null ? line.trim() : "";
        } catch (Exception e) {
            return "";
        } finally {
            if (br != null) {
                try { br.close(); } catch (Exception ignored) {}
            }
        }
    }

    private String readFileText(File f, int maxBytes) {
        if (!f.exists()) return "";
        FileInputStream fis = null;
        try {
            fis = new FileInputStream(f);
            long len = f.length();
            if (len > maxBytes) {
                fis.skip(len - maxBytes);
            }
            byte[] data = readStreamBytes(fis);
            return new String(data, "UTF-8");
        } catch (Exception e) {
            return "";
        } finally {
            if (fis != null) {
                try { fis.close(); } catch (Exception ignored) {}
            }
        }
    }

    private void appendLog(final String msg) {
        mainHandler.post(new Runnable() {
            @Override
            public void run() {
                logView.append(msg + "\n");
                logScroll.post(new Runnable() {
                    @Override
                    public void run() {
                        logScroll.fullScroll(View.FOCUS_DOWN);
                    }
                });
            }
        });
    }
}
