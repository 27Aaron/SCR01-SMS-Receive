#!/system/bin/sh
MODDIR=${0%/*}
/data/adb/ksu/bin/busybox sh "$MODDIR/rollback.sh" || exit 1
# /data/adb/scr01_sms_receive_state is intentionally preserved for
# inspection; delete it manually after a verified rollback.
