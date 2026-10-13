# SCR01 SMS Receive

A minimal, self-contained module that brings SMS send and receive back to
the SCR01.

English · [简体中文](README_zh.md)

## Compatibility

| Item     | Supported target                                                      |
| -------- | --------------------------------------------------------------------- |
| Device   | Samsung SCR-01 / SM-H412J                                             |
| Product  | Galaxy 5G Mobile Wi-Fi                                                |
| Firmware | `SCR01KDU1AVK2` exact match                                           |
| Android  | 11                                                                    |
| Root     | Existing KernelSU-Next environment (see Prerequisites)                |
| SMS app  | Fossify Messages (auto-fetched from the official release when absent) |
| SIM      | Any operator; the owned IMS APN follows the inserted SIM              |

## Prerequisites

- **This is a KernelSU module: the device must already be rooted.**
- Not rooted yet? Use [SCRoot](https://github.com/hackintoanetwork/SCRoot)
  for one-click rooting and the KernelSU-Next setup on the SCR01, then come
  back and install this module.
- `/data/adb/ksu/bin/busybox` must be available (bundled with SCRoot /
  KernelSU-Next).
- A SIM card inserted and registered.
- Every script hard-checks the firmware fingerprint; a mismatched
  fingerprint or payload hash safely stops the run with no changes made.

## How it works

The stock firmware ships `config_sms_capable=false`, so the SMS role does not
even exist in the role registry and no SMS app can start. On every boot, after
root arms and the SIM loads, the module:

1. **Ensures Fossify Messages is installed** — fetched from the official
   GitHub release (pinned URL + SHA256) when absent; an installed copy is
   never replaced or downgraded.
2. **Enables the candidate theme overlay** — the pinned candidate Cinnamon
   overlay (original manifest and colors, plus `bool/config_sms_capable=true`)
   is bind-mounted over
   `/product/overlay/AccentColorCinnamon/AccentColorCinnamonOverlay.apk`.
   The init mount namespace is bound first so the framework-respawned idmap2d
   regenerates the idmap from the candidate, then the overlay is enabled
   through the standard OverlayManager.
3. **Bootstraps the SMS role** — a package-state change while the capability
   is true makes the role registry re-evaluate and grant the role to Fossify,
   with the shell role API as a fallback.
4. **Restarts the phone process** (at most once per boot) — the inbound-SMS
   handler re-reads the capability cache.
5. **IMS link, best effort and never fatal** — one owned IMS APN for the
   inserted SIM plus the volte/smsip switches.

Every mutation is journaled to `/data/adb/scr01_sms_receive_state` before it
happens. A failed run simply exits non-zero; the next boot converges from
whatever state it finds, and the module never disables itself.

> [!NOTE]
> The only visible side effect is the system accent color switching to
> Cinnamon — that Samsung color channel is exactly what the module rides on.

## Install

```sh
adb push SCR01-SMS-Receive-v0.1.2.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/SCR01-SMS-Receive-v0.1.2.zip'"
adb reboot
```

- When Fossify Messages is missing, first activation fetches it from
  `https://github.com/FossifyOrg/Messages/releases/download/1.10.1/messages-25-foss-release.apk`
  (SHA256 `af81e85e…dab59703d`) and installs it as root; offline devices get
  a message to install it manually and reboot.
- Activation runs after boot once root is armed and the SIM is loaded. Watch
  `/data/adb/scr01_sms_receive_state/run.log` for
  `Active: capability true, role=org.fossify.messages`.

## Rollback and uninstall

```sh
# Restore everything (role, enabled state, IMS switches, owned APN, overlay,
# all binds); the module itself stays installed
adb shell "su -c '/data/adb/ksu/bin/busybox sh /data/adb/modules/scr01_sms_receive/rollback.sh'"

# To remove the module entirely: roll back first, then uninstall in the
# KernelSU manager
```

- Reboot once after rollback to clear the phone capability cache.
- The state directory `/data/adb/scr01_sms_receive_state` is intentionally
  preserved on uninstall for inspection; delete it manually after a verified
  rollback.
- If the phone process was restarted earlier in the same boot, rollback
  reports the cache recovery as unconfirmed — expected, reboot to clear it.

## Known limitations

- First activation needs network access to fetch Fossify (only when it is not
  installed); offline, install it manually and reboot.
- The phone process is restarted once per boot; mobile data or hotspot may
  blip for a few seconds.
- volte being enabled does not imply voice calling works.
- The role bootstrap expects Fossify to be the only eligible SMS app; if
  another package already holds the SMS role, the module refuses to run
  instead of stealing it.
- Swap SIM cards only after a rollback — while an owned IMS APN exists, a
  changed SIM numeric is refused with a rollback-first hint.
- Validated on one device; the core mechanism was verified end to end on that
  device, but no second-device testing has been done.

## Credits

- Based on the SCR01 SMS module shared by Earrmouth (https://github.com/earrmouth)
- Fossify Messages: <https://github.com/FossifyOrg/Messages> (GPL-3.0,
  distributed from the official releases)
- Root environment: [SCRoot](https://github.com/hackintoanetwork/SCRoot) /
  KernelSU-Next, provided by the device; this module contains no root
  components of its own.
- The overlay candidate derives from this firmware's own theme overlay with
  only `bool/config_sms_capable=true` added; all other rights remain with
  their respective owners.
