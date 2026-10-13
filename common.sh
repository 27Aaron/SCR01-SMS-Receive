#!/system/bin/sh
# SCR01 SMS Receive shared helpers. State is data, never shell code.
MODDIR=${MODDIR:-${0%/*}}
STATE=/data/adb/scr01_sms_receive_state
TARGET=/product/overlay/AccentColorCinnamon/AccentColorCinnamonOverlay.apk
OVERLAY=com.android.theme.color.cinnamon
APP=org.fossify.messages
ORIGINAL=7a206d842ad6baa60a22e10df8b154dc92b76e4ee3f5006adfbca9c89e2d8f19
CANDIDATE=be3101f4bbae894aa86cbe9493e7c110f9d669967a1622e3f5bfc95dd36591cf
FIRMWARE=KDDI/SCR01_jp_kdi/SCR01:11/RP1A.200720.012/SCR01KDU1AVK2:user/release-keys
APN_NAME='SCR01 SMS module v1 IMS'
IMS=content://com.sec.ims.settings/imsswitch
CARRIERS=content://telephony/carriers
# Official Fossify Messages release asset from FossifyOrg/Messages.
FOSSIFY_URL=https://github.com/FossifyOrg/Messages/releases/download/1.10.1/messages-25-foss-release.apk
FOSSIFY_SHA=af81e85e0e5442cf22d9669f43ecc42e39737389cff8fe91fd0ef58dab59703d
umask 077
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$STATE/run.log"; }
fail() { printf '%s\n' "$*" >&2; return 1; }
say() { if command -v ui_print >/dev/null 2>&1; then ui_print "$*"; else printf '%s\n' "$*"; fi; }
need_tools() {
    for tool in nsenter sha256sum timeout getprop id cmd pm dumpsys content pidof readlink awk grep cut tr sync mount umount flock chcon cp chmod rm mkdir; do
        command -v "$tool" >/dev/null 2>&1 || { fail "Missing tool: $tool"; return 1; }
    done
}
run() { timeout -k 1s 15s "$@"; }
provider() {
    provider_output=$(run content "$@" 2>&1) || { fail "$provider_output"; return 1; }
    printf '%s\n' "$provider_output" | grep -Eq 'Error|Exception' && return 1
    printf '%s\n' "$provider_output"
}
put() { printf '%s\n' "$2" > "$STATE/$1.new" && sync && mv "$STATE/$1.new" "$STATE/$1" && sync; }
mark() { put "$1" 1; }
get() { [ -f "$STATE/$1" ] && tr -d '\r\n' < "$STATE/$1"; }
hash() { sha256sum "$1" | cut -d' ' -f 1; }
view_hash() { run nsenter -t "$1" -m -- sha256sum "$TARGET" 2>/dev/null | cut -d' ' -f 1; }
ns() { readlink "/proc/$1/ns/mnt"; }
firmware_guard() { [ "$(id -u)" = 0 ] && [ "$(getprop ro.build.fingerprint)" = "$FIRMWARE" ]; }
lock() {
    exec 9> /data/adb/.scr01_sms_receive.lock || return 1
    flock -n 9 || { fail 'Another module transaction is running'; return 1; }
}
# Samsung Android 11 dumpsys role parsing. Absent role or empty holders both
# count as null (a fresh registry has no SMS role name at all); any other
# holder is refused rather than replaced.
role() {
    run dumpsys role | awk '
    /user_id=|userId=/ { user=($0 ~ /(user_id|userId)=0([^0-9]|$)/); active=0 }
    user && /name=android.app.role.SMS([^A-Za-z.]|$)/ {active=1; found++}
    user && active && /holders=/ {sub(/^.*holders=/, ""); gsub(/\[/, ""); gsub(/\]/, ""); gsub(/[{}[:space:]]/, ""); value=$0; active=0}
    END {if(found>1) exit 1; if(value=="") print "null"; else if(value=="org.fossify.messages") print value; else exit 1}'
}
app_enabled() {
    run dumpsys package "$APP" | awk '/User 0:/ {for(i=1;i<=NF;i++) if($i ~ /^enabled=[0-4]$/) {sub(/^enabled=/,"",$i); print $i; found++}} END {if(found!=1) exit 1}'
}
switch_value() {
    provider query --uri "$IMS" | awk -v key="$1" '
    {n=split($0, fields, ", "); name=""; enabled=""; for(i=1;i<=n;i++){if(fields[i] ~ /name=/){name=fields[i]; sub(/^.*name=/,"",name)} if(fields[i] ~ /^enabled=/){enabled=fields[i]; sub(/^enabled=/,"",enabled)}} if(name==key && enabled ~ /^[01]$/){print enabled; found++}}
    END {if(found!=1) exit 1}'
}
preferred() { provider query --uri "$CARRIERS/preferapn" --projection _id:name:apn:numeric; }
# The owned IMS APN follows whichever SIM numeric was journaled at insert time.
apn_rows() { provider query --uri "$CARRIERS" --projection _id:name:apn:type:numeric:protocol:roaming_protocol:carrier_enabled --where "name='$APN_NAME'"; }
apn_id() {
    owned_numeric=$(get apn_numeric)
    [ -n "$owned_numeric" ] || return 1
    apn_rows | awk -v name="$APN_NAME" -v numeric="$owned_numeric" 'index($0,"name="name", apn=ims, type=ims, numeric="numeric", protocol=IPV4V6, roaming_protocol=IPV4V6, carrier_enabled=1") {sub(/^.*_id=/,""); sub(/,.*/,""); if($0 ~ /^[0-9]+$/){print; found++}} END {if(found!=1) exit 1}'
}
resource_true() {
    [ "$(run cmd overlay lookup android android:bool/config_sms_capable | tr -d '\r')" = true ] &&
    [ "$(run cmd overlay lookup com.android.phone android:bool/config_sms_capable | tr -d '\r')" = true ]
}
phone_capable() { run dumpsys phone | grep -Eq 'isSmsCapable[=:][[:space:]]*true'; }
# Surfing's TPROXY path does not honor tun.exclude-package. IMS registration
# runs as system UID 1000, so it is caught by the four local proxy/DNS chains.
# Surfing rebuilds those chains whenever it restarts, which drops a one-shot
# insert; re-assert them whenever the chains exist. The comment is the
# ownership tag rollback matches. Bypasses every flow owned by UID 1000, not
# only IMS, and only while Surfing's chains are present.
RULE_TAG=scr01-sms-module-v1
surfing_chains() { printf '%s\n' 'iptables mangle BOX_LOCAL' 'iptables nat CLASH_DNS_LOCAL' 'ip6tables mangle BOX_LOCAL' 'ip6tables mangle CLASH_DNS_LOCAL'; }
# Present only when the module is installed and not switched off. A disable
# file means the user turned it off, so its chains are not ours to touch.
surfing_present() {
    [ -f /data/adb/modules/Surfing/module.prop ] && [ ! -f /data/adb/modules/Surfing/disable ] && [ ! -f /data/adb/modules/Surfing/remove ]
}
ensure_surfing_bypass() {
    surfing_present || { log 'Surfing not installed or disabled; bypass not applied'; return 0; }
    surfing_chains | while read -r tool table chain; do
        "$tool" -w 5 -t "$table" -S "$chain" >/dev/null 2>&1 || continue
        "$tool" -w 5 -t "$table" -C "$chain" -m owner --uid-owner 1000 -m comment --comment "$RULE_TAG" -j RETURN >/dev/null 2>&1 && continue
        "$tool" -w 5 -t "$table" -I "$chain" 1 -m owner --uid-owner 1000 -m comment --comment "$RULE_TAG" -j RETURN >/dev/null 2>&1 ||
            { log "Surfing bypass insert failed: $tool $table $chain"; continue; }
        log "Surfing bypass inserted: $tool $table $chain"
    done
}
# Surfing tears its chains down and rebuilds them on every service restart, so
# a rule inserted once at boot is gone the next time the user toggles it.
# Watch the chains and put the rule back; stop when Surfing is gone or off.
# Started from boot, not from apply, so it keeps running on boots where apply
# exits early.
watch_surfing_bypass() {
    surfing_present || return 0
    trap 'exit 0' TERM INT
    while surfing_present; do
        ensure_surfing_bypass
        sleep 5
    done
    log 'Surfing bypass watch stopped'
}
drop_surfing_bypass() {
    surfing_chains | while read -r tool table chain; do
        while "$tool" -w 5 -t "$table" -D "$chain" -m owner --uid-owner 1000 -m comment --comment "$RULE_TAG" -j RETURN >/dev/null 2>&1; do :; done
    done
}
# init plus the runtime processes that must see the candidate. The permission
# controller entry is optional: when absent it is spawned later by the role
# bootstrap and inherits the candidate view from zygote.
watched_pids() {
    printf '1\n'
    for process in system_server zygote64 zygote com.android.phone; do
        pids=$(pidof "$process" 2>/dev/null || true)
        case "$process" in system_server|com.android.phone) [ -n "$pids" ] || return 1;; esac
        for pid in $pids; do case "$pid" in ''|*[!0-9]*) return 1;; *) printf '%s\n' "$pid";; esac; done
    done
    for pid in $(pidof com.google.android.permissioncontroller 2>/dev/null || true); do printf '%s\n' "$pid"; done
}
# Fetch the official Fossify release only while the package is absent; an
# installed copy is never replaced, downgraded or touched.
ensure_fossify() {
    run pm path "$APP" 2>/dev/null | grep -q '^package:' && return 0
    busybox=/data/adb/ksu/bin/busybox
    staged=/data/local/tmp/scr01-fossify-messages.apk
    say "Fossify Messages absent; fetching $FOSSIFY_URL"
    rm -f "$staged"
    "$busybox" wget -q -O "$staged" "$FOSSIFY_URL" 2>/dev/null || wget -q -O "$staged" "$FOSSIFY_URL" 2>/dev/null || {
        rm -f "$staged"; say 'Download failed; install Fossify Messages manually from the URL above and reboot'; return 1; }
    [ "$(hash "$staged")" = "$FOSSIFY_SHA" ] || { rm -f "$staged"; say 'Downloaded Fossify APK hash mismatch'; return 1; }
    output=$(timeout -k 5s 180s pm install -r --user 0 "$staged" 2>&1)
    status=$?
    rm -f "$staged"
    if [ "$status" = 0 ] && printf '%s\n' "$output" | grep -q 'Success' && run pm path "$APP" 2>/dev/null | grep -q '^package:'; then
        say 'Fossify Messages installed from the official release'
        return 0
    fi
    say "Fossify install failed: $output"
    return 1
}
