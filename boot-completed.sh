#!/system/bin/sh
MODDIR=${0%/*}
[ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
# ksud fires this only after root is armed; apply.sh itself waits for boot,
# SIM and SCRoot readiness. The Surfing bypass watch is separate: it has to
# outlive apply.sh and re-insert after every Surfing chain rebuild.
/data/adb/ksu/bin/busybox sh "$MODDIR/apply.sh" >/dev/null 2>&1 &
/data/adb/ksu/bin/busybox sh -c '. "$1/common.sh"; watch_surfing_bypass' _ "$MODDIR" >/dev/null 2>&1 &
