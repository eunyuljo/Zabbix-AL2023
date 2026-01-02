# 이해를 위한 예시

## 기능

- **개인 알림:** `<<personal_chat_id>>`로 그래프가 포함된 직접 메시지
- **채널 알림:** `customer-alert` 채널로 그래프가 포함된 브로드캐스트 알림
- **그래프 통합:** 자동 Zabbix 그래프 생성 및 전송
- **단일 봇 아키텍처:** 하나의 봇이 모든 대상을 처리

## 봇 정보

- **토큰:** `<<bot_token>>`
- **개인 채팅 ID:** `<<personal_chat_id>>`
- **채널 ID:** `-<<chat_id>>`
- **채널명:** `customer-alert`

## ⚙️ 설정

### zbxtg_settings.py

주요 설정:

```python
# 봇 설정
tg_token = "<<bot_token>>"

# Zabbix API 접근
zbx_server = "http://ALB_DNS/zabbix"
zbx_api_user = "Admin"
zbx_api_pass = "zabbix"

# 채널 권한
zbx_tg_daemon_enabled_chats = ["customer-alert"]
zbx_tg_daemon_enabled_ids = [-<<chat_id>>]
```

## 🚀 사용 예제

### 개인 알림
```bash
sudo -u zabbix ./zbxtg.py "<<personal_chat_id>>" "서버 알림" "web-01에서 CPU 사용량이 높습니다"
```

### 채널 알림
```bash
sudo -u zabbix ./zbxtg.py "-<<chat_id>>" "네트워크 알림" "스위치 연결이 끊어졌습니다" --channel
```

### 그래프 포함
```bash
sudo -u zabbix ./zbxtg.py "<<personal_chat_id>>" "성능 알림" "zbxtg;graphs
zbxtg;itemid:50745
zbxtg;title:지난 1시간 CPU 성능"
```

## 🔧 Zabbix 미디어 타입 설정

**미디어 타입 구성:**
- **이름:** `고객사 텔레그램`
- **타입:** `스크립트`
- **스크립트 이름:** `customer/zbxtg.py`
- **스크립트 매개변수:**
  1. `{ALERT.SENDTO}`
  2. `{ALERT.SUBJECT}`
  3. `{ALERT.MESSAGE}`
  4. 채널용 사용자 정의 매개변수: `--channel` (조건부)
  5. 그룹용 사용자 정의 매개변수: `--group` (조건부)

**사용자 미디어 구성:**
- **개인:** `<<personal_chat_id>>`로 전송
- **채널:** `--channel` 매개변수와 함께 `-<<chat_id>>`으로 전송

## ⚠️ 중요 사항

### 인수 순서
채널 플래그는 반드시 마지막에:
```bash
# ✅ 올바름
zbxtg.py "채팅ID" "제목" "메시지" --channel

# ❌ 잘못됨
zbxtg.py --channel "채팅ID" "제목" "메시지"
```

### 의존성
- 가상 환경: `/var/lib/zabbix/zbxtg/venv/`
- 필요한 패키지가 설치된 Python 3
- 그래프 생성을 위한 Zabbix 웹 UI 접근

## 🔍 문제 해결

**일반적인 문제:**
1. **"chat not found"** → 인수 순서와 채널 권한 확인
2. **그래프 실패** → Zabbix API 자격증명과 아이템 접근 권한 확인
3. **권한 에러** → 파일이 `zabbix` 사용자 소유인지 확인

**테스트 명령어:**
```bash
# 개인 채팅 테스트
sudo -u zabbix ./zbxtg.py "<<personal_chat_id>>" "테스트" "개인 테스트 메시지"

# 채널 테스트
sudo -u zabbix ./zbxtg.py "-<<chat_id>>" "테스트" "채널 테스트 메시지" --channel

# 그래프 테스트
sudo -u zabbix ./zbxtg.py "<<personal_chat_id>>" "그래프 테스트" "zbxtg;graphs
zbxtg;itemid:50745
zbxtg;title:테스트 그래프"
```

## 📊 그래프 명령어 참조

### 기본 그래프
```
zbxtg;graphs
zbxtg;itemid:아이템ID
zbxtg;title:그래프 제목
```

### 고급 옵션
```
zbxtg;graphs
zbxtg;itemid:50745,50746,50747
zbxtg;title:다중 아이템 그래프
zbxtg;graphs_period:7200
zbxtg;graphs_width:1200
zbxtg;graphs_height:300
```

## 🛠️ 설치 및 업그레이드

### 초기 설치
```bash
# 가상 환경 확인
ls -la /var/lib/zabbix/zbxtg/venv/

# 권한 설정
sudo chown -R zabbix:zabbix /usr/lib/zabbix/alertscripts/customer/
sudo chmod +x /usr/lib/zabbix/alertscripts/customer/zbxtg.py

# 캐시 디렉토리 생성
sudo mkdir -p /tmp/zbxtg
sudo chown zabbix:zabbix /tmp/zbxtg
```

### 설정 업데이트
```bash
# 설정 파일 편집
sudo nano customer/zbxtg_settings.py

# 구성 테스트
sudo -u zabbix python3 -c "import zbxtg_settings; print('설정 로드 성공')"
```

## 캐시 관련 정리

  1. /tmp/zbxtg/uids.txt - 메인 UID 캐시
  포맷: 사용자명;타입;채팅ID
  예시:
  customer-alert;channel;-1003682743283
  myusername;private;758619717

  2. /tmp/zbxtg/cache_-1003682743283 - 개별 채널 캐시
  포맷: 채널명;타입;채팅ID
  내용: customer-alert;channel;-1003682743283

zbxtg.py의 캐시 로직 (zbxtg.py:805-817)

# 1단계: 캐시에서 UID 찾기
uid = tg.get_uid_from_cache(zbx_to)

# 2단계: 캐시에 없으면 API로 조회
if not uid:
    uid = tg.get_uid(zbx_to)  # Telegram API 호출
    tmp_need_update = True    # 캐시 업데이트 필요 표시

# 3단계: 새로 찾은 UID를 캐시에 저장
if tmp_need_update:
    tg.update_cache_uid(zbx_to, str(uid).rstrip())

⚠️ 캐시 문제가 생기는 경우

1. 권한 문제:
# 캐시 폴더가 root 소유여서 zabbix가 쓸 수 없음
drwxr-xr-x.  2 root   root     80 Jan  2 07:31 /tmp/zbxtg/

2. 파일 누락:
# uids.txt가 없으면 캐시를 읽을 수 없음
ls: cannot access '/tmp/zbxtg/uids.txt': No such file or directory

3. 캐시 데이터 불일치:
# 채널 ID가 바뀌었는데 캐시에는 옛날 정보
# 또는 봇이 채널에서 제거되었는데 캐시에는 남아있음

🛠️ 캐시 문제 해결법

캐시 초기화:
# 모든 캐시 삭제 후 재생성
sudo rm -rf /tmp/zbxtg/*
sudo mkdir -p /tmp/zbxtg
sudo chown -R zabbix:zabbix /tmp/zbxtg
sudo chmod 755 /tmp/zbxtg

수동 캐시 생성:
# uids.txt에 직접 추가
echo "customer-alert;channel;-1003682743283" >> /tmp/zbxtg/uids.txt
echo "758619717;private;758619717" >> /tmp/zbxtg/uids.txt

디버그 모드로 캐시 동작 확인:
sudo -u zabbix ./zbxtg.py "-1003682743283" "캐시 테스트" "메시지" --channel --debug

