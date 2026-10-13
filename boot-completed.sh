#!/system/bin/sh
MODDIR=${0%/*}
[ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || exit 0
# SCRoot arms root late; boot-completed only fires once ksud is up.
/data/adb/ksu/bin/busybox sh "$MODDIR/apply.sh" >/dev/null 2>&1 &
