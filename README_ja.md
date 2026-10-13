# SCR01 SMS Receive

SCR01 に SMS の送受信を取り戻す、最小構成の KernelSU モジュール。

[English](README.md) · [简体中文](README_zh.md) · 日本語 · [한국어](README_ko.md)

## 動作環境

| 項目 | 要件 |
| --- | --- |
| デバイス | Samsung SCR-01 / SM-H412J |
| ファームウェア | `SCR01KDU1AVK2` 完全一致（スクリプトが厳格に検証） |
| Android | 11 |
| Root | 必須。未対応の場合は [SCRoot](https://github.com/hackintoanetwork/SCRoot) でワンクリック root 化 |
| SIM | 全キャリア対応。IMS APN は挿入された SIM に追従 |

`/data/adb/ksu/bin/busybox` が必要です（SCRoot / KernelSU-Next 環境に同梱）。

## 仕組み

工場ファームウェアでは `config_sms_capable` が false になっており、SMS ロールがシステムに存在しないため、どの SMS アプリも起動できません。本モジュールは起動のたびに自動で以下を実行します：

1. Fossify Messages がインストールされていることを確認 — 未インストールの場合は公式リリースから取得（URL と SHA256 を固定）。インストール済みのコピーは一切置き換えません；
2. Samsung 純正のテーマオーバーレイ経路で SMS 機能をオンに戻します；
3. SMS ロールをブートストラップし、Fossify に付与します；
4. 受信キャッシュを更新するため電話プロセスを一度再起動し、IMS APN と volte/smsip スイッチを設定します（ベストエフォート、失敗しても中断しません）。

失敗はログのみで、次回起動時に再試行します。すべての変更はランタイム状態として項目ごとに記録され、パーティションは一切変更せず、`rollback.sh` で完全に復元できます。唯一の目に見える副作用は、システムのアクセントカラーが Cinnamon に変わることです。

## インストール

```sh
adb push SCR01-SMS-Receive-v0.1.1.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/SCR01-SMS-Receive-v0.1.1.zip'"
adb reboot
```

再起動後 2〜3 分で有効になります。`/data/adb/scr01_sms_receive_state/run.log` に `Active:` の行が出れば成功です。

## 既知の制限

- 再起動後 2〜3 分ほどは送信が「圏外」と表示されることがあります。そのままお待ちください。
- 送信は IMS 登録に依存します（受信は影響なし）。5G 設定の異常で IMS が登録できない場合は、付録の手順を再実行して再起動してください。
- 起動ごとに電話プロセスが一度再起動されるため、モバイルデータやテザリングが数秒切れることがあります。
- volte の有効化は音声通話の可否を保証しません。
- SIM を交換する前にロールバックしてください。

## ロールバックとアンインストール

```sh
# すべての変更を復元（ロール、スイッチ、APN、オーバーレイ、バインド）。モジュールは残ります
adb shell "su -c '/data/adb/ksu/bin/busybox sh /data/adb/modules/scr01_sms_receive/rollback.sh'"

# 完全に削除する場合：先にロールバックし、KernelSU マネージャーでアンインストール
```

ロールバック後は一度再起動して電話プロセスのキャッシュをクリアしてください。状態ディレクトリは検証用に意図的に残されるため、確認後に手動で削除できます。

## 付録：5G の有効化（Samsung エンジニアリングモード）

デバイスはデフォルトで 4G に滞留します。以下の手順でモデムレベルで 5G（SA を含む）を有効化します。再起動後に反映されます：

1. 設定 → 端末情報 → ステータス → 電話番号 を**素早く 10 回タップ**すると DRParser Mode に入ります；
2. `*#0011#` を入力して Service Mode に入ります；
3. 右上のメニュー → Back を一度 → Key input をタップ；
4. 大文字の `Q` を入力して確定し、約 1 分待つとメインメニューに入ります；
5. `[2] UE SETTING & INFO` → `[1] SETTING` → `[1] PROTOCOL` → `[9] NR` → `[2] allow list control` → `[2] allow list off`（APLY success と表示）；右上のメニュー → Back を 2 回で上位階層に戻ります；
6. `[1] nr5g sa/nsa mode control` → `[1] sa/nsa enable` を選び、指示に従って再起動します。

デフォルトの 9 キー入力で大文字 Q を入力する方法：左下の地球アイコンで英語に切り替え、`A/a` で大文字にしてから、`PQRS` を 2 回タップします。

## クレジット

- 本モジュールは Earrmouth（https://github.com/earrmouth ）が共有した SCR01 SMS モジュールをベースに簡素化したものです
- Fossify Messages：<https://github.com/FossifyOrg/Messages>（GPL-3.0、公式リリースから配布）
- Root 環境：[SCRoot](https://github.com/hackintoanetwork/SCRoot) / KernelSU-Next。デバイス環境が提供するもので、本モジュールに root コンポーネントは含まれません。
- オーバーレイ候補は本ファームウェア純正のテーマオーバーレイから派生し、`bool/config_sms_capable=true` のみを追加したものです。その他の権利はそれぞれの権利者に帰属します。
