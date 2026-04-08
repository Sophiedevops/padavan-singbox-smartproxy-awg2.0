#!/bin/sh
# ===================================================================
# ИДЕАЛЬНЫЙ СБОРЩИК: Фильтр мертвых серверов + Lua Парсер + JQ Мердж
# ===================================================================

# Принудительно переходим в директорию, где лежит скрипт
cd "$(dirname "$0")" || exit 1

CONFIG_DIR="configs"
BASE_JSON="base.json"
RUN_JSON="run.json"
LUA_SCRIPT="parse_conf.lua"

REQUIRE_PING=0 
TIMEOUT=2

echo ">>> Запуск расширенной проверки серверов (DoH + UDP DNS)..."

# Парсер Endpoint'ов
get_server_addr() {
    grep -im 1 "^[[:space:]]*Endpoint" "$1" | awk -F '=' '{print $2}' | tr -d ' ' | sed 's/:[0-9]*$//' | tr -d '[]'
}

# Функция: параноидальный резолв домена
resolve_domain() {
    local domain="$1"
    local ip=""
    
    # 1. Системный резолв
    ip=$(ping -c 1 -W 1 "$domain" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then echo "$ip"; return 0; fi
    
    # 2. ЗАШИФРОВАННЫЙ DNS over HTTPS
    ip=$(wget --no-check-certificate -qO- "https://dns.google/resolve?name=$domain&type=A" 2>/dev/null | grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | head -n 1 | awk -F'"' '{print $4}')
    if [ -n "$ip" ]; then echo "$ip"; return 0; fi

    ip=$(wget --no-check-certificate -qO- "https://dns.alidns.com/resolve?name=$domain&type=1" 2>/dev/null | grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | head -n 1 | awk -F'"' '{print $4}')
    if [ -n "$ip" ]; then echo "$ip"; return 0; fi

    ip=$(wget --no-check-certificate -qO- --header="accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=$domain&type=A" 2>/dev/null | grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | head -n 1 | awk -F'"' '{print $4}')
    if [ -n "$ip" ]; then echo "$ip"; return 0; fi

    # 3. КЛАССИЧЕСКИЙ UDP DNS
    local dns_list="77.88.8.8 94.140.14.14 8.8.8.8 1.1.1.1 223.5.5.5 9.9.9.9"
    for dns in $dns_list; do
        ip=$(nslookup "$domain" "$dns" 2>/dev/null | awk '/^Name:/ {in_answer=1} in_answer && /^Address/ {print}' | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        if [ -n "$ip" ]; then echo "$ip"; return 0; fi
    done
    return 1
}

rm -rf configs_valid && mkdir -p configs_valid

# === БЛОК ПРОВЕРКИ ===
for FILE in "$CONFIG_DIR"/*.conf; do
    [ -e "$FILE" ] || continue
    FILENAME=$(basename "$FILE")
    ADDR=$(get_server_addr "$FILE")
    [ -z "$ADDR" ] && continue

    TARGET_IP="$ADDR"
    if echo "$ADDR" | grep -q '[A-Za-z]'; then
        TARGET_IP=$(resolve_domain "$ADDR")
        if [ -z "$TARGET_IP" ]; then
            echo "❌ АЛЕРТ: Домен $ADDR ($FILENAME) мертв! Выкидываем."
            continue
        fi
        echo "✅ Домен $ADDR жив -> $TARGET_IP"
    fi
    cp "$FILE" "configs_valid/$FILENAME"
done

# === БЛОК СБОРКИ ===
EP_ARRAY="/tmp/sb_eps_$$.json"
TAGS_ARRAY="/tmp/sb_tags_$$.json"
echo "[]" > "$EP_ARRAY"
echo "[]" > "$TAGS_ARRAY"

echo ">>> Начинаем сборку конфигурации из живых серверов..."

for conf_file in configs_valid/*.conf; do
    [ -e "$conf_file" ] || continue
    tag_name=$(basename "$conf_file" .conf)
    echo -n "Конвертация: $tag_name... "
    ep_json=$(lua "$LUA_SCRIPT" "$conf_file" "$tag_name")
    
    if [ $? -eq 0 ] && [ -n "$ep_json" ]; then
        jq --argjson new_ep "$ep_json" '. + [$new_ep]' "$EP_ARRAY" > "${EP_ARRAY}.tmp" && mv "${EP_ARRAY}.tmp" "$EP_ARRAY"
        jq --arg tag "$tag_name" '. + [$tag]' "$TAGS_ARRAY" > "${TAGS_ARRAY}.tmp" && mv "${TAGS_ARRAY}.tmp" "$TAGS_ARRAY"
        echo "ОК"
    else
        echo "ПРОПУСК"
    fi
done

URLTEST_OUTBOUND=$(jq -n --argjson tags "$(cat "$TAGS_ARRAY")" '{"type":"urltest","tag":"auto-balancer","outbounds":$tags,"url":"https://www.cloudflare.com/cdn-cgi/trace","interval":"3m","tolerance":50}')
jq --argjson eps "$(cat "$EP_ARRAY")" --argjson urltest "$URLTEST_OUTBOUND" '.endpoints = ($eps + (.endpoints // [])) | .outbounds = ([$urltest] + (.outbounds // []))' "$BASE_JSON" > "$RUN_JSON"

rm -f "$EP_ARRAY" "$TAGS_ARRAY" "${EP_ARRAY}.tmp" "${TAGS_ARRAY}.tmp"
rm -rf configs_valid
echo ">>> Сборка успешно завершена! Создан $RUN_JSON с новыми DNS правилами."
