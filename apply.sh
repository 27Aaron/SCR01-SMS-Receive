#!/system/bin/sh
# Idempotent per-boot convergence: capability overlay, Fossify role, IMS link.
# Any failure just exits 1 and the next boot retries; nothing self-disables.
MODDIR=${0%/*}
. "$MODDIR/common.sh"
[ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
firmware_guard && need_tools && lock || exit 1
mkdir -m 0700 "$STATE" 2>/dev/null; chmod 0700 "$STATE" 2>/dev/null
[ "$(hash "$MODDIR/payload/AccentColorCinnamonOverlay.apk")" = "$CANDIDATE" ] || { log 'Payload hash mismatch'; exit 1; }

# Readiness: boot complete, SIM loaded, no active SCRoot rooting flow.
count=0
while [ "$count" -lt 180 ]; do
    [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
    services=$(run dumpsys activity services com.scr01.scroot) || exit 1
    if [ "$(getprop sys.boot_completed)" = 1 ] && [ "$(getprop gsm.sim.state)" = LOADED ] &&
       ! printf '%s\n' "$services" | grep -Eq 'ServiceRecord.*(AutoRootService|ManualFlowGuardService)'; then break; fi
    sleep 2; count=$((count + 2))
done
[ "$count" -lt 180 ] || { log 'Readiness wait failed'; exit 1; }

ensure_fossify || { log 'Fossify Messages unavailable'; exit 1; }

# Lazy baseline on first run: record exactly what rollback must restore.
if [ ! -f "$STATE/installed" ]; then
    baseline_role=$(role 2>/dev/null) || { log 'Another package already holds the SMS role'; exit 1; }
    baseline_enabled=$(app_enabled) || { log 'Cannot read Fossify enabled state'; exit 1; }
    [ "$baseline_enabled" != 2 ] || { log 'Fossify is disabled by the user; enable it first'; exit 1; }
    baseline_volte=$(switch_value volte 2>/dev/null) || baseline_volte=unknown
    baseline_smsip=$(switch_value smsip 2>/dev/null) || baseline_smsip=unknown
    baseline_preferred=$(preferred 2>/dev/null) || baseline_preferred=unknown
    put firmware "$FIRMWARE" && put role "$baseline_role" && put enabled "$baseline_enabled" &&
    put volte "$baseline_volte" && put smsip "$baseline_smsip" && put preferred "$baseline_preferred" &&
    mark installed || exit 1
    log "Baseline recorded: role=$baseline_role enabled=$baseline_enabled volte=$baseline_volte smsip=$baseline_smsip"
fi
[ "$(get firmware)" = "$FIRMWARE" ] || { log 'Firmware changed since baseline'; exit 1; }

# The owned APN follows whichever SIM is actually inserted; no numeric gate.
sim_numeric=$(getprop gsm.sim.operator.numeric)
case "$sim_numeric" in
    [0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) log "No well-formed SIM numeric ('$sim_numeric'); IMS APN skipped"; sim_numeric=;;
esac
if [ -n "$sim_numeric" ]; then
    owned=$(get apn_numeric)
    if [ -n "$owned" ] && [ "$owned" != "$sim_numeric" ]; then
        log 'SIM changed since the owned APN insert; run rollback.sh first'; exit 1
    fi
    [ -n "$owned" ] || put apn_numeric "$sim_numeric" || exit 1
fi

# Mounts: init is bound first so idmap2d — respawned by the framework and
# inheriting the init view — regenerates the idmap from the candidate file;
# then the running watched processes. Idempotent within and across runs.
chmod 0644 "$MODDIR/payload/AccentColorCinnamonOverlay.apk" &&
chcon u:object_r:vendor_overlay_file:s0 "$MODDIR/payload/AccentColorCinnamonOverlay.apk" || exit 1
bind_pid() {
    case "$(view_hash "$1")" in
        "$CANDIDATE") return 0;;
        "$ORIGINAL") nsenter -t "$1" -m -- mount -o bind "$MODDIR/payload/AccentColorCinnamonOverlay.apk" "$TARGET";;
        *) return 1;;
    esac && [ "$(view_hash "$1")" = "$CANDIDATE" ]
}
pids=$(watched_pids) || { log 'Watched processes unavailable'; exit 1; }
for pid in $pids; do bind_pid "$pid" || { log "Bind failed: pid=$pid"; exit 1; }; done
reset_idmap() {
    while [ -n "$(pidof idmap2d 2>/dev/null)" ]; do kill "$(pidof idmap2d)" 2>/dev/null; sleep 1; done
    rm -f /data/resource-cache/product@overlay@AccentColorCinnamon@AccentColorCinnamonOverlay.apk@idmap
}
enable_overlay() {
    reset_idmap
    run cmd overlay enable --user 0 "$OVERLAY" &&
    run cmd overlay dump "$OVERLAY" | grep -q 'STATE_ENABLED' &&
    sleep 2 && resource_true
}
enable_overlay || { sleep 3; enable_overlay; } || { log 'Overlay enable or resource lookup failed'; exit 1; }

# Role bootstrap: on a fresh device the role registry has no SMS role name at
# all; a package-state change while the capability is true makes the registry
# re-evaluate and grant it, with the shell API as fallback.
current_role=$(role 2>/dev/null) || { log 'Another package holds the SMS role'; exit 1; }
if [ "$current_role" != "$APP" ]; then
    pm disable-user --user 0 "$APP" >/dev/null 2>&1
    pm enable --user 0 "$APP" >/dev/null 2>&1
    count=0; while [ "$count" -lt 10 ] && [ "$(role 2>/dev/null)" != "$APP" ]; do sleep 1; count=$((count + 1)); done
    if [ "$(role 2>/dev/null)" != "$APP" ]; then
        run cmd role add-role-holder --user 0 android.app.role.SMS "$APP" >/dev/null 2>&1
        count=0; while [ "$count" -lt 10 ] && [ "$(role 2>/dev/null)" != "$APP" ]; do sleep 1; count=$((count + 1)); done
    fi
    [ "$(role)" = "$APP" ] || { log 'Role bootstrap failed'; exit 1; }
    mark role_changed || exit 1
    # Return the recorded enabled state (default or explicit) without losing
    # the role; the re-evaluation keeps the holder across the restore.
    if [ "$(get enabled)" = 0 ]; then
        run pm default-state --user 0 "$APP" || exit 1
        sleep 2
    fi
    [ "$(role)" = "$APP" ] || { log 'Role lost while restoring enabled state'; exit 1; }
    log "SMS role bootstrapped to $APP"
fi

# IMS link, best effort: one owned APN row plus volte/smsip switches. The
# reference device received SMS before either existed, so failures are logged
# and never abort the run.
if [ -n "$(get apn_numeric)" ]; then
    rows=$(apn_rows 2>/dev/null) || rows=
    if ! printf '%s\n' "$rows" | grep -q '^Row:'; then
        mark apn_requested 2>/dev/null
        owned_numeric=$(get apn_numeric)
        if provider insert --uri "$CARRIERS" --bind "name:s:$APN_NAME" --bind apn:s:ims --bind type:s:ims \
            --bind "numeric:s:$owned_numeric" --bind "mcc:s:$(printf '%s' "$owned_numeric" | cut -c1-3)" \
            --bind "mnc:s:$(printf '%s' "$owned_numeric" | cut -c4-)" --bind protocol:s:IPV4V6 \
            --bind roaming_protocol:s:IPV4V6 --bind carrier_enabled:b:true >/dev/null 2>&1; then
            owned_id=$(apn_id 2>/dev/null) && put apn_id "$owned_id" 2>/dev/null &&
                log "Owned IMS APN inserted (numeric=$owned_numeric)" || log 'IMS APN inserted; id unresolved'
        else
            log 'IMS APN insert failed (non-fatal)'
        fi
    fi
fi
for service in volte smsip; do
    value=$(switch_value "$service" 2>/dev/null) || { log "Cannot read $service switch (non-fatal)"; continue; }
    if [ "$value" = 0 ] && [ "$(get "$service")" = 0 ]; then mark "${service}_changed" 2>/dev/null; fi
    if [ "$value" != 1 ]; then
        provider update --uri "$IMS" --bind "service:s:$service" --bind enabled:b:true >/dev/null 2>&1 ||
            log "$service enable failed (non-fatal)"
    fi
done

# One phone restart per boot refreshes the inbound-SMS capability cache.
boot=$(tr -d '\n' < /proc/sys/kernel/random/boot_id)
if ! phone_capable || [ "$(get phone_restart_boot)" != "$boot" ]; then
    [ "$(get phone_restart_boot)" != "$boot" ] || { log 'Phone capability false after an earlier restart'; exit 1; }
    pid=$(pidof com.android.phone) || { log 'Phone process missing'; exit 1; }
    [ "$(view_hash "$pid")" = "$CANDIDATE" ] || { log 'Phone view mismatch before restart'; exit 1; }
    put phone_restart_boot "$boot" || exit 1
    kill -TERM "$pid" || exit 1
    count=0
    while [ "$count" -lt 45 ]; do
        new_pid=$(pidof com.android.phone 2>/dev/null || true)
        if [ -n "$new_pid" ] && [ "$new_pid" != "$pid" ] && [ "$(getprop gsm.sim.state)" = LOADED ] &&
           phone_capable && resource_true; then break; fi
        sleep 1; count=$((count + 1))
    done
    [ "$count" -lt 45 ] || { log 'Phone restart recovery failed'; exit 1; }
fi

resource_true || { log 'Final resource lookup failed'; exit 1; }
phone_capable || { log 'Final phone capability failed'; exit 1; }
[ "$(role)" = "$APP" ] || { log 'Final SMS role failed'; exit 1; }
count=0
while [ "$count" -lt 15 ] && [ -z "$(preferred 2>/dev/null)" ]; do sleep 1; count=$((count + 1)); done
[ -n "$(preferred 2>/dev/null)" ] || log 'Preferred data APN not visible yet (non-fatal)'
put transaction committed && put active_boot "$boot" || exit 1
log "Active: capability true, role=$APP, phone pid=$(pidof com.android.phone)"
