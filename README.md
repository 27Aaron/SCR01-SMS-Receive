# SCR01 SMS Receive

A minimal KernelSU module that brings SMS send and receive back to the SCR01.

English · [简体中文](README_zh.md) · [日本語](README_ja.md) · [한국어](README_ko.md)

## Requirements

| Item | Requirement |
| --- | --- |
| Device | Samsung SCR-01 / SM-H412J |
| Firmware | `SCR01KDU1AVK2` exact match (hard-checked by every script) |
| Android | 11 |
| Root | Required; not rooted yet? Use [SCRoot](https://github.com/hackintoanetwork/SCRoot) for one-click rooting |
| SIM | Any operator; the IMS APN follows the inserted SIM |

`/data/adb/ksu/bin/busybox` must be available (bundled with SCRoot / KernelSU-Next).

## How it works

The stock firmware ships `config_sms_capable=false`, so the SMS role does not exist in the system and no SMS app can start. On every boot the module automatically:

1. Ensures Fossify Messages is installed — fetched from the official release (pinned URL + SHA256) when absent; an installed copy is never replaced;
2. Turns the SMS capability back on through Samsung's own theme-overlay channel;
3. Bootstraps the SMS role and grants it to Fossify;
4. Restarts the phone process once to refresh the receive cache, then configures the IMS APN and the volte/smsip switches (best effort, never fatal);
5. If Surfing's four local proxy/DNS chains exist, inserts a RETURN for system UID 1000 at the head of each so IMS registration is not caught by TPROXY. Surfing drops the rule when it rebuilds a chain; the next boot puts it back, and rollback removes it by its comment. The bypass covers every flow owned by UID 1000, not only IMS.

Failures only log; the next boot retries. Every change is runtime state with per-item journaling, no partition is modified, and `rollback.sh` restores everything. The only visible side effect is the system accent color switching to Cinnamon.

## Install

```sh
adb push SCR01-SMS-Receive-v0.1.2.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/SCR01-SMS-Receive-v0.1.2.zip'"
adb reboot
```

Allow 2-3 minutes after reboot; an `Active:` line in `/data/adb/scr01_sms_receive_state/run.log` means success.

## Known limitations

- Roughly 2-3 minutes after each reboot, sends may report "no service" — just wait.
- Sending depends on IMS registration (receiving is unaffected); if a broken 5G configuration keeps IMS from registering, re-run the appendix procedure and reboot.
- The phone process restarts once per boot; mobile data or hotspot may blip for a few seconds.
- volte being enabled does not imply voice calling works.
- Roll back before swapping SIM cards.

## Rollback and uninstall

```sh
# Restore everything (role, switches, APN, overlay, binds); the module stays
adb shell "su -c '/data/adb/ksu/bin/busybox sh /data/adb/modules/scr01_sms_receive/rollback.sh'"

# To remove entirely: roll back first, then uninstall in the KernelSU manager
```

Reboot once after rollback to clear the phone process cache; the state directory is intentionally preserved for inspection and can be deleted once verified.

## Appendix: enabling 5G (Samsung service mode)

The device camps on 4G by default; the procedure below enables 5G (including SA) at the modem level and takes effect after a reboot:

1. Settings → About → Status → Phone number — **tap it quickly 10 times** to enter DRParser Mode;
2. Type `*#0011#` to enter Service Mode;
3. Tap the top-right menu → tap Back once → tap Key input;
4. Enter an uppercase `Q` and confirm, then wait about a minute for the main menu;
5. Navigate `[2] UE SETTING & INFO` → `[1] SETTING` → `[1] PROTOCOL` → `[9] NR` → `[2] allow list control` → `[2] allow list off` (shows APLY success); tap the top-right menu, tap Back twice to return to the parent list;
6. Enter `[1] nr5g sa/nsa mode control` → `[1] sa/nsa enable` and reboot the device when prompted.

To type an uppercase Q on the default 9-key IME: tap the globe icon at the bottom-left to switch to English, tap `A/a` for uppercase, then tap `PQRS` twice.

## Credits

- Based on the SCR01 SMS module shared by Earrmouth (https://github.com/earrmouth)
- Fossify Messages: <https://github.com/FossifyOrg/Messages> (GPL-3.0, distributed from the official releases)
- Root environment: [SCRoot](https://github.com/hackintoanetwork/SCRoot) / KernelSU-Next, provided by the device; this module contains no root components of its own.
- The overlay candidate derives from this firmware's own theme overlay with only `bool/config_sms_capable=true` added; all other rights remain with their respective owners.
