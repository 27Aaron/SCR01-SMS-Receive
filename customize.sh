#!/system/bin/sh
MODDIR=$MODPATH
. "$MODDIR/common.sh"
firmware_guard && need_tools || abort 'Unsupported firmware/root or missing tools'
[ "$(hash "$MODDIR/payload/AccentColorCinnamonOverlay.apk")" = "$CANDIDATE" ] || abort 'Payload hash mismatch'
if ! run pm path "$APP" 2>/dev/null | grep -q '^package:'; then
    ui_print 'Fossify Messages is not installed yet.'
    ui_print "It will be fetched at first boot from: $FOSSIFY_URL"
    ui_print 'or install it manually from the official Fossify releases beforehand.'
fi
set_perm_recursive "$MODPATH" 0 0 0755 0644
for script in boot-completed.sh apply.sh rollback.sh uninstall.sh; do set_perm "$MODPATH/$script" 0 0 0755; done
ui_print 'SCR01 SMS Receive 0.1.1 staged; activation runs after SCRoot recovery.'
ui_print 'No firewall/proxy integration; the IMS APN follows the inserted SIM.'
