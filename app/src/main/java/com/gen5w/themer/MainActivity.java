package com.gen5w.themer;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffColorFilter;
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
import java.util.zip.Adler32;
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

    private static final String THEMED_ODEX = WORK_DIR + "/Launcher_WP3_themed.odex";
    private static final String STOCK_ODEX = WORK_DIR + "/Launcher_WP3_stock.odex";
    private static final String TARGET_ODEX = "/system/app/Launcher_WP3.odex";

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
    private Button oemCarBtn;
    private Button oemBatteryBtn;
    private Button oemBrandBtn;

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
    private final List<String> detectedEvCarModels = new ArrayList<String>();
    private boolean hasOemRedBattery = false;
    private boolean hasOemYellowBattery = false;
    private boolean hasOemKiaUi = false;
    private boolean hasOemCeSedanHome = false;

    // In-car OEM Built-In Override selectors ("default" keeps the selected theme's behavior)
    private String oemCarOverride = "default";     // default, suv, ce_sedan, sedan, hatch, 1ttruck
    private String oemBatteryOverride = "default"; // default, cyan, red, yellow
    private String oemBrandOverride = "default";   // default, kia, hyundai
    private String oemScanSummary = "";

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
        pickerLp.setMargins(0, 0, 0, 8);
        root.addView(pickerBar, pickerLp);

        // In-Car Built-In OEM Asset Override Bar (reads directly from vehicle's /system APKs)
        LinearLayout oemOverrideBar = new LinearLayout(this);
        oemOverrideBar.setOrientation(LinearLayout.HORIZONTAL);
        oemOverrideBar.setGravity(Gravity.CENTER_VERTICAL);
        oemOverrideBar.setPadding(14, 6, 14, 6);
        GradientDrawable oemBarBg = new GradientDrawable();
        oemBarBg.setColor(Color.parseColor("#111827"));
        oemBarBg.setStroke(2, Color.parseColor("#1F2937"));
        oemBarBg.setCornerRadius(12f);
        oemOverrideBar.setBackground(oemBarBg);

        TextView oemLbl = new TextView(this);
        oemLbl.setText("IN-CAR OEM MIXER:  ");
        oemLbl.setTextSize(TypedValue.COMPLEX_UNIT_PX, 16);
        oemLbl.setTypeface(Typeface.DEFAULT_BOLD);
        oemLbl.setTextColor(Color.parseColor("#94A3B8"));
        oemOverrideBar.addView(oemLbl);

        oemCarBtn = new Button(this);
        oemCarBtn.setTextSize(TypedValue.COMPLEX_UNIT_PX, 16);
        oemCarBtn.setTypeface(Typeface.DEFAULT_BOLD);
        oemCarBtn.setPadding(16, 6, 16, 6);
        oemCarBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                cycleOemCarOverride();
            }
        });

        oemBatteryBtn = new Button(this);
        oemBatteryBtn.setTextSize(TypedValue.COMPLEX_UNIT_PX, 16);
        oemBatteryBtn.setTypeface(Typeface.DEFAULT_BOLD);
        oemBatteryBtn.setPadding(16, 6, 16, 6);
        oemBatteryBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                cycleOemBatteryOverride();
            }
        });

        oemBrandBtn = new Button(this);
        oemBrandBtn.setTextSize(TypedValue.COMPLEX_UNIT_PX, 16);
        oemBrandBtn.setTypeface(Typeface.DEFAULT_BOLD);
        oemBrandBtn.setPadding(16, 6, 16, 6);
        oemBrandBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                cycleOemBrandOverride();
            }
        });

        LinearLayout.LayoutParams obLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        obLp.setMargins(0, 0, 12, 0);
        oemOverrideBar.addView(oemCarBtn, obLp);
        oemOverrideBar.addView(oemBatteryBtn, obLp);
        oemOverrideBar.addView(oemBrandBtn, obLp);

        LinearLayout.LayoutParams oemBarLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        oemBarLp.setMargins(0, 0, 0, 10);
        root.addView(oemOverrideBar, oemBarLp);

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
                "3. RESTORE TO STOCK\n(Disable Auto-Boot & Reboot)",
                "#EF4444", "#FFFFFF");
        revertStockBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                onRevertStockClicked();
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
        updateOemOverrideButtons();

        appendLog("==========================================================================");
        appendLog(" GEN5W OEM LAUNCHER THEME MANAGER v1.1.2 // " + bundledThemes.size() + " THEME(S) AVAILABLE");
        appendLog("==========================================================================");
        appendLog(" - Selected Theme: " + bundledThemeName + " (tap any theme button above to switch)");
        if (!oemScanSummary.isEmpty()) {
            appendLog(" - Built-In OEM Scan: " + oemScanSummary);
        }
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

        discoverBuiltInOemThemesAndVariants();

        selectedThemeSlug = bundledThemes.get(0).slug;
        bundledThemeName = bundledThemes.get(0).name;
    }

    private File getBestSourceApk(String stockBackupPath, String targetSystemPath) {
        File backup = new File(stockBackupPath);
        if (backup.exists() && backup.length() > 10000L) {
            return backup;
        }
        return new File(targetSystemPath);
    }

    private void discoverBuiltInOemThemesAndVariants() {
        detectedEvCarModels.clear();
        hasOemRedBattery = false;
        hasOemYellowBattery = false;
        hasOemKiaUi = false;
        hasOemCeSedanHome = false;

        List<String> foundSummary = new ArrayList<String>();
        ZipFile lZip = null;
        try {
            File lFile = getBestSourceApk(STOCK_APK, TARGET_APK);
            if (lFile.exists()) {
                lZip = new ZipFile(lFile);
                if (lZip.getEntry("res/drawable-hdpi/home_etc_battery_r_05.webp") != null) {
                    hasOemRedBattery = true;
                }
                if (lZip.getEntry("res/drawable-hdpi/home_etc_battery_y_05.webp") != null) {
                    hasOemYellowBattery = true;
                }
                if (lZip.getEntry("res/drawable-hdpi/home_etc_battery_ce_sedan_05.webp") != null) {
                    hasOemCeSedanHome = true;
                }
            }
        } catch (Exception ignored) {
        } finally {
            if (lZip != null) { try { lZip.close(); } catch (Exception ignored) {} }
        }

        ZipFile sZip = null;
        try {
            File sFile = getBestSourceApk(STOCK_SYSUI, TARGET_SYSUI);
            if (sFile.exists()) {
                sZip = new ZipFile(sFile);
                if (sZip.getEntry("res/drawable-kia-hdpi/co_btn_home_1920_nor.png") != null
                        || sZip.getEntry("res/drawable-eco-kia-hdpi/co_btn_home_1280_focus.png") != null) {
                    hasOemKiaUi = true;
                }
            }
        } catch (Exception ignored) {
        } finally {
            if (sZip != null) { try { sZip.close(); } catch (Exception ignored) {} }
        }

        ZipFile eZip = null;
        try {
            File eFile = getBestSourceApk(STOCK_EV, TARGET_EV);
            if (eFile.exists()) {
                eZip = new ZipFile(eFile);
                String[] candidates = new String[] { "suv", "ce_sedan", "sedan", "hatch", "1ttruck" };
                for (int i = 0; i < candidates.length; i++) {
                    String m = candidates[i];
                    if (eZip.getEntry("res/drawable-nodpi/ev_ic_battery_bg_" + m + "_nor.webp") != null) {
                        detectedEvCarModels.add(m);
                    }
                }
                if (eZip.getEntry("res/drawable-nodpi/ev_etc_battery_r_05.webp") != null) {
                    hasOemRedBattery = true;
                }
                if (eZip.getEntry("res/drawable-nodpi/ev_etc_battery_y_05.webp") != null) {
                    hasOemYellowBattery = true;
                }
            }
        } catch (Exception ignored) {
        } finally {
            if (eZip != null) { try { eZip.close(); } catch (Exception ignored) {} }
        }

        if (hasOemKiaUi) {
            bundledThemes.add(new ThemeEntry("oem:kia_eco", "[OEM] Kia Eco Red UI"));
            foundSummary.add("Kia UI");
        }
        if (hasOemRedBattery) {
            bundledThemes.add(new ThemeEntry("oem:n_sport", "[OEM] N-Sport Red"));
            foundSummary.add("Red Battery");
        }
        if (hasOemYellowBattery) {
            bundledThemes.add(new ThemeEntry("oem:amber_gold", "[OEM] Amber Gold"));
            foundSummary.add("Amber Battery");
        }
        if (detectedEvCarModels.contains("ce_sedan") || hasOemCeSedanHome) {
            bundledThemes.add(new ThemeEntry("oem:ioniq6_sedan", "[OEM] CE Streamliner"));
        }
        if (detectedEvCarModels.contains("1ttruck")) {
            bundledThemes.add(new ThemeEntry("oem:ev_1ttruck", "[OEM] 1-Ton EV Truck"));
        }
        if (!detectedEvCarModels.isEmpty()) {
            foundSummary.add(detectedEvCarModels.size() + " EV bodies");
        }
        StringBuilder sum = new StringBuilder();
        for (int i = 0; i < foundSummary.size(); i++) {
            if (i > 0) sum.append(", ");
            sum.append(foundSummary.get(i));
        }
        oemScanSummary = sum.toString();
    }

    private String formatCarModelLabel(String code) {
        if ("suv".equals(code)) return "SUV";
        if ("ce_sedan".equals(code)) return "CE SEDAN";
        if ("sedan".equals(code)) return "SEDAN";
        if ("hatch".equals(code)) return "HATCH";
        if ("1ttruck".equals(code)) return "1T TRUCK";
        return "THEME DEFAULT";
    }

    private void cycleOemCarOverride() {
        List<String> opts = new ArrayList<String>();
        opts.add("default");
        for (int i = 0; i < detectedEvCarModels.size(); i++) {
            opts.add(detectedEvCarModels.get(i));
        }
        if (opts.size() == 1 && hasOemCeSedanHome) {
            opts.add("ce_sedan");
        }
        int idx = opts.indexOf(oemCarOverride);
        oemCarOverride = opts.get((idx + 1) % opts.size());
        updateOemOverrideButtons();
        appendLog("In-Car OEM Car Body override -> " + formatCarModelLabel(oemCarOverride));
    }

    private void cycleOemBatteryOverride() {
        List<String> opts = new ArrayList<String>();
        opts.add("default");
        opts.add("cyan");
        if (hasOemRedBattery) opts.add("red");
        if (hasOemYellowBattery) opts.add("yellow");
        int idx = opts.indexOf(oemBatteryOverride);
        oemBatteryOverride = opts.get((idx + 1) % opts.size());
        updateOemOverrideButtons();
        appendLog("In-Car OEM Battery Color override -> " + oemBatteryOverride.toUpperCase());
    }

    private void cycleOemBrandOverride() {
        List<String> opts = new ArrayList<String>();
        opts.add("default");
        if (hasOemKiaUi) opts.add("kia");
        opts.add("hyundai");
        int idx = opts.indexOf(oemBrandOverride);
        oemBrandOverride = opts.get((idx + 1) % opts.size());
        updateOemOverrideButtons();
        appendLog("In-Car OEM Status Bar Brand override -> " + oemBrandOverride.toUpperCase());
    }

    private void styleMixerButton(Button btn, String text, boolean active) {
        if (btn == null) return;
        btn.setText(text);
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(10f);
        if (active) {
            bg.setColor(Color.parseColor("#F59E0B"));
            bg.setStroke(2, Color.parseColor("#FEF3C7"));
            btn.setTextColor(Color.parseColor("#050811"));
        } else {
            bg.setColor(Color.parseColor("#1E293B"));
            bg.setStroke(2, Color.parseColor("#334155"));
            btn.setTextColor(Color.parseColor("#CBD5E1"));
        }
        btn.setBackground(bg);
    }

    private void updateOemOverrideButtons() {
        styleMixerButton(oemCarBtn, "EV BODY: " + formatCarModelLabel(oemCarOverride), !"default".equals(oemCarOverride));
        String batLbl = "default".equals(oemBatteryOverride) ? "THEME DEFAULT" : oemBatteryOverride.toUpperCase();
        styleMixerButton(oemBatteryBtn, "BATTERY: " + batLbl, !"default".equals(oemBatteryOverride));
        String brLbl = "default".equals(oemBrandOverride) ? "THEME DEFAULT" : (oemBrandOverride.toUpperCase() + " UI");
        styleMixerButton(oemBrandBtn, "TOP BAR: " + brLbl, !"default".equals(oemBrandOverride));
    }

    private void selectThemeEntry(ThemeEntry chosen, boolean logSelection) {
        selectedThemeSlug = chosen.slug;
        bundledThemeName = chosen.name;
        for (int i = 0; i < bundledThemes.size(); i++) {
            ThemeEntry te = bundledThemes.get(i);
            if (te.pillBtn == null) continue;
            boolean isSel = te.slug.equals(selectedThemeSlug);
            boolean isOem = te.slug.startsWith("oem:");
            GradientDrawable bg = new GradientDrawable();
            if (isSel) {
                bg.setColor(Color.parseColor(isOem ? "#F59E0B" : "#38BDF8"));
                bg.setStroke(2, Color.parseColor(isOem ? "#FEF3C7" : "#E0F2FE"));
                te.pillBtn.setTextColor(Color.parseColor("#050811"));
                te.pillBtn.setText("✓ " + te.name);
            } else {
                bg.setColor(Color.parseColor("#1E293B"));
                bg.setStroke(2, Color.parseColor(isOem ? "#B45309" : "#334155"));
                te.pillBtn.setTextColor(Color.parseColor(isOem ? "#FDE68A" : "#E2E8F0"));
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
            String srcLabel = selectedThemeSlug.startsWith("oem:") ? ("on-device OEM remap: " + selectedThemeSlug) : ("pack: themes/" + selectedThemeSlug);
            appendLog("Selected theme to apply: '" + bundledThemeName + "' (" + srcLabel + ")");
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

    private void onRevertStockClicked() {
        appendLog("\n>>> Restore to Stock requested: disarming Auto-Boot on disk first...");
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    writeHelperCommandFile("DISABLE_AUTOSTART");
                    CmdResult res = execNemesis("root", "-c", "sh " + HELPER_SH + " DIRECT_DISABLE_AUTOSTART");
                    appendLog("Auto-Boot disarm rc=" + res.rc + (res.out.isEmpty() ? "" : (" (" + res.out + ")")));
                    mainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            updateLiveStatusBanner();
                        }
                    });
                } catch (Exception e) {
                    appendLog("ERROR disarming Auto-Boot: " + e.toString());
                }
            }
        }).start();
        showRestoreStockDialog();
    }

    private void showRestoreStockDialog() {
        if (isFinishing()) return;
        new AlertDialog.Builder(this)
                .setTitle("Restore to Factory Stock")
                .setMessage("Auto-Boot has been disabled.\n\n"
                        + "A display reboot is about to happen to cleanly restore all head-unit screens back to factory OEM stock.\n\n"
                        + "Tap [REBOOT DISPLAY NOW] to restart the head unit into stock mode.")
                .setCancelable(true)
                .setPositiveButton("REBOOT DISPLAY NOW", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        triggerRevertAndRebootAsync();
                    }
                })
                .setNegativeButton("CLOSE", null)
                .show();
    }

    private void triggerRevertAndRebootAsync() {
        setBannerStyle("DISABLING AUTO-BOOT & REBOOTING DISPLAY TO FACTORY STOCK...", "#EF4444", "#FFFFFF");
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    appendLog("\n>>> Disabling Auto-Boot, unmounting overlays, and rebooting display...");
                    writeHelperCommandFile("REVERT_REBOOT");
                    CmdResult res = execNemesis("root", "-c", "sh " + HELPER_SH + " DIRECT_REVERT_REBOOT");
                    appendLog("DIRECT_REVERT_REBOOT rc=" + res.rc + (res.out.isEmpty() ? "" : (" (" + res.out + ")")));
                } catch (Exception e) {
                    appendLog("ERROR requesting reboot: " + e.toString());
                }
            }
        }).start();

        mainHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (!isFinishing()) {
                    updateLiveStatusBanner();
                    showPinholeResetDialog();
                }
            }
        }, 3000);
    }

    private void showPinholeResetDialog() {
        if (isFinishing()) return;
        new AlertDialog.Builder(this)
                .setTitle("Pin-Hole Reset Required")
                .setMessage("Auto-Boot is disabled, and the head unit could not reboot automatically.\n\n"
                        + "Please press the recessed PIN-HOLE RESET button on the dashboard bezel (using a paperclip or pin) to finish reverting to factory stock.")
                .setCancelable(true)
                .setPositiveButton("OK", null)
                .show();
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
        final String effCar = resolveEffCar(targetSlug);
        final String effBat = resolveEffBat(targetSlug);
        final String effBrand = resolveEffBrand(targetSlug);

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    long t0 = System.currentTimeMillis();
                    StringBuilder mixerLog = new StringBuilder();
                    if (!"default".equals(oemCarOverride)) mixerLog.append(" [Body=").append(formatCarModelLabel(effCar)).append("]");
                    if (!"default".equals(oemBatteryOverride)) mixerLog.append(" [Bat=").append(effBat.toUpperCase()).append("]");
                    if (!"default".equals(oemBrandOverride)) mixerLog.append(" [Bar=").append(effBrand.toUpperCase()).append("]");
                    final String displayThemeName = targetName + mixerLog.toString();

                    appendLog("\n>>> [STEP 1/3] Cleaning previous theme mounts & building '" + displayThemeName + "' in RAM...");

                    CmdResult prepRes = execNemesis("root", "-c", "sh " + HELPER_SH + " DIRECT_PREPARE_STAGE");
                    appendLog("DIRECT_PREPARE_STAGE rc=" + prepRes.rc + (prepRes.out.isEmpty() ? "" : (" (" + prepRes.out + ")")));

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
                    int replacedCount = buildThemedLauncherApk(sourceApk, outApkTmp, "themes/" + targetSlug, effCar, effBat);

                    File outApk = new File(THEMED_APK);
                    if (outApk.exists()) {
                        outApk.delete();
                    }
                    if (!outApkTmp.renameTo(outApk)) {
                        copyFile(outApkTmp, outApk);
                        outApkTmp.delete();
                    }
                    outApk.setReadable(true, false);

                    stagePatchedLauncherOdexForCustomFont(themeHasCustomFont("themes/" + targetSlug));

                    try {
                        File nameFile = new File(ACTIVE_THEME_NAME_FILE);
                        FileOutputStream nFos = new FileOutputStream(nameFile);
                        nFos.write((displayThemeName + "\n").getBytes("UTF-8"));
                        nFos.flush();
                        nFos.close();
                        nameFile.setReadable(true, false);
                    } catch (Exception ignored) {
                    }

                    long elapsed = System.currentTimeMillis() - t0;
                    appendLog("SUCCESS: Patched " + replacedCount + " Launcher resources into "
                            + outApk.getAbsolutePath() + " (" + (outApk.length() / 1024) + " KB) in " + elapsed + " ms.");

                    // Optional Sub-APKs: Status Bar (SystemUI), Climate & Warmer (HKMC_Climate), EV Screen (HKMC_TAppEV3)
                    stageOptionalSubApk("Status Bar (SystemUI)", "sysui", TARGET_SYSUI, STOCK_SYSUI, THEMED_SYSUI, "themes/" + targetSlug + "/systemui", effCar, effBat, effBrand);
                    stageOptionalSubApk("Climate & Warmer (HKMC_Climate)", "climate", TARGET_CLIMATE, STOCK_CLIMATE, THEMED_CLIMATE, "themes/" + targetSlug + "/climate", effCar, effBat, effBrand);
                    stageOptionalSubApk("EV Screen (HKMC_TAppEV3)", "ev", TARGET_EV, STOCK_EV, THEMED_EV, "themes/" + targetSlug + "/ev", effCar, effBat, effBrand);

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

    private String resolveEffCar(String slug) {
        if (!"default".equals(oemCarOverride)) return oemCarOverride;
        if ("oem:ioniq6_sedan".equals(slug)) return "ce_sedan";
        if ("oem:ev_1ttruck".equals(slug)) return "1ttruck";
        return "default";
    }

    private String resolveEffBat(String slug) {
        if (!"default".equals(oemBatteryOverride)) return oemBatteryOverride;
        if ("oem:amber_gold".equals(slug)) return "yellow";
        if ("oem:kia_eco".equals(slug) || "oem:n_sport".equals(slug)) return "red";
        return "default";
    }

    private String resolveEffBrand(String slug) {
        if (!"default".equals(oemBrandOverride)) return oemBrandOverride;
        if ("oem:kia_eco".equals(slug)) return "kia";
        return "default";
    }

    private String resolveOemHomeBatteryEntryName(String name, String effCar, String effBat, ZipFile origZip) {
        int slash = name.lastIndexOf('/');
        if (slash < 0) return null;
        String dir = name.substring(0, slash + 1);
        String file = name.substring(slash + 1);
        if (!file.startsWith("home_etc_battery_") || !file.endsWith(".webp")) return null;
        String tail = file.substring("home_etc_battery_".length(), file.length() - ".webp".length());
        boolean isCeBase = tail.startsWith("ce_sedan_");
        if (isCeBase) {
            tail = tail.substring("ce_sedan_".length());
        }
        // Skip already color-suffixed source entries (_r_XX / _y_XX) or non-two-digit tails
        if (tail.length() != 2 || !Character.isDigit(tail.charAt(0)) || !Character.isDigit(tail.charAt(1))) {
            return null;
        }
        boolean wantCe = "ce_sedan".equals(effCar) || (isCeBase && "default".equals(effCar));
        String colorInfix = "red".equals(effBat) ? "r_" : ("yellow".equals(effBat) ? "y_" : "");
        String candidate = dir + "home_etc_battery_" + (wantCe ? "ce_sedan_" : "") + colorInfix + tail + ".webp";
        if (origZip.getEntry(candidate) != null) return candidate;
        if (wantCe && !colorInfix.isEmpty()) {
            String fallbackColor = dir + "home_etc_battery_" + colorInfix + tail + ".webp";
            if (origZip.getEntry(fallbackColor) != null) return fallbackColor;
        }
        return null;
    }

    private int buildThemedLauncherApk(File sourceApk, File destApk, String assetThemePrefix, String effCar, String effBat) throws Exception {
        AssetManager am = getAssets();
        Set<String> themeEntries = new HashSet<String>();
        InputStream manifestIn = null;
        try {
            manifestIn = am.open(assetThemePrefix + "/manifest.txt");
            BufferedReader br = new BufferedReader(new InputStreamReader(manifestIn, "UTF-8"));
            String line;
            while ((line = br.readLine()) != null) {
                String trimmed = line.trim();
                if (!trimmed.isEmpty() && !trimmed.equals("manifest.txt") && !trimmed.equals("layout-patches.txt") && !trimmed.equals("runtime-composite.txt")) {
                    themeEntries.add(trimmed);
                }
            }
            br.close();
        } catch (Exception ignored) {
        } finally {
            if (manifestIn != null) {
                try { manifestIn.close(); } catch (Exception ignored) {}
            }
        }

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
                            ZipEntry stockSrcEntry = origEntry;
                            if (!"default".equals(effCar) || !"default".equals(effBat)) {
                                String mappedHome = resolveOemHomeBatteryEntryName(name, effCar, effBat, origZip);
                                if (mappedHome != null && origZip.getEntry(mappedHome) != null) {
                                    stockSrcEntry = origZip.getEntry(mappedHome);
                                }
                            }
                            byte[] stockBytes = readStreamBytes(origZip.getInputStream(stockSrcEntry));
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
                    if (name.endsWith(".9.png")) {
                        replacementBytes = ensureCompiledNinePatchChunk(replacementBytes);
                    }
                    writeAlignedStoredEntry(zos, cos, name, replacementBytes);
                    replaced++;
                } else if ((!"default".equals(effCar) || !"default".equals(effBat)) && name.contains("home_etc_battery_") && name.endsWith(".webp")) {
                    String mappedHome = resolveOemHomeBatteryEntryName(name, effCar, effBat, origZip);
                    ZipEntry mappedEntry = (mappedHome != null && !mappedHome.equals(name)) ? origZip.getEntry(mappedHome) : null;
                    if (mappedEntry != null) {
                        byte[] remappedBytes = readStreamBytes(origZip.getInputStream(mappedEntry));
                        writeAlignedStoredEntry(zos, cos, name, remappedBytes);
                        replaced++;
                    } else if (origEntry.getMethod() == ZipEntry.STORED || name.equals("resources.arsc")) {
                        byte[] raw = readStreamBytes(origZip.getInputStream(origEntry));
                        writeAlignedStoredEntry(zos, cos, name, raw);
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
                } else if (transformAvMain && (name.startsWith("res/layout/widget_av_main_") || name.startsWith("res/layout/widget_av_land_")) && name.endsWith(".xml")) {
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

    private void stageOptionalSubApk(String label, String subRole, String targetSystemPath, String stockBackupPath, String themedOutPath, String assetSubPrefix, String effCar, String effBat, String effBrand) {
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
                || "true".equalsIgnoreCase(runtimeCfg.get("scaleOemClimateSeat"))
                || "true".equalsIgnoreCase(runtimeCfg.get("tintOemStatusBar"))
                || "true".equalsIgnoreCase(runtimeCfg.get("tintOemRoad"))
                || ("sysui".equals(subRole) && "kia".equals(effBrand))
                || ("ev".equals(subRole) && (!"default".equals(effCar) || (!"default".equals(effBat) && !"cyan".equals(effBat))));
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
            int count = buildThemedSubApk(sourceApk, outTmp, assetSubPrefix, subRole, entryMap, runtimeCfg, effCar, effBat, effBrand);
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

    private String resolveKiaSysUiEntryName(String name, ZipFile origZip) {
        String candidate = null;
        if (name.startsWith("res/drawable-eco-hdpi/")) {
            candidate = "res/drawable-eco-kia-hdpi/" + name.substring("res/drawable-eco-hdpi/".length());
        } else if (name.startsWith("res/drawable-eco-night-hdpi/")) {
            candidate = "res/drawable-eco-kia-night-hdpi/" + name.substring("res/drawable-eco-night-hdpi/".length());
        } else if (name.startsWith("res/drawable-hdpi/")) {
            candidate = "res/drawable-kia-hdpi/" + name.substring("res/drawable-hdpi/".length());
        } else if (name.startsWith("res/color-eco/")) {
            candidate = "res/color-eco-kia/" + name.substring("res/color-eco/".length());
        } else if (name.startsWith("res/color-eco-night/")) {
            candidate = "res/color-eco-kia-night/" + name.substring("res/color-eco-night/".length());
        } else if (name.startsWith("res/color/")) {
            candidate = "res/color-kia/" + name.substring("res/color/".length());
        }
        if (candidate != null && origZip.getEntry(candidate) != null) {
            return candidate;
        }
        return null;
    }

    private String resolveOemEvEntryName(String name, String effCar, String effBat, ZipFile origZip) {
        String dir = null;
        if (name.startsWith("res/drawable-nodpi/")) {
            dir = "res/drawable-nodpi/";
        } else if (name.startsWith("res/drawable-night-nodpi/")) {
            dir = "res/drawable-night-nodpi/";
        } else {
            return null;
        }
        String file = name.substring(dir.length());
        if (!"default".equals(effCar)) {
            String target = null;
            if (file.equals("ev_ic_battery_bg_nor.webp") || (file.startsWith("ev_ic_battery_bg_") && file.endsWith("_nor.webp"))) {
                target = "ev_ic_battery_bg_" + effCar + "_nor.webp";
            } else if (file.equals("ev_ic_battery_bg_war.webp") || (file.startsWith("ev_ic_battery_bg_") && file.endsWith("_war.webp"))) {
                target = "ev_ic_battery_bg_" + effCar + "_war.webp";
            } else if (file.equals("ev_ic_battery_cover.webp") || (file.startsWith("ev_ic_battery_cover_") && file.endsWith(".webp"))) {
                target = "ev_ic_battery_cover_" + effCar + ".webp";
            }
            if (target != null) {
                if (origZip.getEntry(dir + target) != null) return dir + target;
                if (origZip.getEntry("res/drawable-nodpi/" + target) != null) return "res/drawable-nodpi/" + target;
            }
        }
        if (!"default".equals(effBat) && !"cyan".equals(effBat)) {
            String cShort = "red".equals(effBat) ? "r" : ("yellow".equals(effBat) ? "y" : "");
            String cLong = "red".equals(effBat) ? "red" : ("yellow".equals(effBat) ? "yellow" : "");
            String target = null;
            if (file.startsWith("ev_etc_battery_") && !file.contains("_r_") && !file.contains("_y_") && file.endsWith(".webp")) {
                String rest = file.substring("ev_etc_battery_".length());
                if (rest.startsWith("l_") && rest.length() == 6) {
                    target = "ev_etc_battery_l_" + cShort + "_" + rest.substring(2);
                } else if (rest.startsWith("s_") && rest.length() == 6) {
                    target = "ev_etc_battery_s_" + cShort + "_" + rest.substring(2);
                } else if (rest.length() == 7 && Character.isDigit(rest.charAt(0)) && Character.isDigit(rest.charAt(1))) {
                    target = "ev_etc_battery_" + cShort + "_" + rest;
                }
            } else if (file.startsWith("ev_ic_battery_p_bar_") && !file.contains("_red") && !file.contains("_yellow") && file.endsWith(".webp")) {
                String rest = file.substring("ev_ic_battery_p_bar_".length());
                if (rest.length() == 7 && Character.isDigit(rest.charAt(0)) && Character.isDigit(rest.charAt(1))) {
                    target = "ev_ic_battery_p_bar_" + cLong + "_" + rest;
                }
            }
            if (target != null) {
                if (origZip.getEntry(dir + target) != null) return dir + target;
                if (origZip.getEntry("res/drawable-nodpi/" + target) != null) return "res/drawable-nodpi/" + target;
            }
        }
        return null;
    }

    private int buildThemedSubApk(File sourceApk, File destApk, String assetSubPrefix, String subRole, Map<String, String> entryMap, Map<String, String> runtimeCfg, String effCar, String effBat, String effBrand) throws Exception {
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

        // Top Status Bar transparency patching is unsupported on Gen5W; force opaque/standard OEM handling
        boolean tintOemStatusBar = false;
        int sbBgOpacity = 100;
        int sbBarOpacity = 100;

        boolean tintOemRoad = "true".equalsIgnoreCase(runtimeCfg.get("tintOemRoad"));
        String roadColorHex = runtimeCfg.get("roadColor");
        int roadOpacity = Math.max(0, Math.min(100, Math.round(parseFloatSafe(runtimeCfg.get("roadOpacity"), 100.0f))));

        int replaced = 0;
        ZipFile origZip = new ZipFile(sourceApk);
        boolean patchSysUiStatusBarBg = false;
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
                    if (name.endsWith(".9.png")) {
                        replacementBytes = ensureCompiledNinePatchChunk(replacementBytes);
                    }
                    writeAlignedStoredEntry(zos, cos, name, replacementBytes);
                    replaced++;
                } else if (patchSysUiStatusBarBg && (name.equals("res/layout-long-hdpi/super_status_bar_avn.xml") || name.equals("res/layout-hdpi/super_status_bar_avn.xml"))) {
                    byte[] rawXml = readStreamBytes(origZip.getInputStream(origEntry));
                    byte[] patchedXml = patchSuperStatusBarTransparentBg(rawXml);
                    ZipEntry outEntry = new ZipEntry(name);
                    outEntry.setMethod(ZipEntry.DEFLATED);
                    outEntry.setExtra(null);
                    zos.putNextEntry(outEntry);
                    zos.write(patchedXml);
                    zos.closeEntry();
                    replaced++;
                } else if ("sysui".equals(subRole) && "kia".equals(effBrand) && resolveKiaSysUiEntryName(name, origZip) != null) {
                    String mappedKia = resolveKiaSysUiEntryName(name, origZip);
                    ZipEntry kiaEntry = origZip.getEntry(mappedKia);
                    byte[] kiaBytes = readStreamBytes(origZip.getInputStream(kiaEntry));
                    if (tintOemStatusBar && (name.contains("co_bg_status") || name.endsWith("co_bg_sta_line.png")) && name.endsWith(".png")) {
                        int effAlpha = (sbBgOpacity * sbBarOpacity) / 100;
                        byte[] faded = fadeOemBitmapAlpha(kiaBytes, effAlpha);
                        if (faded != null) kiaBytes = faded;
                    }
                    if (name.endsWith(".xml")) {
                        ZipEntry outEntry = new ZipEntry(name);
                        outEntry.setMethod(ZipEntry.DEFLATED);
                        outEntry.setExtra(null);
                        zos.putNextEntry(outEntry);
                        zos.write(kiaBytes);
                        zos.closeEntry();
                    } else {
                        if (name.endsWith(".9.png")) {
                            kiaBytes = ensureCompiledNinePatchChunk(kiaBytes);
                        }
                        writeAlignedStoredEntry(zos, cos, name, kiaBytes);
                    }
                    replaced++;
                } else if ("sysui".equals(subRole) && tintOemStatusBar && (name.contains("co_bg_status") || name.endsWith("co_bg_sta_line.png")) && name.endsWith(".png")) {
                    byte[] stockBytes = readStreamBytes(origZip.getInputStream(origEntry));
                    int effAlpha = (sbBgOpacity * sbBarOpacity) / 100;
                    byte[] faded = fadeOemBitmapAlpha(stockBytes, effAlpha);
                    byte[] outBytes = faded != null ? faded : stockBytes;
                    if (name.endsWith(".9.png")) {
                        outBytes = ensureCompiledNinePatchChunk(outBytes);
                    }
                    writeAlignedStoredEntry(zos, cos, name, outBytes);
                    replaced++;
                } else if ("ev".equals(subRole) && (!"default".equals(effCar) || (!"default".equals(effBat) && !"cyan".equals(effBat)))
                        && resolveOemEvEntryName(name, effCar, effBat, origZip) != null) {
                    String mappedEv = resolveOemEvEntryName(name, effCar, effBat, origZip);
                    ZipEntry srcEvEntry = (mappedEv != null && !mappedEv.equals(name)) ? origZip.getEntry(mappedEv) : origEntry;
                    byte[] srcBytes = readStreamBytes(origZip.getInputStream(srcEvEntry));
                    if (scaleOemEvCar && (name.contains("ev_ic_battery_bg") || name.contains("ev_ic_battery_cover")) && name.endsWith(".webp")) {
                        byte[] transformed = scaleOffsetOemImage(srcBytes, 450, 255, evCarScale, evCarOffX, evCarOffY, false);
                        if (transformed != null) srcBytes = transformed;
                    }
                    writeAlignedStoredEntry(zos, cos, name, srcBytes);
                    replaced++;
                } else if ("ev".equals(subRole) && tintOemRoad && (name.contains("ev_etc_main_case1_") || name.contains("ev_etc_main_c_case1_") || name.contains("ev_etc_main_case5_loading")) && name.endsWith(".webp")) {
                    byte[] stockBytes = readStreamBytes(origZip.getInputStream(origEntry));
                    byte[] tinted = tintAndFadeOemBitmap(stockBytes, roadColorHex, roadOpacity);
                    writeAlignedStoredEntry(zos, cos, name, tinted != null ? tinted : stockBytes);
                    replaced++;
                } else if (scaleOemEvCar && (name.contains("ev_ic_battery_bg") || name.contains("ev_ic_battery_cover")) && name.endsWith(".webp")) {
                    byte[] stockBytes = readStreamBytes(origZip.getInputStream(origEntry));
                    byte[] transformed = scaleOffsetOemImage(stockBytes, 450, 255, evCarScale, evCarOffX, evCarOffY, false);
                    writeAlignedStoredEntry(zos, cos, name, transformed != null ? transformed : stockBytes);
                    replaced++;
                } else if (scaleOemClimateSeat && name.endsWith("clm_bg_seat.png")) {
                    byte[] stockBytes = readStreamBytes(origZip.getInputStream(origEntry));
                    float clampedSeatOffX = Math.max(-25.0f, Math.min(25.0f, seatOffX));
                    float clampedSeatOffY = Math.max(-25.0f, Math.min(25.0f, seatOffY));
                    byte[] transformed = scaleOffsetOemImage(stockBytes, 309, 351, seatScale, clampedSeatOffX, clampedSeatOffY, true);
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

    private byte[] fadeOemBitmapAlpha(byte[] stockBytes, int opacityPct) {
        Bitmap stockBmp = BitmapFactory.decodeByteArray(stockBytes, 0, stockBytes.length);
        if (stockBmp == null) return null;
        try {
            int w = Math.max(1, stockBmp.getWidth());
            int h = Math.max(1, stockBmp.getHeight());
            Bitmap outBmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Canvas outCanvas = new Canvas(outBmp);
            Paint p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
            int alphaByte = Math.max(0, Math.min(255, Math.round(opacityPct * 2.55f)));
            p.setAlpha(alphaByte);
            outCanvas.drawBitmap(stockBmp, 0f, 0f, p);
            ByteArrayOutputStream baos = new ByteArrayOutputStream(16384);
            outBmp.compress(Bitmap.CompressFormat.PNG, 100, baos);
            outBmp.recycle();
            return baos.toByteArray();
        } finally {
            stockBmp.recycle();
        }
    }

    private byte[] tintAndFadeOemBitmap(byte[] stockBytes, String colorHex, int opacityPct) {
        Bitmap stockBmp = BitmapFactory.decodeByteArray(stockBytes, 0, stockBytes.length);
        if (stockBmp == null) return null;
        try {
            int w = Math.max(1, stockBmp.getWidth());
            int h = Math.max(1, stockBmp.getHeight());
            Bitmap outBmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Canvas outCanvas = new Canvas(outBmp);
            Paint p = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
            float aScale = Math.max(0.0f, Math.min(1.0f, opacityPct / 100.0f));
            boolean customTint = (colorHex != null && !colorHex.trim().isEmpty() && !"#00E5FF".equalsIgnoreCase(colorHex.trim()));
            if (customTint) {
                try {
                    int c = Color.parseColor(colorHex.trim());
                    float tr = Color.red(c) / 255.0f;
                    float tg = Color.green(c) / 255.0f;
                    float tb = Color.blue(c) / 255.0f;
                    ColorMatrix cm = new ColorMatrix(new float[] {
                        0.40f * tr, 0.70f * tr, 0.35f * tr, 0f, 0f,
                        0.40f * tg, 0.70f * tg, 0.35f * tg, 0f, 0f,
                        0.40f * tb, 0.70f * tb, 0.35f * tb, 0f, 0f,
                        0f, 0f, 0f, aScale, 0f
                    });
                    p.setColorFilter(new ColorMatrixColorFilter(cm));
                } catch (Exception ignored) {
                    p.setAlpha(Math.round(aScale * 255.0f));
                }
            } else {
                p.setAlpha(Math.round(aScale * 255.0f));
            }
            outCanvas.drawBitmap(stockBmp, 0f, 0f, p);
            ByteArrayOutputStream baos = new ByteArrayOutputStream(32768);
            if (!outBmp.compress(Bitmap.CompressFormat.WEBP, 100, baos)) {
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

    private static void writeInt32BE(byte[] b, int off, int val) {
        b[off] = (byte) ((val >> 24) & 0xFF);
        b[off + 1] = (byte) ((val >> 16) & 0xFF);
        b[off + 2] = (byte) ((val >> 8) & 0xFF);
        b[off + 3] = (byte) (val & 0xFF);
    }

    private static int readInt32BE(byte[] b, int off) {
        return ((b[off] & 0xFF) << 24)
                | ((b[off + 1] & 0xFF) << 16)
                | ((b[off + 2] & 0xFF) << 8)
                | (b[off + 3] & 0xFF);
    }

    private boolean themeHasCustomFont(String assetThemePrefix) {
        AssetManager am = getAssets();
        try {
            InputStream in = am.open(assetThemePrefix + "/manifest.txt");
            BufferedReader br = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            String line;
            while ((line = br.readLine()) != null) {
                if ("assets/fonts/CubeN.ttf".equals(line.trim())) {
                    br.close();
                    return true;
                }
            }
            br.close();
        } catch (Exception ignored) {
        }
        try {
            InputStream in = am.open(assetThemePrefix + "/runtime-composite.txt");
            BufferedReader br = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            String line;
            while ((line = br.readLine()) != null) {
                if ("hasCustomFont=true".equalsIgnoreCase(line.trim())) {
                    br.close();
                    return true;
                }
            }
            br.close();
        } catch (Exception ignored) {
        }
        return false;
    }

    private void stagePatchedLauncherOdexForCustomFont(boolean enableCustomFont) {
        File outOdex = new File(THEMED_ODEX);
        if (!enableCustomFont) {
            if (outOdex.exists()) outOdex.delete();
            return;
        }
        File stockBackup = new File(STOCK_ODEX);
        File targetOdex = new File(TARGET_ODEX);
        File srcOdex = (stockBackup.exists() && stockBackup.length() > 0) ? stockBackup : targetOdex;
        if (!srcOdex.exists() || srcOdex.length() < 80) {
            appendLog(" - NOTE: Launcher_WP3.odex not found; skipping custom font odex patch.");
            if (outOdex.exists()) outOdex.delete();
            return;
        }
        try {
            FileInputStream odexFis = new FileInputStream(srcOdex);
            byte[] odex = readStreamBytes(odexFis);
            odexFis.close();
            if (odex.length < 80 || odex[0] != 'd' || odex[1] != 'e' || odex[2] != 'y' || odex[3] != '\n') {
                appendLog(" - WARNING: Unexpected ODEX header on Launcher_WP3.odex; skipping font patch.");
                return;
            }
            int dexOff = readInt32LE(odex, 8);
            int dexLen = readInt32LE(odex, 12);
            if (dexOff < 40 || dexLen < 128 || dexOff + dexLen > odex.length) {
                appendLog(" - WARNING: Invalid ODEX bounds (dexOff=" + dexOff + ", dexLen=" + dexLen + "); skipping font patch.");
                return;
            }
            if (odex[dexOff] != 'd' || odex[dexOff + 1] != 'e' || odex[dexOff + 2] != 'x' || odex[dexOff + 3] != '\n') {
                appendLog(" - WARNING: Embedded DEX header mismatch; skipping font patch.");
                return;
            }

            // Locate CustomTextView.init():
            //   71 00 E2 05 00 00   invoke-static {}, Lcom/android/launcher3/utils/n;->dZ()Z
            //   0A 01               move-result v1
            //   38 01 0C 00         if-eqz v1, +12
            //   ... followed shortly by const-string v1, ...
            int patchIdx = -1;
            int searchEnd = dexOff + dexLen - 16;
            for (int i = dexOff + 112; i < searchEnd; i += 2) {
                if ((odex[i] & 0xFF) == 0x71 && (odex[i + 1] & 0xFF) == 0x00
                        && (odex[i + 2] & 0xFF) == 0xE2 && (odex[i + 3] & 0xFF) == 0x05
                        && odex[i + 4] == 0x00 && odex[i + 5] == 0x00
                        && (odex[i + 6] & 0xFF) == 0x0A && (odex[i + 7] & 0xFF) == 0x01
                        && (odex[i + 8] & 0xFF) == 0x38 && (odex[i + 9] & 0xFF) == 0x01) {
                    patchIdx = i + 6;
                    break;
                }
            }
            if (patchIdx < 0) {
                for (int i = dexOff + 112; i < searchEnd; i += 2) {
                    if ((odex[i] & 0xFF) == 0x71 && (odex[i + 1] & 0xFF) == 0x00
                            && odex[i + 4] == 0x00 && odex[i + 5] == 0x00
                            && (odex[i + 6] & 0xFF) == 0x0A && (odex[i + 7] & 0xFF) == 0x01
                            && (odex[i + 8] & 0xFF) == 0x38 && (odex[i + 9] & 0xFF) == 0x01
                            && (odex[i + 10] & 0xFF) == 0x0C && (odex[i + 11] & 0xFF) == 0x00
                            && (odex[i + 12] & 0xFF) == 0x71 && (odex[i + 13] & 0xFF) == 0x00) {
                        patchIdx = i + 6;
                        break;
                    }
                }
            }
            if (patchIdx < 0) {
                appendLog(" - WARNING: Could not locate CustomTextView.init() vendor check in Launcher_WP3.odex.");
                return;
            }

            // Replace `move-result v1` (0A 01) with `const/4 v1, 1` (12 11)
            odex[patchIdx] = 0x12;
            odex[patchIdx + 1] = 0x11;

            // Update DEX Adler32 checksum at dexOff + 8 (over bytes dexOff+12 .. dexOff+dexLen)
            Adler32 adler = new Adler32();
            adler.update(odex, dexOff + 12, dexLen - 12);
            writeInt32LE(odex, dexOff + 8, (int) adler.getValue());

            File tmpOdex = new File(THEMED_ODEX + ".tmp");
            FileOutputStream fos = new FileOutputStream(tmpOdex);
            fos.write(odex);
            fos.flush();
            fos.close();
            if (outOdex.exists()) outOdex.delete();
            if (!tmpOdex.renameTo(outOdex)) {
                copyFile(tmpOdex, outOdex);
                tmpOdex.delete();
            }
            outOdex.setReadable(true, false);
            outOdex.setWritable(true, false);
            appendLog(" - Custom Font Unlock: Patched Launcher_WP3.odex at +" + patchIdx + " (" + (outOdex.length() / 1024) + " KB)");
        } catch (Exception e) {
            appendLog(" - WARNING: Failed to patch Launcher_WP3.odex for custom font: " + e.toString());
            if (outOdex.exists()) outOdex.delete();
        }
    }

    private static byte[] ensureCompiledNinePatchChunk(byte[] pngBytes) {
        if (pngBytes == null || pngBytes.length < 33) return pngBytes;
        if ((pngBytes[0] & 0xFF) != 0x89 || pngBytes[1] != 'P' || pngBytes[2] != 'N' || pngBytes[3] != 'G') {
            return pngBytes;
        }
        int pos = 8;
        int ihdrEnd = -1;
        int width = 0;
        int height = 0;
        while (pos + 12 <= pngBytes.length) {
            int len = readInt32BE(pngBytes, pos);
            if (len < 0 || pos + 12 + len > pngBytes.length) break;
            if (pngBytes[pos + 4] == 'n' && pngBytes[pos + 5] == 'p'
                    && pngBytes[pos + 6] == 'T' && pngBytes[pos + 7] == 'c') {
                return pngBytes; // Already compiled 9-patch
            }
            if (pngBytes[pos + 4] == 'I' && pngBytes[pos + 5] == 'H'
                    && pngBytes[pos + 6] == 'D' && pngBytes[pos + 7] == 'R' && len >= 8) {
                width = readInt32BE(pngBytes, pos + 8);
                height = readInt32BE(pngBytes, pos + 12);
                ihdrEnd = pos + 12 + len;
            }
            pos += 12 + len;
        }
        if (ihdrEnd < 33 || width <= 0 || height <= 0) return pngBytes;

        byte[] npTc = new byte[84];
        npTc[0] = 0; // wasDeserialized = 0
        npTc[1] = 2; // numXDivs = 2
        npTc[2] = 2; // numYDivs = 2
        npTc[3] = 9; // numColors = 9
        writeInt32BE(npTc, 4, 32);  // xDivsOffset
        writeInt32BE(npTc, 8, 40);  // yDivsOffset
        writeInt32BE(npTc, 28, 48); // colorsOffset
        writeInt32BE(npTc, 32, 1);
        writeInt32BE(npTc, 36, Math.max(2, width - 1));
        writeInt32BE(npTc, 40, 1);
        writeInt32BE(npTc, 44, Math.max(2, height - 1));
        for (int ci = 0; ci < 9; ci++) {
            writeInt32BE(npTc, 48 + ci * 4, 0x00000001); // NO_COLOR
        }

        byte[] chunkType = new byte[] { 'n', 'p', 'T', 'c' };
        CRC32 crc = new CRC32();
        crc.update(chunkType);
        crc.update(npTc);

        byte[] out = new byte[pngBytes.length + 12 + npTc.length];
        System.arraycopy(pngBytes, 0, out, 0, ihdrEnd);
        writeInt32BE(out, ihdrEnd, npTc.length);
        System.arraycopy(chunkType, 0, out, ihdrEnd + 4, 4);
        System.arraycopy(npTc, 0, out, ihdrEnd + 8, npTc.length);
        writeInt32BE(out, ihdrEnd + 8 + npTc.length, (int) crc.getValue());
        System.arraycopy(pngBytes, ihdrEnd, out, ihdrEnd + 12 + npTc.length, pngBytes.length - ihdrEnd);
        return out;
    }

    private static byte[] patchSuperStatusBarTransparentBg(byte[] rawXml) {
        if (rawXml == null || rawXml.length < 64) return rawXml;
        try {
            byte[] xml = new byte[rawXml.length];
            System.arraycopy(rawXml, 0, xml, 0, rawXml.length);
            if (readUInt16LE(xml, 0) != 0x0003) return rawXml;
            int strPoolOff = 8;
            if (readUInt16LE(xml, strPoolOff) != 0x0001) return rawXml;
            int strPoolSize = readInt32LE(xml, strPoolOff + 4);
            int resMapOff = strPoolOff + strPoolSize;
            if (resMapOff + 8 > xml.length || readUInt16LE(xml, resMapOff) != 0x0180) return rawXml;
            int resMapSize = readInt32LE(xml, resMapOff + 4);
            int resMapCount = (resMapSize - 8) / 4;

            int pos = resMapOff + resMapSize;
            while (pos + 8 <= xml.length) {
                int cType = readUInt16LE(xml, pos);
                int cSize = readInt32LE(xml, pos + 4);
                if (cSize <= 0 || pos + cSize > xml.length) break;
                if (cType == 0x0102) { // First START_ELEMENT (<AvnStatusBarWindowView>)
                    int attrCount = readUInt16LE(xml, pos + 28);
                    for (int ai = 0; ai < attrCount; ai++) {
                        int aOff = pos + 36 + ai * 20;
                        if (aOff + 20 > pos + cSize) break;
                        int nameIdx = readInt32LE(xml, aOff + 4);
                        int resId = (nameIdx >= 0 && nameIdx < resMapCount)
                                ? readInt32LE(xml, resMapOff + 8 + nameIdx * 4) : 0;
                        if (resId == 0x010100D4) { // android:background
                            writeInt32LE(xml, aOff + 8, -1); // rawVal = -1
                            xml[aOff + 14] = 0;
                            xml[aOff + 15] = 0x1C; // TYPE_COLOR_ARGB8
                            writeInt32LE(xml, aOff + 16, 0x00000000); // transparent
                            return xml;
                        }
                    }
                    break;
                }
                pos += cSize;
            }
        } catch (Exception ignored) {
        }
        return rawXml;
    }

    private static void shiftStringIndexIfGe(byte[] xml, int off, int threshold, int delta) {
        int val = readInt32LE(xml, off);
        if (val >= threshold) {
            writeInt32LE(xml, off, val + delta);
        }
    }

    private byte[] transformAvMainLayoutXml(byte[] rawXml, int offXDp, int offYDp, float scalePct) {
        if (rawXml == null || rawXml.length < 64) return rawXml;
        try {
            byte[] work = new byte[rawXml.length];
            System.arraycopy(rawXml, 0, work, 0, rawXml.length);

            if (readUInt16LE(work, 0) != 0x0003) return rawXml;
            int strPoolOff = 8;
            if (readUInt16LE(work, strPoolOff) != 0x0001) return rawXml;
            int strPoolSize = readInt32LE(work, strPoolOff + 4);
            int strCount = readInt32LE(work, strPoolOff + 8);
            int stringsStart = readInt32LE(work, strPoolOff + 20);
            int stylesStart = readInt32LE(work, strPoolOff + 24);

            int resMapOff = strPoolOff + strPoolSize;
            if (resMapOff + 8 > work.length || readUInt16LE(work, resMapOff) != 0x0180) return rawXml;
            int resMapSize = readInt32LE(work, resMapOff + 4);
            int resMapCount = (resMapSize - 8) / 4;

            // 1. Scale textSize (0x01010095) and fixed text row layout_height (0x010100F5) across all elements
            int firstStartElemOff = -1;
            int pos = resMapOff + resMapSize;
            float sFactor = (scalePct > 0f ? scalePct : 100f) / 100.0f;
            while (pos + 8 <= work.length) {
                int cType = readUInt16LE(work, pos);
                int cSize = readInt32LE(work, pos + 4);
                if (cSize <= 0 || pos + cSize > work.length) break;
                if (cType == 0x0102) {
                    if (firstStartElemOff < 0) firstStartElemOff = pos;
                    if (Math.abs(scalePct - 100.0f) > 0.5f) {
                        int attrCount = readUInt16LE(work, pos + 28);
                        int aBase = pos + 36;
                        for (int ai = 0; ai < attrCount; ai++) {
                            int aOff = aBase + ai * 20;
                            if (aOff + 20 > pos + cSize) break;
                            int nameIdx = readInt32LE(work, aOff + 4);
                            int resId = (nameIdx >= 0 && nameIdx < resMapCount)
                                    ? readInt32LE(work, resMapOff + 8 + nameIdx * 4) : 0;
                            int dType = work[aOff + 15] & 0xFF;
                            int data = readInt32LE(work, aOff + 16);
                            if (resId == 0x01010095) { // android:textSize
                                if (dType == 5) {
                                    int unit = data & 0x0F;
                                    int baseVal = data >> 8;
                                    int newVal = Math.max(8, Math.round(baseVal * sFactor));
                                    writeInt32LE(work, aOff + 16, ((newVal & 0xFFFFFF) << 8) | unit);
                                } else if (dType == 1) {
                                    int newSp = Math.max(8, Math.round(22.0f * sFactor));
                                    work[aOff + 15] = 5;
                                    writeInt32LE(work, aOff + 16, ((newSp & 0xFFFFFF) << 8) | 2);
                                }
                            } else if (resId == 0x010100F5 && sFactor > 1.0f && dType == 5) { // android:layout_height
                                int unit = data & 0x0F;
                                int baseVal = data >> 8;
                                if (baseVal >= 18 && baseVal <= 120) {
                                    int newVal = Math.round(baseVal * sFactor);
                                    writeInt32LE(work, aOff + 16, ((newVal & 0xFFFFFF) << 8) | unit);
                                }
                            }
                        }
                    }
                }
                pos += cSize;
            }

            // 2. Inject android:translationX (0x01010320) & android:translationY (0x01010321) into root StartElement
            // IMPORTANT: Insert 2 string slots into StringPool at index resMapCount AND shift all string indices >= resMapCount by +2!
            if ((offXDp != 0 || offYDp != 0) && firstStartElemOff > 0 && strCount >= resMapCount && stringsStart >= 28 + strCount * 4) {
                int rootAttrCount = readUInt16LE(work, firstStartElemOff + 28);
                if (rootAttrCount > 0) {
                    int insIdx = rootAttrCount;
                    for (int ai = 0; ai < rootAttrCount; ai++) {
                        int aOff = firstStartElemOff + 36 + ai * 20;
                        int nameIdx = readInt32LE(work, aOff + 4);
                        int resId = (nameIdx >= 0 && nameIdx < resMapCount)
                                ? readInt32LE(work, resMapOff + 8 + nameIdx * 4) : 0x7FFFFFFF;
                        if (resId > 0x01010320) {
                            insIdx = ai;
                            break;
                        }
                    }

                    // Shift all XML string indices >= resMapCount by +2 across chunks following ResourceMap
                    pos = resMapOff + resMapSize;
                    while (pos + 8 <= work.length) {
                        int cType = readUInt16LE(work, pos);
                        int cSize = readInt32LE(work, pos + 4);
                        if (cSize <= 0 || pos + cSize > work.length) break;
                        shiftStringIndexIfGe(work, pos + 12, resMapCount, 2); // header.comment
                        if (cType == 0x0100 || cType == 0x0101) { // START_NAMESPACE / END_NAMESPACE
                            shiftStringIndexIfGe(work, pos + 16, resMapCount, 2); // prefix
                            shiftStringIndexIfGe(work, pos + 20, resMapCount, 2); // uri
                        } else if (cType == 0x0102) { // START_ELEMENT
                            shiftStringIndexIfGe(work, pos + 16, resMapCount, 2); // ns
                            shiftStringIndexIfGe(work, pos + 20, resMapCount, 2); // name
                            int ac = readUInt16LE(work, pos + 28);
                            for (int ai = 0; ai < ac; ai++) {
                                int aOff = pos + 36 + ai * 20;
                                if (aOff + 20 > pos + cSize) break;
                                shiftStringIndexIfGe(work, aOff, resMapCount, 2);     // attr.ns
                                shiftStringIndexIfGe(work, aOff + 4, resMapCount, 2); // attr.name
                                shiftStringIndexIfGe(work, aOff + 8, resMapCount, 2); // attr.rawValue
                                if ((work[aOff + 15] & 0xFF) == 3) { // TYPE_STRING
                                    shiftStringIndexIfGe(work, aOff + 16, resMapCount, 2);
                                }
                            }
                        } else if (cType == 0x0103) { // END_ELEMENT
                            shiftStringIndexIfGe(work, pos + 16, resMapCount, 2); // ns
                            shiftStringIndexIfGe(work, pos + 20, resMapCount, 2); // name
                        } else if (cType == 0x0104) { // CDATA
                            shiftStringIndexIfGe(work, pos + 16, resMapCount, 2); // data
                        }
                        pos += cSize;
                    }

                    // Find an attribute in root with valid android namespace index (now shifted by +2)
                    int nsIdx = -1;
                    for (int ai = 0; ai < rootAttrCount; ai++) {
                        int candNs = readInt32LE(work, firstStartElemOff + 36 + ai * 20);
                        if (candNs >= 0) {
                            nsIdx = candNs;
                            break;
                        }
                    }

                    int strOffsetInsertPos = strPoolOff + 28 + resMapCount * 4;
                    int resMapInsertPos = resMapOff + resMapSize;
                    int attrInsertPos = firstStartElemOff + 36 + insIdx * 20;
                    byte[] out = new byte[work.length + 56];

                    // Part 1: Before StringPool[resMapCount] offset slot
                    System.arraycopy(work, 0, out, 0, strOffsetInsertPos);
                    // Insert 2 uint32 string offsets (+8 bytes, both pointing to offset 0 in string pool)
                    writeInt32LE(out, strOffsetInsertPos, 0);
                    writeInt32LE(out, strOffsetInsertPos + 4, 0);

                    // Part 2: Remainder of StringPool + ResourceMap (+8 shift)
                    System.arraycopy(work, strOffsetInsertPos, out, strOffsetInsertPos + 8, resMapInsertPos - strOffsetInsertPos);
                    // Append 0x01010320 (translationX) and 0x01010321 (translationY) to ResourceMap (+8 bytes -> total +16)
                    writeInt32LE(out, resMapInsertPos + 8, 0x01010320);
                    writeInt32LE(out, resMapInsertPos + 12, 0x01010321);

                    // Part 3: From end of ResourceMap up to attribute insertion point (+16 shift)
                    System.arraycopy(work, resMapInsertPos, out, resMapInsertPos + 16, attrInsertPos - resMapInsertPos);

                    // Write two 20-byte ResXMLTree_attribute structs (+40 bytes -> total +56)
                    int newAttrPos = attrInsertPos + 16;
                    writeInt32LE(out, newAttrPos, nsIdx);
                    writeInt32LE(out, newAttrPos + 4, resMapCount);
                    writeInt32LE(out, newAttrPos + 8, -1);
                    writeUInt16LE(out, newAttrPos + 12, 8);
                    out[newAttrPos + 14] = 0;
                    out[newAttrPos + 15] = 5; // TYPE_DIMENSION (dp)
                    writeInt32LE(out, newAttrPos + 16, ((offXDp & 0xFFFFFF) << 8) | 1);

                    writeInt32LE(out, newAttrPos + 20, nsIdx);
                    writeInt32LE(out, newAttrPos + 24, resMapCount + 1);
                    writeInt32LE(out, newAttrPos + 28, -1);
                    writeUInt16LE(out, newAttrPos + 32, 8);
                    out[newAttrPos + 34] = 0;
                    out[newAttrPos + 35] = 5; // TYPE_DIMENSION (dp)
                    writeInt32LE(out, newAttrPos + 36, ((offYDp & 0xFFFFFF) << 8) | 1);

                    // Part 4: Remainder of XML (+56 shift)
                    System.arraycopy(work, attrInsertPos, out, newAttrPos + 40, work.length - attrInsertPos);

                    // Update chunk headers
                    writeInt32LE(out, 4, work.length + 56);
                    writeInt32LE(out, strPoolOff + 4, strPoolSize + 8);
                    writeInt32LE(out, strPoolOff + 8, strCount + 2);
                    writeInt32LE(out, strPoolOff + 20, stringsStart + 8);
                    if (stylesStart > 0) {
                        writeInt32LE(out, strPoolOff + 24, stylesStart + 8);
                    }
                    writeInt32LE(out, resMapOff + 8 + 4, resMapSize + 8);
                    int newRootOff = firstStartElemOff + 16;
                    int oldRootSize = readInt32LE(out, newRootOff + 4);
                    writeInt32LE(out, newRootOff + 4, oldRootSize + 40);
                    writeUInt16LE(out, newRootOff + 28, rootAttrCount + 2);
                    for (int idxOff = 30; idxOff <= 34; idxOff += 2) {
                        int idx1 = readUInt16LE(out, newRootOff + idxOff);
                        if (idx1 > insIdx) {
                            writeUInt16LE(out, newRootOff + idxOff, idx1 + 2);
                        }
                    }
                    return out;
                }
            }
            return work;
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
                    sb.append("OEM Variants Detected     : ").append(oemScanSummary.isEmpty() ? "None" : oemScanSummary).append("\n");
                    sb.append("OEM Mixer Overrides       : car=").append(oemCarOverride)
                            .append(", bat=").append(oemBatteryOverride)
                            .append(", brand=").append(oemBrandOverride).append("\n");
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
