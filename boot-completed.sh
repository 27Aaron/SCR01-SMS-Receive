#!/system/bin/sh
MODDIR=${0%/*}
[ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
# ksud fires this only after root is armed; apply.sh itself waits for boot,
# SIM and SCRoot readiness.
/data/adb/ksu/bin/busybox sh "$MODDIR/apply.sh" >/dev/null 2>&1 &
