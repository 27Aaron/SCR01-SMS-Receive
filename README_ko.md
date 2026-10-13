# SCR01 SMS Receive

SCR01에 SMS 송수신 기능을 되돌려주는 최소 구성의 KernelSU 모듈입니다.

[English](README.md) · [简体中文](README_zh.md) · [日本語](README_ja.md) · 한국어

## 요구 사항

| 항목 | 요구 사항 |
| --- | --- |
| 기기 | Samsung SCR-01 / SM-H412J |
| 펌웨어 | `SCR01KDU1AVK2` 정확히 일치(모든 스크립트가 엄격히 확인) |
| Android | 11 |
| 루트 | 필수. 루팅 전이라면 [SCRoot](https://github.com/hackintoanetwork/SCRoot)로 원클릭 루팅 |
| SIM | 모든 사업자; IMS APN은 삽입된 SIM을 따름 |

`/data/adb/ksu/bin/busybox`가 필요합니다(SCRoot / KernelSU-Next 환경에 포함).

## 동작 원리

기본 펌웨어는 `config_sms_capable`이 false여서 SMS 역할이 시스템에 존재하지 않고 어떤 SMS 앱도 시작할 수 없습니다. 이 모듈은 부팅할 때마다 자동으로:

1. Fossify Messages 설치를 확인 — 미설치 시 공식 릴리스에서 다운로드(URL과 SHA256 고정). 설치된 본은 절대 교체하지 않습니다;
2. Samsung 자체 테마 오버레이 채널을 통해 SMS 기능을 다시 켭니다;
3. SMS 역할을 부트스트랩하여 Fossify에 부여합니다;
4. 수신 캐시를 갱신하기 위해 폰 프로세스를 한 번 재시작한 뒤 IMS APN과 volte/smsip 스위치를 구성합니다(최선 노력, 실패해도 중단하지 않음);
5. Surfing의 로컬 프록시/DNS 체인 4개가 있으면 각 맨 앞에 system UID 1000의 RETURN을 넣어 IMS 등록이 TPROXY에 잡히지 않게 합니다. Surfing이 체인을 다시 만들면 규칙은 사라지며, 다음 부팅에 다시 넣고 롤백 시 주석으로 삭제합니다. 이 예외는 UID 1000의 모든 트래픽에 적용되며 IMS만이 아닙니다.

실패는 로그만 남기고 다음 부팅에 재시도합니다. 모든 변경은 런타임 상태로 항목별로 기록되며 파티션은 수정하지 않고, `rollback.sh`로 완전히 복원됩니다. 유일하게 눈에 보이는 부작용은 시스템 강조색이 Cinnamon으로 바뀌는 것입니다.

## 설치

```sh
adb push SCR01-SMS-Receive-v0.1.2.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/SCR01-SMS-Receive-v0.1.2.zip'"
adb reboot
```

재부팅 후 2~3분 기다리면 적용됩니다. `/data/adb/scr01_sms_receive_state/run.log`에 `Active:` 줄이 보이면 성공입니다.

## 알려진 제한

- 재부팅 후 약 2~3분간 발송이 "서비스 없음"으로 표시될 수 있습니다. 기다리면 됩니다.
- 발송은 IMS 등록에 의존합니다(수신은 영향 없음). 5G 설정 이상으로 IMS가 등록되지 않으면 부록 절차를 다시 실행하고 재부팅하세요.
- 부팅마다 폰 프로세스가 한 번 재시작되어 모바일 데이터나 핫스팟이 몇 초 끊길 수 있습니다.
- volte 활성화는 음성 통화 가능을 의미하지 않습니다.
- SIM 교체 전에 먼저 롤백하세요.

## 롤백 및 제거

```sh
# 모든 변경 복원(역할, 스위치, APN, 오버레이, 바인드). 모듈은 유지됩니다
adb shell "su -c '/data/adb/ksu/bin/busybox sh /data/adb/modules/scr01_sms_receive/rollback.sh'"

# 완전히 제거하려면: 먼저 롤백한 뒤 KernelSU 매니저에서 제거
```

롤백 후 한 번 재부팅해 폰 프로세스 캐시를 정리하세요. 상태 디렉터리는 검증용으로 남겨두며 확인 후 수동으로 삭제할 수 있습니다.

## 부록: 5G 활성화(Samsung 서비스 모드)

기기는 기본적으로 4G에 머뭅니다. 아래 절차로 모뎀 수준에서 5G(SA 포함)를 활성화하며 재부팅 후 적용됩니다:

1. 설정 → 디바이스 정보 → 상태 → 전화번호를 **빠르게 10번 탭**하면 DRParser Mode에 진입합니다;
2. `*#0011#`을 입력해 Service Mode에 진입합니다;
3. 오른쪽 위 메뉴 → Back 한 번 → Key input을 탭합니다;
4. 대문자 `Q`를 입력하고 확인하면 약 1분 뒤 메인 메뉴에 들어갑니다;
5. `[2] UE SETTING & INFO` → `[1] SETTING` → `[1] PROTOCOL` → `[9] NR` → `[2] allow list control` → `[2] allow list off`(APLY success 표시); 오른쪽 위 메뉴 → Back 두 번으로 상위로 돌아갑니다;
6. `[1] nr5g sa/nsa mode control` → `[1] sa/nsa enable`을 선택하고 안내에 따라 재부팅합니다.

기본 9키 입력기에서 대문자 Q 입력 방법: 왼쪽 아래 지구본 아이콘으로 영어로 전환하고 `A/a`로 대문자 모드를 켠 뒤 `PQRS`를 두 번 탭합니다.

## 크레딧

- 이 모듈은 Earrmouth(https://github.com/earrmouth )가 공유한 SCR01 SMS 모듈을 간소화한 것입니다
- Fossify Messages: <https://github.com/FossifyOrg/Messages>(GPL-3.0, 공식 릴리스에서 배포)
- 루트 환경: [SCRoot](https://github.com/hackintoanetwork/SCRoot) / KernelSU-Next. 기기 환경에서 제공되며 이 모듈에는 루트 구성 요소가 없습니다.
- 오버레이 후보는 이 펌웨어 자체 테마 오버레이에서 파생되었으며 `bool/config_sms_capable=true`만 추가했습니다. 그 외 권리는 각 권리자에게 있습니다.
