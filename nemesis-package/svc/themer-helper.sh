#!/system/bin/sh
# Gen5W Themer Root Helper Service (NEMESIS service.0, uid=root)
# Strict Gen5W toolbox + mksh compatibility (NO busybox, tr, awk, killall, pkill, or umount -l).

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

WORK_DIR="/mnt/asec/gen5w_themer"
CMD_FILE="$WORK_DIR/cmd"
STATUS_FILE="$WORK_DIR/status"
COUNTDOWN_FILE="$WORK_DIR/countdown"
ACTIVE_FILE="$WORK_DIR/active_state"
LOG_FILE="$WORK_DIR/helper.log"
THEMED_APK="$WORK_DIR/Launcher_WP3_themed.apk"
STOCK_APK="$WORK_DIR/Launcher_WP3_stock.apk"
TARGET_APK="/system/app/Launcher_WP3.apk"

mkdir -p "$WORK_DIR" 2>/dev/null
chmod 777 "$WORK_DIR" 2>/dev/null

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

is_mounted() {
    grep -q "$TARGET_APK" /proc/mounts 2>/dev/null
    return $?
}

kill_launcher() {
    ps | while read user pid ppid vsize rss wchan pc state name rest; do
        case "$name" in
            *com.android.launcher3*)
                log_msg "Killing com.android.launcher3 (pid=$pid)"
                kill -9 "$pid" 2>/dev/null
                ;;
        esac
    done
}

unmount_target() {
    # Always kill launcher first so it closes its open fd on Launcher_WP3.apk
    kill_launcher
    sleep 1
    local tries=0
    while is_mounted && [ $tries -lt 4 ]; do
        /system/bin/toolbox umount "$TARGET_APK" >> "$LOG_FILE" 2>&1 || umount "$TARGET_APK" >> "$LOG_FILE" 2>&1
        if ! is_mounted; then
            log_msg "Unmounted $TARGET_APK cleanly."
            return 0
        fi
        kill_launcher
        tries=$((tries + 1))
        sleep 1
    done

    # Fallback if system_server holds an open fd preventing umount:
    # Bind-mount the clean stock APK copy right on top so stock assets are restored immediately!
    if is_mounted && [ -s "$STOCK_APK" ]; then
        log_msg "Mount busy; bind-mounting clean STOCK_APK ($STOCK_APK) on top of $TARGET_APK..."
        chmod 644 "$STOCK_APK" 2>/dev/null
        chown 0.0 "$STOCK_APK" 2>/dev/null || chown 0:0 "$STOCK_APK" 2>/dev/null
        /system/bin/toolbox mount -o bind "$STOCK_APK" "$TARGET_APK" >> "$LOG_FILE" 2>&1 || mount -o bind "$STOCK_APK" "$TARGET_APK" >> "$LOG_FILE" 2>&1
        return 0
    fi
    return 1
}

do_revert() {
    log_msg "Reverting to factory stock OEM Launcher..."
    set_countdown "0"
    set_active_state "STOCK"
    unmount_target
    kill_launcher
    sleep 1
    am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
    set_status "STOCK (Factory Unmodified)"
    log_msg "Reverted to stock successfully."
}

do_apply_test() {
    local skip_timer="$1"
    if [ ! -s "$THEMED_APK" ]; then
        set_status "ERROR: Themed APK missing at $THEMED_APK"
        log_msg "ERROR: Missing or empty $THEMED_APK"
        return 1
    fi

    # Snapshot clean stock APK in RAM before first bind mount
    if [ ! -s "$STOCK_APK" ] && ! is_mounted; then
        log_msg "Saving clean stock reference copy to $STOCK_APK..."
        cp -f "$TARGET_APK" "$STOCK_APK" 2>/dev/null
    fi
    if [ -s "$STOCK_APK" ]; then
        chmod 644 "$STOCK_APK" 2>/dev/null
        chown 0.0 "$STOCK_APK" 2>/dev/null || chown 0:0 "$STOCK_APK" 2>/dev/null
    fi

    chmod 644 "$THEMED_APK" 2>/dev/null
    chown 0.0 "$THEMED_APK" 2>/dev/null || chown 0:0 "$THEMED_APK" 2>/dev/null

    # If already mounted, try unmounting first
    if is_mounted; then
        kill_launcher
        /system/bin/toolbox umount "$TARGET_APK" >/dev/null 2>&1 || umount "$TARGET_APK" >/dev/null 2>&1
    fi

    log_msg "Running: toolbox mount -o bind $THEMED_APK $TARGET_APK"
    /system/bin/toolbox mount -o bind "$THEMED_APK" "$TARGET_APK" >> "$LOG_FILE" 2>&1 || mount -o bind "$THEMED_APK" "$TARGET_APK" >> "$LOG_FILE" 2>&1

    if is_mounted; then
        set_active_state "THEMED"
        if [ "$skip_timer" = "CONFIRMED" ]; then
            set_countdown "0"
            set_status "CONFIRMED (Custom Theme Active Until Reboot)"
            log_msg "SUCCESS: $TARGET_APK bind-mounted directly in CONFIRMED mode (no timer)! Restarting com.android.launcher3..."
        else
            set_countdown "45"
            set_status "TESTING_COUNTDOWN (45s left - Confirm to Keep!)"
            log_msg "SUCCESS: $TARGET_APK is now bind-mounted! Restarting com.android.launcher3..."
        fi
        kill_launcher
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
            if ! is_mounted && [ -s "$THEMED_APK" ]; then
                do_apply_test "CONFIRMED"
                exit $?
            fi
            set_countdown "0"
            set_active_state "THEMED"
            set_status "CONFIRMED (Custom Theme Active Until Reboot)"
            am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
            exit 0
            ;;
        DIRECT_REVERT)
            log_msg "Direct invocation: DIRECT_REVERT"
            do_revert
            exit 0
            ;;
    esac
fi

# Daemon mode startup
log_msg "themer-helper daemon started (id=$(id))"
rm -f "$CMD_FILE" 2>/dev/null
if is_mounted; then
    set_active_state "THEMED"
    set_status "CONFIRMED (Custom Theme Active Until Reboot)"
else
    set_active_state "STOCK"
    set_status "STOCK (Factory Unmodified)"
    set_countdown "0"
fi

TIMER_REMAINING=0
TIMER_ACTIVE=0

while true; do
    # Also allow external DIRECT_APPLY to trigger the daemon countdown by checking COUNTDOWN_FILE
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
                if do_apply_test ""; then
                    TIMER_ACTIVE=1
                    TIMER_REMAINING=45
                fi
                ;;

            APPLY_CONFIRMED*)
                TIMER_ACTIVE=0
                TIMER_REMAINING=0
                do_apply_test "CONFIRMED"
                ;;

            CONFIRM_KEEP*)
                TIMER_ACTIVE=0
                TIMER_REMAINING=0
                set_countdown "0"
                set_active_state "THEMED"
                set_status "CONFIRMED (Custom Theme Active Until Reboot)"
                log_msg "User confirmed theme! Deadman timer cancelled."
                am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
                ;;

            REVERT_STOCK*)
                TIMER_ACTIVE=0
                TIMER_REMAINING=0
                do_revert
                ;;
        esac
    fi

    if [ "$TIMER_ACTIVE" -eq 1 ]; then
        # Check if user confirmed via DIRECT_CONFIRM (which sets COUNTDOWN_FILE to 0)
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
