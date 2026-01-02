#!/bin/bash

# Zabbix-Telegram 알림 스크립트 (그래프 포함)
# Zabbix 7 버전 호환

# --- 사용자 정의 설정 시작 ---
# Telegram Bot 토큰: @BotFather를 통해 얻은 토큰을 여기에 입력하세요.
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN_HERE"

# Zabbix 웹 인터페이스 URL: Zabbix 프런트엔드의 기본 URL
# 예: "http://your_zabbix_server/zabbix" 또는 "https://your_zabbix_server"
ZABBIX_URL="YOUR_ZABBIX_WEB_INTERFACE_URL_HERE"

# 그래프를 가져올 Zabbix 사용자 이름 및 비밀번호
# 이 사용자는 Zabbix API 접근 권한과 알림 대상 호스트/아이템에 대한 읽기 권한이 있어야 합니다.
ZABBIX_API_USER="YOUR_ZABBIX_API_USERNAME"
ZABBIX_API_PASSWORD="YOUR_ZABBIX_API_PASSWORD"

# 그래프 전송 활성화 (1: 활성화, 0: 비활성화)
GRAPHS_ENABLED=1

# 임시 그래프 이미지 저장 디렉터리 (Zabbix 서버에서 쓰기 가능한 경로)
GRAPHS_DIR="/tmp/zabbix_graphs"

# cURL 타임아웃 (초)
CURL_TIMEOUT=15

# 디버그 모드 (1: 활성화, 0: 비활성화)
# 디버그 로그는 스크립트 실행 경로의 telegram_debug.log 파일에 저장됩니다.
DEBUG_MODE=0
# --- 사용자 정의 설정 끝 ---

# --- 내부 변수 (수정하지 마세요) ---
TELEGRAM_API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
DEBUG_LOG_FILE="$(dirname "$0")/telegram_debug.log"

# 디버그 로깅 함수
debug_log() {
    if [ "${DEBUG_MODE}" -eq 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $1" >> "${DEBUG_LOG_FILE}"
    fi
}

# 인자 파싱
TO="$1"
SUBJECT="$2"
MESSAGE="$3"

debug_log "스크립트 시작: TO='${TO}', SUBJECT='${SUBJECT}', MESSAGE='${MESSAGE}'"

# 그래프 디렉터리 생성 (존재하지 않을 경우)
mkdir -p "${GRAPHS_DIR}"
if [ $? -ne 0 ]; then
    debug_log "ERROR: 그래프 디렉터리 '${GRAPHS_DIR}'를 생성할 수 없습니다. 권한을 확인하세요."
    echo "ERROR: Could not create graphs directory. Check permissions."
    exit 1
fi

# Zabbix API 토큰 획득 함수
get_zabbix_api_token() {
    debug_log "Zabbix API 토큰 획득 시도..."
    AUTH_RESPONSE=$(curl -s -X POST -H 'Content-Type: application/json-rpc' \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"user.login\",
            \"params\": {
                \"user\": \"${ZABBIX_API_USER}\",
                \"password\": \"${ZABBIX_API_PASSWORD}\"
            },
            \"id\": 1
        }" \
        "${ZABBIX_URL}/api_jsonrpc.php" --max-time "${CURL_TIMEOUT}")

    debug_log "Zabbix API 로그인 응답: ${AUTH_RESPONSE}"

    ZABBIX_API_TOKEN=$(echo "${AUTH_RESPONSE}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', ''))")

    if [ -z "${ZABBIX_API_TOKEN}" ]; then
        debug_log "ERROR: Zabbix API 토큰을 얻지 못했습니다. 사용자 이름, 비밀번호 또는 Zabbix URL을 확인하세요."
        return 1
    fi
    debug_log "Zabbix API 토큰 획득 성공: ${ZABBIX_API_TOKEN}"
    echo "${ZABBIX_API_TOKEN}"
    return 0
}

# 그래프 이미지 다운로드 함수
download_graph_image() {
    local itemid="$1"
    local period="$2"
    local width="$3"
    local height="$4"
    local filename="$5"
    local api_token="$6"

    debug_log "그래프 다운로드 시도: itemid=${itemid}, period=${period}, width=${width}, height=${height}, filename=${filename}"

    # Zabbix API를 통해 그래프 이미지 URL 생성
    local graph_url="${ZABBIX_URL}/chart.php?itemids%5B%5D=${itemid}&period=${period}&width=${width}&height=${height}&resourcetype=0&output=0&profileIdx=web.graphs.filter"

    # API를 통해 인증된 세션으로 그래프 이미지 다운로드
    curl -s -o "${filename}" \
        --cookie "zbx_sessionid=${api_token}" \
        "${graph_url}" --max-time "${CURL_TIMEOUT}"

    if [ $? -ne 0 ] || [ ! -s "${filename}" ]; then
        debug_log "ERROR: 그래프 이미지 다운로드 실패 또는 파일이 비어있음: ${graph_url}"
        return 1
    fi
    debug_log "그래프 이미지 다운로드 성공: ${filename}"
    return 0
}

# 그래프 전송
send_graphs() {
    local full_message="$1"
    local chat_id="$2"
    local api_token="$3"
    local graph_files=()
    local graph_captions=()
    local graph_counter=0

    # 메시지에서 그래프 정보를 추출
    # 예: <graph:12345:3600:900:200>
    IFS=$'\n' read -r -d '' -a graph_matches < <(grep -oP '<graph:\K[^>]+' <<< "${full_message}")
    debug_log "그래프 매치 결과: ${graph_matches[@]}"

    if [ ${#graph_matches[@]} -eq 0 ]; then
        debug_log "메시지에서 그래프 정보를 찾을 수 없습니다."
        return 0 # 그래프가 없으면 아무것도 안 함
    fi

    for graph_info in "${graph_matches[@]}"; do
        IFS=':' read -r itemid period width height <<< "${graph_info}"

        if [ -z "${itemid}" ] || [ -z "${period}" ] || [ -z "${width}" ] || [ -z "${height}" ]; then
            debug_log "WARNING: 불완전한 그래프 정보가 감지되었습니다: ${graph_info}. 건너뜁니다."
            continue
        fi

        # 기본값 설정 (명시되지 않은 경우)
        period=${period:-3600} # 1시간
        width=${width:-900}
        height=${height:-200}

        local graph_filename="${GRAPHS_DIR}/graph_${RANDOM}_${itemid}.png"

        if download_graph_image "${itemid}" "${period}" "${width}" "${height}" "${graph_filename}" "${api_token}"; then
            graph_files+=("${graph_filename}")
            graph_captions+=("아이템 ID: ${itemid} (기간: $((${period}/3600))시간)")
            graph_counter=$((graph_counter + 1))
        else
            debug_log "WARNING: 아이템 ID ${itemid}에 대한 그래프 다운로드 실패."
        fi
    done

    if [ ${#graph_files[@]} -eq 0 ]; then
        debug_log "다운로드에 성공한 그래프가 없습니다."
        return 0
    fi

    debug_log "다운로드된 그래프 수: ${#graph_files[@]}"

    # Telegram으로 이미지 전송
    for i in "${!graph_files[@]}"; do
        local file="${graph_files[$i]}"
        local caption="${graph_captions[$i]}"

        debug_log "Telegram으로 그래프 전송 시도: ${file} (캡션: ${caption})"
        UPLOAD_RESPONSE=$(curl -s -X POST -F "chat_id=${chat_id}" \
            -F "photo=@${file}" \
            -F "caption=${caption}" \
            "${TELEGRAM_API_URL}/sendPhoto" --max-time "${CURL_TIMEOUT}")

        debug_log "Telegram 그래프 전송 응답: ${UPLOAD_RESPONSE}"

        if ! echo "${UPLOAD_RESPONSE}" | grep -q '"ok":true'; then
            debug_log "ERROR: Telegram으로 그래프 전송 실패: ${UPLOAD_RESPONSE}"
        fi
        rm -f "${file}" # 전송 후 임시 파일 삭제
    done
    return 0
}

# 주 메시지 전송
send_main_message() {
    local message_text="$1"
    local chat_id="$2"

    debug_log "Telegram으로 주 메시지 전송 시도: ${message_text}"
    SEND_RESPONSE=$(curl -s -X POST "${TELEGRAM_API_URL}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=${message_text}" \
        -d "parse_mode=Markdown" \
        --max-time "${CURL_TIMEOUT}")

    debug_log "Telegram 주 메시지 전송 응답: ${SEND_RESPONSE}"

    if ! echo "${SEND_RESPONSE}" | grep -q '"ok":true'; then
        debug_log "ERROR: Telegram으로 주 메시지 전송 실패: ${SEND_RESPONSE}"
        echo "ERROR: Failed to send main message to Telegram."
        exit 1
    fi
    debug_log "Telegram 주 메시지 전송 성공."
}

# --- 메인 로직 시작 ---
# 그래프가 활성화된 경우에만 Zabbix API 토큰 획득 시도
ZABBIX_AUTH_TOKEN=""
if [ "${GRAPHS_ENABLED}" -eq 1 ]; then
    ZABBIX_AUTH_TOKEN=$(get_zabbix_api_token)
    if [ $? -ne 0 ]; then
        debug_log "경고: Zabbix API 토큰 획득에 실패했습니다. 그래프는 전송되지 않습니다."
        GRAPHS_ENABLED=0 # 그래프 전송 비활성화
    fi
fi

# Zabbix 메시지에서 그래프 정보를 제거하고 순수 텍스트 메시지 준비
CLEAN_MESSAGE=$(echo "${MESSAGE}" | sed -E 's/<graph:[^>]+>//g')
FULL_MESSAGE_TEXT="*${SUBJECT}*\n\n${CLEAN_MESSAGE}"

# Telegram으로 주 메시지 전송
send_main_message "${FULL_MESSAGE_TEXT}" "${TO}"

# 그래프 전송 (활성화되어 있고 토큰이 있는 경우)
if [ "${GRAPHS_ENABLED}" -eq 1 ] && [ -n "${ZABBIX_AUTH_TOKEN}" ]; then
    send_graphs "${MESSAGE}" "${TO}" "${ZABBIX_AUTH_TOKEN}"
fi

debug_log "스크립트 종료."
exit 0
