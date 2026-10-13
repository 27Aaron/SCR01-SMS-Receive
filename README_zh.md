# SCR01 SMS Receive

一个精简、自包含的模块：让 SCR01 恢复短信收发。
[English](README.md) · 简体中文

## 兼容性

| 项目     | 支持目标                                          |
| -------- | ------------------------------------------------- |
| 设备     | Samsung SCR-01 / SM-H412J                         |
| 产品     | Galaxy 5G Mobile Wi-Fi                            |
| 固件     | `SCR01KDU1AVK2` 精确匹配                          |
| Android  | 11                                                |
| Root     | 已有 KernelSU-Next 环境（见前提）                 |
| 短信应用 | Fossify Messages（缺失时自动从官方 Release 下载） |
| SIM      | 任意运营商，IMS APN 跟随实际插入的 SIM            |

## 前提

- **本模块是 KernelSU 模块，设备必须已经 Root。**
- 尚未 Root 的设备，可先用 [SCRoot](https://github.com/hackintoanetwork/SCRoot)
  完成 SCR01 一键提权与 KernelSU-Next 环境安装，再回来安装本模块。
- 需要 `/data/adb/ksu/bin/busybox` 可用（SCRoot / KernelSU-Next 环境自带）。
- SIM 已插入并注册网络。
- 所有脚本硬校验固件指纹；指纹或 payload 哈希不符时安全拒绝运行，不做任何更改。

## 工作原理

出厂固件的 `config_sms_capable=false`，导致短信角色在角色注册表里根本不存在，
任何短信应用都无法启动。每次开机，在 root 武装、SIM 就绪之后，模块会：

1. **确保 Fossify Messages 已安装**——缺失时从官方 GitHub Release 下载
   （固定 URL + SHA256 校验）；已安装的副本永远不会被替换或降级。
2. **启用候选主题覆盖**——将固定哈希的候选 Cinnamon 覆盖（原 manifest 与
   配色不变，仅新增 `bool/config_sms_capable=true`）bind mount 到
   `/product/overlay/AccentColorCinnamon/AccentColorCinnamonOverlay.apk`。
   先绑定 init 挂载命名空间，使框架重新拉起的 idmap2d 按候选文件生成正确的
   idmap，再通过标准 OverlayManager 启用。
3. **引导 SMS 角色**——在能力为 true 时制造一次包状态变化，促使角色注册表
   重新评估并把角色授予 Fossify；shell 角色 API 作为兜底。
4. **重启电话进程**（每开机至多一次）——让收信处理器重新读取能力缓存。
5. **IMS 链路（尽力而为，失败不阻断）**——为当前 SIM 插入一条模块持有的
   IMS APN，并开启 volte/smsip 开关。

每一项改动在发生之前都会记录到 `/data/adb/scr01_sms_receive_state`。
某次运行失败只是非零退出，下次开机从现状继续收敛，模块从不停用自身。

> [!NOTE]
> 唯一的可见副作用是系统强调色变为 Cinnamon（肉桂色）——模块借用的正是
> 这条三星自有的换色通道。

## 安装

```sh
adb push SCR01-SMS-Receive-v0.1.2.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/SCR01-SMS-Receive-v0.1.2.zip'"
adb reboot
```

- Fossify Messages 缺失时，首次激活会从
  `https://github.com/FossifyOrg/Messages/releases/download/1.10.1/messages-25-foss-release.apk`
  （SHA256 `af81e85e…dab59703d`）下载并以 root 安装；离线设备会提示
  手动安装后重启重试。
- 激活发生在开机后（root 武装、SIM 就绪）。观察
  `/data/adb/scr01_sms_receive_state/run.log`，出现
  `Active: capability true, role=org.fossify.messages` 即成功。

## 回退与卸载

```sh
# 还原全部改动（角色、启用状态、IMS 开关、持有 APN、overlay、全部绑定），
# 模块本身保留
adb shell "su -c '/data/adb/ksu/bin/busybox sh /data/adb/modules/scr01_sms_receive/rollback.sh'"

# 如需彻底移除模块：先回退，再到 KernelSU 管理器里卸载
```

- 回退后重启一次，清理电话进程的能力缓存。
- 状态目录 `/data/adb/scr01_sms_receive_state` 在卸载时有意保留供核查，
  回退确认无误后可手动删除。
- 若同一开机内电话进程已被模块重启过，回退会如实提示缓存恢复未确认——
  属预期行为，重启即可。

## 已知限制

- 首次激活依赖网络下载 Fossify（仅当未安装）；离线时手动安装后重启。
- 每开机电话进程会被重启一次，移动数据或热点可能闪断几秒。
- 开启 volte 不代表语音通话可用。
- 角色引导要求 Fossify 是唯一有资格的短信应用；若其他应用已持有 SMS 角色，
  模块会拒绝运行而不是抢夺角色。
- 换卡前先回退——模块持有按旧 SIM 建立的 IMS APN 时，SIM numeric 变化会被
  拒绝并提示先回退。
- 仅在一台设备上验证；核心机制在该设备上端到端实测通过，未做第二台设备测试。

## 来源与致谢

- 本模块基于 earrmouth（https://github.com/earrmouth ）分享的 SCR01 短信模块精简而来
- Fossify Messages：<https://github.com/FossifyOrg/Messages>（GPL-3.0，
  由官方 Release 分发）
- Root 环境：[SCRoot](https://github.com/hackintoanetwork/SCRoot) /
  KernelSU-Next，由设备环境提供；本模块不含任何 root 组件。
- overlay 候选派生自本固件自带的主题覆盖，仅新增
  `bool/config_sms_capable=true`；其余权利归相应权利人所有。
