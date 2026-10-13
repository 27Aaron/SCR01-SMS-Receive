#!/system/bin/sh
# Restore the recorded baseline: SMS role, enabled state, IMS switches, the
# owned APN row, the overlay state and every candidate bind. Run through the
# KSU busybox (flock requires it): the stock toybox flock cannot fd-lock.
MODDIR=${0%/*}
. "$MODDIR/common.sh"
firmware_guard && need_tools && lock || exit 1
errors=0
[ -f "$STATE/installed" ] || { say 'Nothing installed; nothing to roll back'; exit 0; }

# Removing a role holder requires the capability to be visible; lift the
# overlay first when it is not currently active.
if ! resource_true 2>/dev/null; then
    chmod 0644 "$MODDIR/payload/AccentColorCinnamonOverlay.apk" 2>/dev/null
    chcon u:object_r:vendor_overlay_file:s0 "$MODDIR/payload/AccentColorCinnamonOverlay.apk" 2>/dev/null
    for pid in $(watched_pids 2>/dev/null); do
        [ "$(view_hash "$pid" 2>/dev/null)" = "$ORIGINAL" ] &&
            nsenter -t "$pid" -m -- mount -o bind "$MODDIR/payload/AccentColorCinnamonOverlay.apk" "$TARGET" 2>/dev/null
    done
    run cmd overlay enable --user 0 "$OVERLAY" >/dev/null 2>&1
    sleep 2
    resource_true 2>/dev/null || say 'Capability lift failed; role removal may fail'
fi

if [ -f "$STATE/role_changed" ]; then
    if [ "$(role 2>/dev/null)" = "$APP" ] && [ "$(get role)" = null ]; then
        run cmd role remove-role-holder --user 0 android.app.role.SMS "$APP" >/dev/null 2>&1 || errors=1
    fi
    [ "$(role 2>/dev/null)" = "$(get role)" ] && rm -f "$STATE/role_changed" || errors=1
fi
current=$(app_enabled 2>/dev/null) || current=unknown
if [ "$current" != unknown ] && [ "$current" != "$(get enabled)" ]; then
    case "$(get enabled)" in
        0) run pm default-state --user 0 "$APP" >/dev/null 2>&1;;
        1) run pm enable --user 0 "$APP" >/dev/null 2>&1;;
    esac
    [ "$(app_enabled 2>/dev/null)" = "$(get enabled)" ] || errors=1
fi
for service in volte smsip; do
    [ -f "$STATE/${service}_changed" ] || continue
    old=$(get "$service")
    case "$old" in 0|1) :;; *) continue;; esac
    wanted=false; [ "$old" = 1 ] && wanted=true
    if [ "$(switch_value "$service" 2>/dev/null)" != "$old" ]; then
        provider update --uri "$IMS" --bind "service:s:$service" --bind "enabled:b:$wanted" >/dev/null 2>&1 || errors=1
    fi
    [ "$(switch_value "$service" 2>/dev/null)" = "$old" ] && rm -f "$STATE/${service}_changed" || errors=1
done
if [ -f "$STATE/apn_requested" ]; then
    rows=$(apn_rows 2>/dev/null) || rows=unknown
    if printf '%s\n' "$rows" | grep -q '^Row:'; then
        current_id=$(apn_id 2>/dev/null) || current_id=unknown
        owned=$(get apn_numeric)
        if [ -n "$owned" ] && [ "$current_id" != unknown ]; then
            provider delete --uri "$CARRIERS" --where "_id=$current_id AND name='$APN_NAME' AND apn='ims' AND type='ims' AND numeric='$owned'" >/dev/null 2>&1 || errors=1
        else errors=1; fi
    fi
    rows=$(apn_rows 2>/dev/null) || rows=unknown
    if [ "$rows" != unknown ] && ! printf '%s\n' "$rows" | grep -q '^Row:'; then
        rm -f "$STATE/apn_requested" "$STATE/apn_id" "$STATE/apn_numeric"
    else errors=1; fi
fi

# Overlay off, candidate idmap gone, then detach every namespace still
# showing the candidate; never touch unrelated mounts.
run cmd overlay disable --user 0 "$OVERLAY" >/dev/null 2>&1
rm -f /data/resource-cache/product@overlay@AccentColorCinnamon@AccentColorCinnamonOverlay.apk@idmap
seen=/data/local/tmp/scr01-sms-rollback-seen
: > "$seen"
for entry in /proc/[0-9]*/ns/mnt; do
    pid=${entry#/proc/}; pid=${pid%%/*}
    [ "$(view_hash "$pid" 2>/dev/null)" = "$CANDIDATE" ] || continue
    identity=$(ns "$pid" 2>/dev/null) || continue
    grep -Fxq "$identity" "$seen" && continue
    printf '%s\n' "$identity" >> "$seen"
    nsenter -t "$pid" -m -- umount -l "$TARGET" 2>/dev/null
    [ "$(view_hash "$pid" 2>/dev/null)" = "$ORIGINAL" ] || errors=1
done
rm -f "$seen"
for pid in $(watched_pids 2>/dev/null); do
    [ "$(view_hash "$pid" 2>/dev/null)" = "$ORIGINAL" ] || errors=1
done

if [ "$errors" = 0 ]; then
    put transaction rolled_back || errors=1
    log 'Rollback complete. Reboot once to clear the phone capability cache.'
else
    log 'Rollback incomplete; durable state retained for retry'
fi
[ "$errors" = 0 ] || exit 1
