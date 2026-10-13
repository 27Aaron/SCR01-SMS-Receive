# SCR01 SMS Receive

一个精简的 KernelSU 模块：让 SCR01 恢复短信收发。

[English](README.md) · 简体中文 · [日本語](README_ja.md) · [한국어](README_ko.md)

## 适用条件

| 项目 | 要求 |
| --- | --- |
| 设备 | Samsung SCR-01 / SM-H412J |
| 固件 | `SCR01KDU1AVK2` 精确匹配（脚本硬校验，不符即拒绝运行） |
| Android | 11 |
| Root | 必须已 Root；未 Root 可先用 [SCRoot](https://github.com/hackintoanetwork/SCRoot) 一键提权 |
| SIM | 任意运营商，IMS APN 跟随实际插入的 SIM |

需 `/data/adb/ksu/bin/busybox` 可用（SCRoot / KernelSU-Next 环境自带）。

## 原理

出厂固件把 `config_sms_capable` 置为 false，短信角色因此在系统中不存在，任何短信应用都无法启动。模块在每次开机后自动完成：

1. 确保 Fossify Messages 已安装——缺失时从官方 Release 下载（固定 URL + SHA256 校验），已装的副本永不替换；
2. 借三星自有的主题覆盖通道把短信能力重新打开；
3. 引导 SMS 角色并授予 Fossify；
4. 重启一次电话进程刷新收信缓存，并配置 IMS APN 与 volte/smsip 开关（尽力而为，失败不阻断）；
5. 若 Surfing 的四条本机代理/DNS 链存在，在每条链首插入 system UID 1000 的 RETURN，避免 IMS 注册被 TPROXY 接管。Surfing 重建链会丢掉这条规则，下次开机自动补回；回退时按注释删除。该例外覆盖 UID 1000 的全部流量，不只 IMS。

失败只记日志，下次开机自动重试。所有改动均为运行时状态并逐项记录，不修改任何分区，`rollback.sh` 可完整还原。唯一可见副作用是系统强调色变为 Cinnamon。

## 安装

```sh
adb push SCR01-SMS-Receive-v0.1.2.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/SCR01-SMS-Receive-v0.1.2.zip'"
adb reboot
```

重启后等待 2-3 分钟生效，`/data/adb/scr01_sms_receive_state/run.log` 出现 `Active:` 即成功。

## 已知限制

- 每次重启后约有 2-3 分钟激活窗口，期间发送可能报"无服务"，等待即可。
- 发送依赖 IMS 注册（接收不受影响）；若 5G 配置异常导致 IMS 注册不上，重跑附录流程并重启即可恢复。
- 每开机电话进程重启一次，移动数据或热点可能闪断几秒。
- 开启 volte 不代表语音通话可用。
- 换卡前先回退。

## 回退与卸载

```sh
# 还原全部改动（角色、开关、APN、overlay、绑定），模块保留
adb shell "su -c '/data/adb/ksu/bin/busybox sh /data/adb/modules/scr01_sms_receive/rollback.sh'"

# 彻底移除：先回退，再到 KernelSU 管理器卸载
```

回退后重启一次清理电话进程缓存；状态目录有意保留供核查，确认无误后可手动删除。

## 附录：开启 5G（三星工程模式）

设备默认只驻 4G；以下流程在调制解调器层开启 5G（含 SA），重启后生效：

1. 设置 → 关于 → 状态 → 手机号码，**快速连续点击 10 次**，进入 DRParser Mode；
2. 依次输入 `*#0011#`，进入 Service Mode；
3. 点击右上角菜单 → 点击一次 Back → 再点击 Key input；
4. 输入大写 `Q` 并确认，等待约一分钟进入主菜单；
5. 依次进入 `[2] UE SETTING & INFO` → `[1] SETTING` → `[1] PROTOCOL` → `[9] NR` → `[2] allow list control` → `[2] allow list off`（显示 APLY success）；点击右上角菜单，点击两次 Back 回到上层目录；
6. 进入 `[1] nr5g sa/nsa mode control` → `[1] sa/nsa enable`，按提示重启设备。

默认九宫格输入大写 Q 的方法：点输入法左下角地球图标切到英文，点 `A/a` 切换大写，再点两次 `PQRS`。

## 来源与致谢

- 本模块基于 Earrmouth（https://github.com/earrmouth ）分享的 SCR01 短信模块精简而来
- Fossify Messages：<https://github.com/FossifyOrg/Messages>（GPL-3.0，由官方 Release 分发）
- Root 环境：[SCRoot](https://github.com/hackintoanetwork/SCRoot) / KernelSU-Next，由设备环境提供；本模块不含任何 root 组件。
- overlay 候选派生自本固件自带的主题覆盖，仅新增 `bool/config_sms_capable=true`；其余权利归相应权利人所有。
