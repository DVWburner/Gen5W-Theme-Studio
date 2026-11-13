#!/system/bin/sh
# Gen5W Themer Root Helper Service (NEMESIS service.0, uid=root)
# Supports Launcher_WP3.apk, SystemUI.apk, HKMC_Climate.apk, and HKMC_TAppEV3.apk
# Includes Auto-Boot on Reboot + 5-Layer Failsafe (USB Kill-Switch, Pinhole 2-Strike Breaker,
# 6s Boot Grace Window, 60s Launcher Crash Watchdog, and 45s Deadman Test Timer).
# Strict Gen5W toolbox + mksh compatibility (NO busybox, tr, awk, killall, pkill, or umount -l).

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

WORK_DIR="/mnt/asec/gen5w_themer"
CMD_FILE="$WORK_DIR/cmd"
STATUS_FILE="$WORK_DIR/status"
COUNTDOWN_FILE="$WORK_DIR/countdown"
ACTIVE_FILE="$WORK_DIR/active_state"
ACTIVE_THEME_NAME_FILE="$WORK_DIR/active_theme_name"
AUTOSTART_STATE_FILE="$WORK_DIR/autostart_state"
LOG_FILE="$WORK_DIR/helper.log"

PERSIST_DIR="/data/data/com.gen5w.themer/autostart"
AUTOSTART_ENABLED_FILE="$PERSIST_DIR/enabled"
AUTOSTART_STRIKES_FILE="$PERSIST_DIR/boot_strikes"
AUTOSTART_THEME_FILE="$PERSIST_DIR/theme_name"

THEMED_APK="$WORK_DIR/Launcher_WP3_themed.apk"
STOCK_APK="$WORK_DIR/Launcher_WP3_stock.apk"
TARGET_APK="/system/app/Launcher_WP3.apk"

THEMED_ODEX="$WORK_DIR/Launcher_WP3_themed.odex"
STOCK_ODEX="$WORK_DIR/Launcher_WP3_stock.odex"
TARGET_ODEX="/system/app/Launcher_WP3.odex"
PERSIST_ODEX="$PERSIST_DIR/Launcher_WP3_themed.odex"

THEMED_SYSUI="$WORK_DIR/SystemUI_themed.apk"
STOCK_SYSUI="$WORK_DIR/SystemUI_stock.apk"
TARGET_SYSUI="/system/priv-app/SystemUI.apk"

THEMED_CLIMATE="$WORK_DIR/HKMC_Climate_themed.apk"
STOCK_CLIMATE="$WORK_DIR/HKMC_Climate_stock.apk"
TARGET_CLIMATE="/system/app/HKMC_Climate.apk"

THEMED_EV="$WORK_DIR/HKMC_TAppEV3_themed.apk"
STOCK_EV="$WORK_DIR/HKMC_TAppEV3_stock.apk"
TARGET_EV="/system/app/HKMC_TAppEV3.apk"

mkdir -p "$WORK_DIR" 2>/dev/null
chmod 777 "$WORK_DIR" 2>/dev/null
mkdir -p "$PERSIST_DIR" 2>/dev/null
chmod 777 "/data/data/com.gen5w.themer" 2>/dev/null
chmod 777 "$PERSIST_DIR" 2>/dev/null

log_msg() {
    local line="[$(date)] [HELPER] $1"
    echo "$line" >> "$LOG_FILE" 2>/dev/null
    chmod 666 "$LOG_FILE" 2>/dev/null
}

set_status() {
    echo "$1" > "$STATUS_FILE"
    chmod 666 "$STATUS_FILE" 2>/dev/null
}

set_countdown() {
    echo "$1" > "$COUNTDOWN_FILE"
    chmod 666 "$COUNTDOWN_FILE" 2>/dev/null
}

set_active_state() {
    echo "$1" > "$ACTIVE_FILE"
    chmod 666 "$ACTIVE_FILE" 2>/dev/null
}

set_autostart_state() {
    echo "$1" > "$AUTOSTART_STATE_FILE"
    chmod 666 "$AUTOSTART_STATE_FILE" 2>/dev/null
}

is_autostart_enabled() {
    if [ -f "$AUTOSTART_ENABLED_FILE" ]; then
        local val=""
        read -r val < "$AUTOSTART_ENABLED_FILE" 2>/dev/null
        if [ "$val" = "1" ]; then
            return 0
        fi
    fi
    return 1
}

sync_autostart_state_file() {
    if is_autostart_enabled; then
        local tname="Custom Theme"
        if [ -f "$AUTOSTART_THEME_FILE" ]; then
            read -r tname < "$AUTOSTART_THEME_FILE" 2>/dev/null
        fi
        set_autostart_state "ENABLED|$tname"
    elif [ ! -f "$AUTOSTART_STATE_FILE" ]; then
        set_autostart_state "DISABLED"
    fi
}

is_path_mounted() {
    grep -q "$1" /proc/mounts 2>/dev/null
    return $?
}

is_mounted() {
    is_path_mounted "$TARGET_APK" || is_path_mounted "$TARGET_ODEX" || is_path_mounted "$TARGET_SYSUI" || is_path_mounted "$TARGET_CLIMATE" || is_path_mounted "$TARGET_EV"
    return $?
}

get_launcher_pid() {
    ps | while read user pid ppid vsize rss wchan pc state name rest; do
        case "$name" in
            *com.android.launcher3*)
                echo "$pid"
                return 0
                ;;
        esac
    done
}

kill_proc_pattern() {
    local pat="$1"
    ps | while read user pid ppid vsize rss wchan pc state name rest; do
        case "$name" in
            *$pat*)
                log_msg "Killing $name (pid=$pid)"
                kill -9 "$pid" 2>/dev/null
                ;;
        esac
    done
}

kill_launcher() {
    kill_proc_pattern "com.android.launcher3"
}

unmount_single_target() {
    local target_path="$1"
    local stock_copy="$2"
    local proc_pat="$3"
    local pkg_name="$4"

    if ! is_path_mounted "$target_path"; then
        return 0
    fi

    if [ -n "$pkg_name" ]; then
        /system/bin/am force-stop "$pkg_name" >/dev/null 2>&1
    fi
    kill_proc_pattern "$proc_pat"
    sleep 1
    local tries=0
    while is_path_mounted "$target_path" && [ $tries -lt 5 ]; do
        /system/bin/toolbox umount "$target_path" >> "$LOG_FILE" 2>&1 || umount "$target_path" >> "$LOG_FILE" 2>&1
        if ! is_path_mounted "$target_path"; then
            log_msg "Unmounted $target_path cleanly."
            kill_proc_pattern "$proc_pat"
            return 0
        fi
        if [ -n "$pkg_name" ]; then
            /system/bin/am force-stop "$pkg_name" >/dev/null 2>&1
        fi
        kill_proc_pattern "$proc_pat"
        tries=$((tries + 1))
        sleep 1
    done

    if is_path_mounted "$target_path" && [ -s "$stock_copy" ]; then
        log_msg "Mount busy; bind-mounting clean stock copy ($stock_copy) on top of $target_path..."
        chmod 666 "$stock_copy" 2>/dev/null
        chown 0.0 "$stock_copy" 2>/dev/null || chown 0:0 "$stock_copy" 2>/dev/null
        /system/bin/toolbox mount -o bind "$stock_copy" "$target_path" >> "$LOG_FILE" 2>&1 || mount -o bind "$stock_copy" "$target_path" >> "$LOG_FILE" 2>&1
        kill_proc_pattern "$proc_pat"
        return 0
    fi
    return 1
}

mount_single_target() {
    local themed_copy="$1"
    local stock_copy="$2"
    local target_path="$3"
    local proc_pat="$4"
    local pkg_name="$5"

    if [ ! -f "$target_path" ]; then
        log_msg "Target $target_path not present on this vehicle; skipping."
        return 0
    fi

    if is_path_mounted "$target_path"; then
        log_msg "$target_path already mounted; unmounting previous theme first..."
        unmount_single_target "$target_path" "$stock_copy" "$proc_pat" "$pkg_name"
    fi

    if [ ! -s "$themed_copy" ]; then
        return 0
    fi

    if [ ! -s "$stock_copy" ] && ! is_path_mounted "$target_path"; then
        log_msg "Saving clean stock reference copy to $stock_copy..."
        cp -f "$target_path" "$stock_copy" 2>/dev/null
    fi
    if [ -s "$stock_copy" ]; then
        chmod 666 "$stock_copy" 2>/dev/null
        chown 0.0 "$stock_copy" 2>/dev/null || chown 0:0 "$stock_copy" 2>/dev/null
    fi

    chown 0.0 "$themed_copy" 2>/dev/null || chown 0:0 "$themed_copy" 2>/dev/null
    chmod 666 "$themed_copy" 2>/dev/null

    log_msg "Running: toolbox mount -o bind $themed_copy $target_path"
    /system/bin/toolbox mount -o bind "$themed_copy" "$target_path" >> "$LOG_FILE" 2>&1 || mount -o bind "$themed_copy" "$target_path" >> "$LOG_FILE" 2>&1

    if is_path_mounted "$target_path"; then
        log_msg "Mounted $target_path; restarting $proc_pat..."
        if [ -n "$pkg_name" ]; then
            /system/bin/am force-stop "$pkg_name" >/dev/null 2>&1
        fi
        kill_proc_pattern "$proc_pat"
        return 0
    else
        log_msg "ERROR: Failed to bind-mount $target_path"
        return 1
    fi
}

do_disable_autostart() {
    local reason="$1"
    if [ -z "$reason" ]; then
        reason="DISABLED"
    fi
    rm -f "$AUTOSTART_ENABLED_FILE" 2>/dev/null
    rm -f "$PERSIST_DIR/Launcher_WP3_themed.apk" 2>/dev/null
    rm -f "$PERSIST_ODEX" 2>/dev/null
    rm -f "$PERSIST_DIR/SystemUI_themed.apk" 2>/dev/null
    rm -f "$PERSIST_DIR/HKMC_Climate_themed.apk" 2>/dev/null
    rm -f "$PERSIST_DIR/HKMC_TAppEV3_themed.apk" 2>/dev/null
    echo "0" > "$AUTOSTART_STRIKES_FILE" 2>/dev/null
    chmod 666 "$AUTOSTART_STRIKES_FILE" 2>/dev/null
    set_autostart_state "$reason"
    sync
    log_msg "Auto-Boot disabled (state=$reason)."
}

do_enable_autostart() {
    if ! is_path_mounted "$TARGET_APK" || [ ! -s "$THEMED_APK" ]; then
        log_msg "ERROR: Cannot enable Auto-Boot when no confirmed theme is mounted."
        set_status "ERROR: Apply & Confirm a theme before enabling Auto-Boot"
        return 1
    fi
    local cur_cd="0"
    if [ -f "$COUNTDOWN_FILE" ]; then
        read -r cur_cd < "$COUNTDOWN_FILE" 2>/dev/null
    fi
    if [ -n "$cur_cd" ] && [ "$cur_cd" != "0" ]; then
        log_msg "ERROR: Cannot enable Auto-Boot while 45s test countdown is still running ($cur_cd s left)."
        set_status "ERROR: Confirm the theme first before enabling Auto-Boot"
        return 1
    fi

    mkdir -p "$PERSIST_DIR" 2>/dev/null
    chmod 777 "/data/data/com.gen5w.themer" 2>/dev/null
    chmod 777 "$PERSIST_DIR" 2>/dev/null

    rm -f "$PERSIST_DIR/Launcher_WP3_themed.apk" "$PERSIST_ODEX" "$PERSIST_DIR/SystemUI_themed.apk" "$PERSIST_DIR/HKMC_Climate_themed.apk" "$PERSIST_DIR/HKMC_TAppEV3_themed.apk" 2>/dev/null

    log_msg "Caching confirmed themed APKs into $PERSIST_DIR for Auto-Boot..."
    cp -f "$THEMED_APK" "$PERSIST_DIR/Launcher_WP3_themed.apk" 2>/dev/null
    if [ ! -s "$PERSIST_DIR/Launcher_WP3_themed.apk" ]; then
        log_msg "ERROR: Failed to copy $THEMED_APK to $PERSIST_DIR"
        set_status "ERROR: Could not write Auto-Boot cache to /data"
        return 1
    fi
    chmod 644 "$PERSIST_DIR/Launcher_WP3_themed.apk" 2>/dev/null

    if [ -s "$THEMED_ODEX" ]; then
        cp -f "$THEMED_ODEX" "$PERSIST_ODEX" 2>/dev/null
        chmod 644 "$PERSIST_ODEX" 2>/dev/null
    fi
    if [ -s "$THEMED_SYSUI" ]; then
        cp -f "$THEMED_SYSUI" "$PERSIST_DIR/SystemUI_themed.apk" 2>/dev/null
        chmod 644 "$PERSIST_DIR/SystemUI_themed.apk" 2>/dev/null
    fi
    if [ -s "$THEMED_CLIMATE" ]; then
        cp -f "$THEMED_CLIMATE" "$PERSIST_DIR/HKMC_Climate_themed.apk" 2>/dev/null
        chmod 644 "$PERSIST_DIR/HKMC_Climate_themed.apk" 2>/dev/null
    fi
    if [ -s "$THEMED_EV" ]; then
        cp -f "$THEMED_EV" "$PERSIST_DIR/HKMC_TAppEV3_themed.apk" 2>/dev/null
        chmod 644 "$PERSIST_DIR/HKMC_TAppEV3_themed.apk" 2>/dev/null
    fi

    local tname="Custom Theme"
    if [ -f "$ACTIVE_THEME_NAME_FILE" ]; then
        read -r tname < "$ACTIVE_THEME_NAME_FILE" 2>/dev/null
    fi
    echo "$tname" > "$AUTOSTART_THEME_FILE" 2>/dev/null
    chmod 666 "$AUTOSTART_THEME_FILE" 2>/dev/null

    echo "0" > "$AUTOSTART_STRIKES_FILE" 2>/dev/null
    chmod 666 "$AUTOSTART_STRIKES_FILE" 2>/dev/null
    echo "1" > "$AUTOSTART_ENABLED_FILE" 2>/dev/null
    chmod 666 "$AUTOSTART_ENABLED_FILE" 2>/dev/null
    sync

    set_autostart_state "ENABLED|$tname"
    set_status "CONFIRMED (Auto-Boot ON for '$tname')"
    log_msg "SUCCESS: Auto-Boot enabled for '$tname'!"
    return 0
}

do_backup_stock_if_clean() {
    local target_path="$1"
    local stock_copy="$2"
    if [ -f "$target_path" ] && ! is_path_mounted "$target_path"; then
        if [ ! -s "$stock_copy" ]; then
            cp -f "$target_path" "$stock_copy" 2>/dev/null
        fi
        if [ -s "$stock_copy" ]; then
            chmod 666 "$stock_copy" 2>/dev/null
        fi
    fi
}

do_prepare_stage() {
    mkdir -p "$WORK_DIR" 2>/dev/null
    chmod 777 "$WORK_DIR" 2>/dev/null
    log_msg "Preparing clean staging area (unmounting active mounts first)..."
    set_countdown "0"

    unmount_single_target "$TARGET_EV" "$STOCK_EV" "daudio.app.ev" "com.hkmc.daudio.app.ev3"
    unmount_single_target "$TARGET_CLIMATE" "$STOCK_CLIMATE" "HKMC_Climate|apps.climate" "com.hkmc.telematics.service.apps.climate"
    unmount_single_target "$TARGET_SYSUI" "$STOCK_SYSUI" "com.android.systemui" ""
    unmount_single_target "$TARGET_ODEX" "$STOCK_ODEX" "com.android.launcher3" "com.android.launcher3"
    unmount_single_target "$TARGET_APK" "$STOCK_APK" "com.android.launcher3" "com.android.launcher3"

    do_backup_stock_if_clean "$TARGET_APK" "$STOCK_APK"
    do_backup_stock_if_clean "$TARGET_ODEX" "$STOCK_ODEX"
    do_backup_stock_if_clean "$TARGET_SYSUI" "$STOCK_SYSUI"
    do_backup_stock_if_clean "$TARGET_CLIMATE" "$STOCK_CLIMATE"
    do_backup_stock_if_clean "$TARGET_EV" "$STOCK_EV"

    rm -f "$THEMED_APK" "$THEMED_ODEX" "$THEMED_SYSUI" "$THEMED_CLIMATE" "$THEMED_EV" 2>/dev/null
    chmod 777 "$WORK_DIR" 2>/dev/null
    set_active_state "STOCK"
    log_msg "Stage prepared cleanly (all targets unmounted, stock backed up, old themed files removed)"
    return 0
}

do_revert_mounts_only() {
    log_msg "Reverting all themed APKs to factory stock OEM..."
    set_countdown "0"
    set_active_state "STOCK"
    unmount_single_target "$TARGET_EV" "$STOCK_EV" "daudio.app.ev" "com.hkmc.daudio.app.ev3"
    unmount_single_target "$TARGET_CLIMATE" "$STOCK_CLIMATE" "HKMC_Climate|apps.climate" "com.hkmc.telematics.service.apps.climate"
    unmount_single_target "$TARGET_SYSUI" "$STOCK_SYSUI" "com.android.systemui" ""
    unmount_single_target "$TARGET_ODEX" "$STOCK_ODEX" "com.android.launcher3" "com.android.launcher3"
    unmount_single_target "$TARGET_APK" "$STOCK_APK" "com.android.launcher3" "com.android.launcher3"
    rm -f "$THEMED_APK" "$THEMED_ODEX" "$THEMED_SYSUI" "$THEMED_CLIMATE" "$THEMED_EV" 2>/dev/null
    kill_launcher
    sleep 1
    am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
}

do_revert() {
    do_disable_autostart "DISABLED"
    do_revert_mounts_only
    set_status "STOCK (Factory Unmodified)"
    log_msg "Reverted to stock and disarmed Auto-Boot successfully."
}

do_revert_and_reboot() {
    log_msg "Revert + Reboot requested: disarming Auto-Boot, unmounting themes, and rebooting display..."
    do_disable_autostart "DISABLED"
    set_countdown "0"
    set_active_state "STOCK"
    do_revert_mounts_only
    set_status "STOCK (Auto-Boot Disabled - Rebooting Display...)"
    sync
    sleep 1
    log_msg "Attempting root display reboot (svc power reboot / sys.powerctl / reboot)..."
    /system/bin/svc power reboot >> "$LOG_FILE" 2>&1
    setprop sys.powerctl reboot >> "$LOG_FILE" 2>&1
    /system/bin/reboot >> "$LOG_FILE" 2>&1
    /system/bin/toolbox reboot >> "$LOG_FILE" 2>&1
    log_msg "WARNING: Software reboot commands returned without halting display; advise user to pinhole reset."
    return 1
}

check_usb_failsafe() {
    local usb_dir=""
    local trig_file=""
    for usb_dir in /storage/usb0 /storage/usb1 /mnt/media_rw/usb0 /mnt/media_rw/usb1 /mnt/usb_storage /storage/usbdisk; do
        if [ -d "$usb_dir" ]; then
            for trig_file in REVERT_THEME REVERT_THEME.txt revert_theme revert_theme.txt SAFE_MODE SAFE_MODE.txt safe_mode safe_mode.txt DISABLE_THEME DISABLE_THEME.txt disable_theme disable_theme.txt; do
                if [ -f "$usb_dir/$trig_file" ]; then
                    if is_mounted || is_autostart_enabled; then
                        log_msg "FAILSAFE TRIGGERED: USB kill-switch file found at $usb_dir/$trig_file!"
                        do_disable_autostart "TRIPPED|USB Kill-Switch ($trig_file)"
                        if is_mounted; then
                            do_revert_mounts_only
                        fi
                        set_status "STOCK (USB Kill-Switch Triggered - Auto-Boot Disabled)"
                    fi
                    return 0
                fi
            done
        fi
    done
    return 1
}

do_apply_test() {
    local skip_timer="$1"
    if [ ! -s "$THEMED_APK" ]; then
        set_status "ERROR: Themed APK missing at $THEMED_APK"
        log_msg "ERROR: Missing or empty $THEMED_APK"
        return 1
    fi

    if [ "$skip_timer" != "CONFIRMED" ] && is_autostart_enabled; then
        log_msg "New 45s theme test started; disarming previous Auto-Boot until confirmed."
        do_disable_autostart "DISABLED"
    fi

    if [ -s "$THEMED_ODEX" ] && [ -f "$TARGET_ODEX" ]; then
        mount_single_target "$THEMED_ODEX" "$STOCK_ODEX" "$TARGET_ODEX" "com.android.launcher3" "com.android.launcher3"
    elif is_path_mounted "$TARGET_ODEX"; then
        unmount_single_target "$TARGET_ODEX" "$STOCK_ODEX" "com.android.launcher3" "com.android.launcher3"
    fi
    mount_single_target "$THEMED_APK" "$STOCK_APK" "$TARGET_APK" "com.android.launcher3" "com.android.launcher3"
    mount_single_target "$THEMED_SYSUI" "$STOCK_SYSUI" "$TARGET_SYSUI" "com.android.systemui" ""
    mount_single_target "$THEMED_CLIMATE" "$STOCK_CLIMATE" "$TARGET_CLIMATE" "HKMC_Climate|apps.climate" "com.hkmc.telematics.service.apps.climate"
    mount_single_target "$THEMED_EV" "$STOCK_EV" "$TARGET_EV" "daudio.app.ev" "com.hkmc.daudio.app.ev3"

    if is_path_mounted "$TARGET_APK"; then
        set_active_state "THEMED"
        if [ "$skip_timer" = "CONFIRMED" ]; then
            set_countdown "0"
            if is_autostart_enabled; then
                set_status "CONFIRMED (Auto-Boot ON - Custom Theme Active)"
            else
                set_status "CONFIRMED (Custom Theme Active Until Reboot)"
            fi
            log_msg "SUCCESS: Theme bind-mounted directly in CONFIRMED mode (no timer)!"
        else
            set_countdown "45"
            set_status "TESTING_COUNTDOWN (45s left - Confirm to Keep!)"
            log_msg "SUCCESS: Theme bind-mounted! Starting 45s safety timer..."
        fi
        sleep 1
        am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
        sleep 1
        return 0
    else
        set_status "ERROR: toolbox mount -o bind failed (see helper.log)"
        log_msg "ERROR: $TARGET_APK not found in /proc/mounts after mount -o bind"
        return 1
    fi
}

# Support direct one-shot invocation via `nemesis root -c "sh .../themer-helper.sh DIRECT_APPLY"`
if [ -n "$1" ]; then
    case "$1" in
        DIRECT_PREPARE_STAGE)
            log_msg "Direct invocation: DIRECT_PREPARE_STAGE"
            do_prepare_stage
            exit $?
            ;;
        DIRECT_APPLY)
            log_msg "Direct invocation: DIRECT_APPLY"
            do_apply_test ""
            exit $?
            ;;
        DIRECT_APPLY_CONFIRMED)
            log_msg "Direct invocation: DIRECT_APPLY_CONFIRMED"
            do_apply_test "CONFIRMED"
            exit $?
            ;;
        DIRECT_CONFIRM)
            log_msg "Direct invocation: DIRECT_CONFIRM"
            if ! is_path_mounted "$TARGET_APK" && [ -s "$THEMED_APK" ]; then
                do_apply_test "CONFIRMED"
                exit $?
            fi
            set_countdown "0"
            set_active_state "THEMED"
            if is_autostart_enabled; then
                set_status "CONFIRMED (Auto-Boot ON - Custom Theme Active)"
            else
                set_status "CONFIRMED (Custom Theme Active Until Reboot)"
            fi
            am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
            exit 0
            ;;
        DIRECT_REVERT)
            log_msg "Direct invocation: DIRECT_REVERT"
            do_revert
            exit 0
            ;;
        DIRECT_REVERT_REBOOT)
            log_msg "Direct invocation: DIRECT_REVERT_REBOOT"
            do_revert_and_reboot
            exit $?
            ;;
        DIRECT_ENABLE_AUTOSTART)
            log_msg "Direct invocation: DIRECT_ENABLE_AUTOSTART"
            do_enable_autostart
            exit $?
            ;;
        DIRECT_DISABLE_AUTOSTART)
            log_msg "Direct invocation: DIRECT_DISABLE_AUTOSTART"
            do_disable_autostart "DISABLED"
            if is_mounted; then
                set_status "CONFIRMED (Auto-Boot OFF - Active Until Reboot)"
            else
                set_status "STOCK (Factory Unmodified)"
            fi
            exit 0
            ;;
    esac
fi

# Daemon mode startup
log_msg "themer-helper daemon started (id=$(id))"
rm -f "$CMD_FILE" 2>/dev/null
sync_autostart_state_file

BOOT_VERIFY_REMAINING=0
BOOT_VERIFY_PID=""
BOOT_PID_CHANGES=0

if is_mounted; then
    set_active_state "THEMED"
    if is_autostart_enabled; then
        set_status "CONFIRMED (Auto-Boot ON - Custom Theme Active)"
    else
        set_status "CONFIRMED (Custom Theme Active Until Reboot)"
    fi
else
    set_active_state "STOCK"
    set_status "STOCK (Factory Unmodified)"
    set_countdown "0"

    # Check if Auto-Boot on Reboot is armed
    if is_autostart_enabled; then
        if check_usb_failsafe; then
            log_msg "AUTO-BOOT ABORTED: USB kill-switch present at boot."
        elif [ ! -s "$PERSIST_DIR/Launcher_WP3_themed.apk" ]; then
            log_msg "AUTO-BOOT ABORTED: Cached Launcher_WP3_themed.apk missing in $PERSIST_DIR."
            do_disable_autostart "DISABLED"
        else
            strikes=0
            if [ -f "$AUTOSTART_STRIKES_FILE" ]; then
                read -r strikes < "$AUTOSTART_STRIKES_FILE" 2>/dev/null
            fi
            case "$strikes" in
                ''|*[!0-9]*) strikes=0 ;;
            esac

            if [ "$strikes" -ge 2 ]; then
                log_msg "FAILSAFE TRIPPED: Boot strike counter reached $strikes (pinhole reset or crash detected on previous boots). Disabling Auto-Boot!"
                do_disable_autostart "TRIPPED|2-Strike Boot/Pinhole Failsafe"
                set_status "STOCK (Failsafe Tripped After $strikes Interrupted Boots)"
            else
                # Record strike immediately to disk BEFORE waiting or mounting so a pinhole reset increments strikes
                strikes=$((strikes + 1))
                echo "$strikes" > "$AUTOSTART_STRIKES_FILE" 2>/dev/null
                chmod 666 "$AUTOSTART_STRIKES_FILE" 2>/dev/null
                sync
                log_msg "AUTO-BOOT ARMED (Strike $strikes/2): Waiting for Android boot_completed & stock Launcher..."

                wait_ticks=0
                while [ $wait_ticks -lt 60 ]; do
                    boot_done="$(getprop sys.boot_completed 2>/dev/null)"
                    lpid="$(get_launcher_pid)"
                    if [ "$boot_done" = "1" ] && [ -n "$lpid" ]; then
                        break
                    fi
                    if check_usb_failsafe; then
                        break
                    fi
                    sleep 1
                    wait_ticks=$((wait_ticks + 1))
                done

                if is_autostart_enabled; then
                    log_msg "AUTO-BOOT: Entering 6s grace window (Strike $strikes/2 - Pinhole Reset or USB Kill-Switch to abort)..."
                    grace=6
                    aborted=0
                    while [ $grace -gt 0 ]; do
                        set_status "AUTO-BOOT IN ${grace}s (Strike $strikes/2 - Pinhole Reset or Revert to Abort)"
                        if check_usb_failsafe; then
                            aborted=1
                            break
                        fi
                        if [ -f "$CMD_FILE" ]; then
                            early_cmd=""
                            read -r early_cmd < "$CMD_FILE" 2>/dev/null
                            case "$early_cmd" in
                                REVERT_STOCK*|DISABLE_AUTOSTART*)
                                    rm -f "$CMD_FILE" 2>/dev/null
                                    do_disable_autostart "DISABLED"
                                    set_status "STOCK (Auto-Boot Cancelled by User)"
                                    aborted=1
                                    break
                                    ;;
                            esac
                        fi
                        if ! is_autostart_enabled; then
                            aborted=1
                            break
                        fi
                        sleep 1
                        grace=$((grace - 1))
                    done

                    if [ "$aborted" -eq 0 ] && is_autostart_enabled; then
                        log_msg "AUTO-BOOT: Staging cached APKs from $PERSIST_DIR into $WORK_DIR..."
                        rm -f "$THEMED_APK" "$THEMED_ODEX" "$THEMED_SYSUI" "$THEMED_CLIMATE" "$THEMED_EV" 2>/dev/null
                        cp -f "$PERSIST_DIR/Launcher_WP3_themed.apk" "$THEMED_APK" 2>/dev/null
                        chmod 666 "$THEMED_APK" 2>/dev/null
                        if [ -s "$PERSIST_ODEX" ]; then
                            cp -f "$PERSIST_ODEX" "$THEMED_ODEX" 2>/dev/null
                            chmod 666 "$THEMED_ODEX" 2>/dev/null
                        fi
                        if [ -s "$PERSIST_DIR/SystemUI_themed.apk" ]; then
                            cp -f "$PERSIST_DIR/SystemUI_themed.apk" "$THEMED_SYSUI" 2>/dev/null
                            chmod 666 "$THEMED_SYSUI" 2>/dev/null
                        fi
                        if [ -s "$PERSIST_DIR/HKMC_Climate_themed.apk" ]; then
                            cp -f "$PERSIST_DIR/HKMC_Climate_themed.apk" "$THEMED_CLIMATE" 2>/dev/null
                            chmod 666 "$THEMED_CLIMATE" 2>/dev/null
                        fi
                        if [ -s "$PERSIST_DIR/HKMC_TAppEV3_themed.apk" ]; then
                            cp -f "$PERSIST_DIR/HKMC_TAppEV3_themed.apk" "$THEMED_EV" 2>/dev/null
                            chmod 666 "$THEMED_EV" 2>/dev/null
                        fi
                        if [ -f "$AUTOSTART_THEME_FILE" ]; then
                            cp -f "$AUTOSTART_THEME_FILE" "$ACTIVE_THEME_NAME_FILE" 2>/dev/null
                            chmod 666 "$ACTIVE_THEME_NAME_FILE" 2>/dev/null
                        fi

                        if do_apply_test "CONFIRMED"; then
                            sleep 2
                            BOOT_VERIFY_PID="$(get_launcher_pid)"
                            BOOT_PID_CHANGES=0
                            BOOT_VERIFY_REMAINING=60
                            log_msg "AUTO-BOOT: Theme mounted! Monitoring Launcher stability for 60s (initial pid=$BOOT_VERIFY_PID) before clearing strike $strikes..."
                        else
                            log_msg "AUTO-BOOT ERROR: Failed to mount cached theme; disabling Auto-Boot."
                            do_disable_autostart "TRIPPED|Mount Failed on Boot"
                        fi
                    fi
                fi
            fi
        fi
    fi
fi

TIMER_REMAINING=0
TIMER_ACTIVE=0

while true; do
    # Continuous USB Kill-Switch Failsafe check
    check_usb_failsafe

    # 60-Second Post-Boot Stability Watchdog
    if [ "$BOOT_VERIFY_REMAINING" -gt 0 ]; then
        if ! is_mounted || ! is_autostart_enabled; then
            BOOT_VERIFY_REMAINING=0
        else
            cur_lpid="$(get_launcher_pid)"
            if [ -z "$cur_lpid" ]; then
                BOOT_PID_CHANGES=$((BOOT_PID_CHANGES + 1))
                log_msg "AUTO-BOOT WATCHDOG: Launcher process missing (count=$BOOT_PID_CHANGES)..."
            elif [ -z "$BOOT_VERIFY_PID" ]; then
                BOOT_VERIFY_PID="$cur_lpid"
            elif [ "$cur_lpid" != "$BOOT_VERIFY_PID" ]; then
                BOOT_PID_CHANGES=$((BOOT_PID_CHANGES + 1))
                log_msg "AUTO-BOOT WATCHDOG: Launcher PID changed ($BOOT_VERIFY_PID -> $cur_lpid, changes=$BOOT_PID_CHANGES)"
                BOOT_VERIFY_PID="$cur_lpid"
            fi

            if [ "$BOOT_PID_CHANGES" -ge 2 ]; then
                log_msg "FAILSAFE TRIPPED: Launcher crashed/restarted repeatedly during 60s boot watchdog! Reverting to Stock & disabling Auto-Boot."
                BOOT_VERIFY_REMAINING=0
                do_disable_autostart "TRIPPED|Launcher Crash Watchdog"
                do_revert_mounts_only
                set_status "STOCK (Failsafe Tripped: Launcher Crash on Boot)"
            else
                BOOT_VERIFY_REMAINING=$((BOOT_VERIFY_REMAINING - 1))
                if [ "$BOOT_VERIFY_REMAINING" -le 0 ]; then
                    echo "0" > "$AUTOSTART_STRIKES_FILE" 2>/dev/null
                    chmod 666 "$AUTOSTART_STRIKES_FILE" 2>/dev/null
                    sync
                    sync_autostart_state_file
                    set_status "CONFIRMED (Auto-Boot Verified & Active)"
                    log_msg "AUTO-BOOT: 60s stability verification passed! boot_strikes reset to 0."
                fi
            fi
        fi
    fi

    # Allow external DIRECT_APPLY to trigger the daemon countdown by checking COUNTDOWN_FILE
    if [ "$TIMER_ACTIVE" -eq 0 ] && [ -f "$COUNTDOWN_FILE" ]; then
        ext_cd=""
        read -r ext_cd < "$COUNTDOWN_FILE" 2>/dev/null
        if [ "$ext_cd" = "45" ]; then
            TIMER_ACTIVE=1
            TIMER_REMAINING=45
            log_msg "Daemon detected 45s countdown trigger; starting deadman timer."
        fi
    fi

    if [ -f "$CMD_FILE" ]; then
        CMD=""
        read -r CMD < "$CMD_FILE" 2>/dev/null
        rm -f "$CMD_FILE" 2>/dev/null
        log_msg "Daemon received command: '$CMD'"

        case "$CMD" in
            APPLY_TEST*)
                BOOT_VERIFY_REMAINING=0
                if do_apply_test ""; then
                    TIMER_ACTIVE=1
                    TIMER_REMAINING=45
                fi
                ;;

            APPLY_CONFIRMED*)
                BOOT_VERIFY_REMAINING=0
                TIMER_ACTIVE=0
                TIMER_REMAINING=0
                do_apply_test "CONFIRMED"
                ;;

            CONFIRM_KEEP*)
                TIMER_ACTIVE=0
                TIMER_REMAINING=0
                set_countdown "0"
                set_active_state "THEMED"
                if is_autostart_enabled; then
                    set_status "CONFIRMED (Auto-Boot ON - Custom Theme Active)"
                else
                    set_status "CONFIRMED (Custom Theme Active Until Reboot)"
                fi
                log_msg "User confirmed theme! Deadman timer cancelled."
                am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
                ;;

            ENABLE_AUTOSTART*)
                do_enable_autostart
                ;;

            DISABLE_AUTOSTART*)
                BOOT_VERIFY_REMAINING=0
                do_disable_autostart "DISABLED"
                if is_mounted; then
                    set_status "CONFIRMED (Auto-Boot OFF - Active Until Reboot)"
                else
                    set_status "STOCK (Factory Unmodified)"
                fi
                ;;

            REVERT_STOCK*)
                BOOT_VERIFY_REMAINING=0
                TIMER_ACTIVE=0
                TIMER_REMAINING=0
                do_revert
                ;;

            REVERT_REBOOT*)
                BOOT_VERIFY_REMAINING=0
                TIMER_ACTIVE=0
                TIMER_REMAINING=0
                do_revert_and_reboot
                ;;
        esac
    fi

    if [ "$TIMER_ACTIVE" -eq 1 ]; then
        cur_cd=""
        read -r cur_cd < "$COUNTDOWN_FILE" 2>/dev/null
        if [ "$cur_cd" = "0" ]; then
            log_msg "Countdown cleared externally (user confirmed or reverted)."
            TIMER_ACTIVE=0
            TIMER_REMAINING=0
        elif [ "$TIMER_REMAINING" -le 0 ]; then
            log_msg "45s Deadman Timer expired without confirmation! Auto-reverting to stock..."
            TIMER_ACTIVE=0
            do_revert
            am start -n com.gen5w.themer/com.gen5w.themer.MainActivity >/dev/null 2>&1
        else
            set_countdown "$TIMER_REMAINING"
            set_status "TESTING_COUNTDOWN (${TIMER_REMAINING}s left - Tap CONFIRM to Keep!)"
            if [ "$TIMER_REMAINING" -eq 30 ]; then
                log_msg "15s preview elapsed (30s left) - surfacing Gen5WThemer for confirmation."
                am start -n com.gen5w.themer/com.gen5w.themer.MainActivity >/dev/null 2>&1
            fi
            TIMER_REMAINING=$((TIMER_REMAINING - 1))
        fi
    fi

    sleep 1
done
