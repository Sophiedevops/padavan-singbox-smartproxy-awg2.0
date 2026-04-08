#!/bin/sh

# === НАСТРОЙКИ ===
INSTALL_DIR="/opt/awg2_singbox"
BACKUP_DIR="${INSTALL_DIR}.bak"
BIN_URL="https://github.com/Sophiedevops/padavan-singbox-smartproxy-awg2.0/releases/download/main/sing-box"
GEOIP_URL="https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set"
GEOSITE_URL="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set"
REPO_RAW="https://raw.githubusercontent.com/Sophiedevops/padavan-singbox-smartproxy-awg2.0/main"

export PATH="/opt/bin:/opt/sbin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH"

echo "=================================================="
echo "    SING-BOX ROUTING SETUP (v2.0) - Padavan Edition"
echo "=================================================="

# === 1. ПРОВЕРКА РЕСУРСОВ И ЗАВИСИМОСТЕЙ ===
echo "[1/6] Проверка системы и зависимостей..."
FREE_RAM=$(free -m | awk '/Mem:/ {print $4}')
[ -z "$FREE_RAM" ] && FREE_RAM=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')
FREE_DISK=$(df -m /opt | awk 'NR==2 {print $4}')

if [ "$FREE_RAM" -lt 25 ] || [ "$FREE_DISK" -lt 50 ]; then
    echo "[ERROR] Мало ресурсов (RAM: ${FREE_RAM}MB, Disk: ${FREE_DISK}MB). Установка прервана."
    exit 1
fi

if [ ! -x "/opt/bin/jq" ] && [ -z "$(which jq 2>/dev/null)" ]; then
    echo "  -> Утилита jq не найдена. Устанавливаем через opkg..."
    /opt/bin/opkg update > /dev/null 2>&1
    /opt/bin/opkg install jq > /dev/null 2>&1
    if [ ! -x "/opt/bin/jq" ]; then
        echo "[ERROR] Не удалось установить jq. Проверьте работу Entware (opkg)!"
        exit 1
    fi
    echo "  -> jq успешно установлен."
fi

# === 2. БЭКАП И ДИРЕКТОРИИ ===
if [ -d "$INSTALL_DIR" ]; then
    echo ""
    echo "Обнаружена предыдущая установка в $INSTALL_DIR!"
    echo "[ 1 ] Сделать бэкап старой папки (в .bak) и установить начисто"
    echo "[ 2 ] Удалить старую папку полностью (Без бэкапа)"
    echo "[ q ] Прервать установку"
    printf "Ваш выбор: "
    read b_choice
    case "$b_choice" in
        1)
            rm -rf "$BACKUP_DIR"
            mv "$INSTALL_DIR" "$BACKUP_DIR"
            echo "Бэкап сохранен в $BACKUP_DIR"
            ;;
        2)
            rm -rf "$INSTALL_DIR"
            echo "Старая папка удалена."
            ;;
        *) echo "Отмена."; exit 0 ;;
    esac
fi
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# === 3. FAIL-FAST: ЗАГРУЗКА И ТЕСТ ЯДРА ===
echo "[2/6] Загрузка и проверка ядра sing-box..."
wget -q --no-check-certificate -O sing-box "$BIN_URL"
if [ ! -s "sing-box" ]; then
    echo "[ERROR] Ошибка скачивания sing-box!"
    cd /opt && rm -rf "$INSTALL_DIR"
    exit 1
fi

chmod +x sing-box
if ! ./sing-box version > /dev/null 2>&1; then
    echo "[ERROR] Ядро несовместимо с архитектурой роутера!"
    cd /opt && rm -rf "$INSTALL_DIR"
    exit 1
fi
echo "Ядро успешно прошло проверку!"

# === 4. ИНТЕРАКТИВНОЕ МЕНЮ ===
PROFILE=""
APPS=""
DROP_QUIC="0"

while true; do
    echo ""
    echo "=================================================="
    echo "Выберите ваш регион для автоматической настройки:"
    echo "[ 1 ] Украина (UA) — Трафик РФ в туннель, остальное напрямую."
    echo "[ 2 ] Россия (RU) - Точечный обход — Только выбранные сервисы в туннель."
    echo "[ 3 ] Россия (RU) - Весь мир через VPN — Трафик РФ напрямую, остальное в туннель."
    echo "[ q ] Выход (Прервать установку)"
    printf "Ваш выбор: "
    read r_choice

    case "$r_choice" in
        q|Q) echo "Выход..."; cd /opt && rm -rf "$INSTALL_DIR"; exit 0 ;;
        1) PROFILE="UA"; break ;;
        3) PROFILE="RU_ALL"; break ;;
        2)
            while true; do
                echo ""
                echo "Какие сервисы ПРИНУДИТЕЛЬНО заворачивать в туннель?"
                echo "[ 1 ] YouTube (Обход замедления)"
                echo "[ 2 ] Instagram / Facebook (Meta)"
                echo "[ 3 ] WhatsApp (Медиа и звонки)"
                echo "[ 4 ] Telegram (Проксирование DC)"
                echo "[ 5 ] OpenAI / ChatGPT"
                echo "[ 6 ] X (Twitter)"
                echo ""
                printf "Ваш выбор (цифры через запятую): "
                read a_choice
                PROFILE="RU_SEL"
                APPS="$a_choice"
                if echo "$APPS" | grep -q "1"; then
                    echo "Блокировать QUIC для YouTube? [1 - Да / 2 - Нет]: "
                    read q_choice
                    [ "$q_choice" = "1" ] && DROP_QUIC="1"
                fi
                break 2
            done
            ;;
        *) echo "Неверный выбор." ;;
    esac
done

# === 5. УМНАЯ ЗАГРУЗКА БАЗ ===
echo ""
echo "[3/6] Скачивание гео-баз..."

download_srs() {
    local NAME="$2"
    echo "  -> Загрузка $NAME.srs..."
    wget -q --no-check-certificate -O "$NAME.srs" "$([ "$1" = "ip" ] && echo $GEOIP_URL || echo $GEOSITE_URL)/${NAME}.srs"
}

RS_STR=""
APP_TAGS=""
add_rs() {
    [ -z "$RS_STR" ] && RS_STR="{ \"tag\": \"$1\", \"type\": \"local\", \"format\": \"binary\", \"path\": \"$1.srs\" }" \
    || RS_STR="${RS_STR}, { \"tag\": \"$1\", \"type\": \"local\", \"format\": \"binary\", \"path\": \"$1.srs\" }"
}

download_srs "ip" "geoip-ru"
add_rs "geoip-ru"

if [ "$PROFILE" = "RU_SEL" ] && [ -n "$APPS" ]; then
    echo "$APPS" | grep -q "1" && { download_srs "site" "geosite-youtube"; add_rs "geosite-youtube"; APP_TAGS="${APP_TAGS}\"geosite-youtube\", "; }
    echo "$APPS" | grep -q "2" && { download_srs "site" "geosite-meta"; add_rs "geosite-meta"; APP_TAGS="${APP_TAGS}\"geosite-meta\", "; }
    echo "$APPS" | grep -q "3" && { download_srs "site" "geosite-whatsapp"; add_rs "geosite-whatsapp"; APP_TAGS="${APP_TAGS}\"geosite-whatsapp\", "; }
    echo "$APPS" | grep -q "4" && { download_srs "site" "geosite-telegram"; add_rs "geosite-telegram"; APP_TAGS="${APP_TAGS}\"geosite-telegram\", "; }
    echo "$APPS" | grep -q "5" && { download_srs "site" "geosite-openai"; add_rs "geosite-openai"; APP_TAGS="${APP_TAGS}\"geosite-openai\", "; }
    echo "$APPS" | grep -q "6" && { download_srs "site" "geosite-twitter"; add_rs "geosite-twitter"; APP_TAGS="${APP_TAGS}\"geosite-twitter\", "; }
    APP_TAGS=$(echo "$APP_TAGS" | sed 's/, $//')
fi

# === 6. ГЕНЕРАЦИЯ КОНФИГА ===
echo "[4/6] Генерация конфигурации base.json..."

RULES_STR=""
FINAL_OUTBOUND="direct"

if [ "$PROFILE" = "UA" ]; then
    RULES_STR="${RULES_STR}, { \"rule_set\": [\"geoip-ru\"], \"outbound\": \"auto-balancer\" }"
elif [ "$PROFILE" = "RU_ALL" ]; then
    RULES_STR="${RULES_STR}, { \"rule_set\": [\"geoip-ru\"], \"outbound\": \"direct\" }"
    FINAL_OUTBOUND="auto-balancer"
elif [ "$PROFILE" = "RU_SEL" ]; then
    RULES_STR="${RULES_STR}, { \"rule_set\": [\"geoip-ru\"], \"outbound\": \"direct\" }"
    [ "$DROP_QUIC" = "1" ] && RULES_STR="${RULES_STR}, { \"protocol\": \"quic\", \"rule_set\": [\"geosite-youtube\"], \"action\": \"reject\" }"
    [ -n "$APP_TAGS" ] && RULES_STR="${RULES_STR}, { \"rule_set\": [${APP_TAGS}], \"outbound\": \"auto-balancer\" }"
fi

cat << EOF > base.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "yandex-udp", "type": "udp", "server": "77.88.8.8" },
      { "tag": "cf-doh", "type": "https", "server": "1.1.1.1" },
      { "tag": "cf-dot", "type": "tls", "server": "1.0.0.1" },
      { "tag": "google-doh", "type": "https", "server": "8.8.8.8" },
      { "tag": "quad9-doh", "type": "https", "server": "9.9.9.9" },
      { "tag": "adguard-doh", "type": "https", "server": "94.140.14.14" },
      { "tag": "alidns-doh", "type": "https", "server": "223.5.5.5" }
    ],
    "rules": [
      { "rule_set": ["geoip-ru"], "server": "yandex-udp" },
      { "outbound": ["any"], "server": "cf-doh" }
    ],
    "final": "google-doh", "strategy": "prefer_ipv4"
  },
  "inbounds": [
    { "type": "http", "tag": "http-tv", "listen": "0.0.0.0", "listen_port": 1080 },
    { "type": "socks", "tag": "socks-1", "listen": "0.0.0.0", "listen_port": 1081 },
    { "type": "socks", "tag": "socks-2", "listen": "0.0.0.0", "listen_port": 1082 },
    { "type": "socks", "tag": "socks-3", "listen": "0.0.0.0", "listen_port": 1083 },
    { "type": "shadowsocks", "tag": "ss-phones", "listen": "0.0.0.0", "listen_port": 30183, "method": "none" }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rule_set": [ $RS_STR ],
    "rules": [
      { "protocol": "dns", "outbound": "direct" }
      $RULES_STR
    ],
    "final": "$FINAL_OUTBOUND"
  }
}
EOF

[ "$PROFILE" = "UA" ] && jq 'del(.dns.servers[] | select(.tag=="yandex-udp")) | del(.dns.rules[] | select(.server=="yandex-udp"))' base.json > b_tmp.json && mv b_tmp.json base.json

# === 7. СКАЧИВАНИЕ СКРИПТОВ ===
echo "[5/6] Загрузка скриптов сборки..."
wget -q --no-check-certificate -O build.sh "$REPO_RAW/build.sh"
wget -q --no-check-certificate -O parse_conf.lua "$REPO_RAW/parse_conf.lua"
chmod +x build.sh
mkdir -p configs
wget -qO- --no-check-certificate "https://api.github.com/repos/Sophiedevops/padavan-singbox-smartproxy-awg2.0/contents/configs" | grep -o '"download_url": *"[^"]*"' | cut -d'"' -f4 | while read -r url; do
    filename=$(basename "$url")
    echo "     Загрузка: $filename"
    wget -q --no-check-certificate -O "configs/$filename" "$url"
done

echo "  -> Сборка балансировщика..."
./build.sh

# === 8. ФИНАЛЬНЫЙ ВЫВОД «ПО-БОГАТОМУ» ===
echo "[6/6] Завершение..."

ROUTER_IP=$(nvram get lan_ipaddr 2>/dev/null || echo "192.168.1.1")
SS_CRED="bm9uZTo="
SS_LINK="ss://${SS_CRED}@${ROUTER_IP}:30183#Padavan-SmartProxy"

echo ""
echo "=================================================="
echo "         УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! 🎉"
echo "=================================================="
echo "Роутер настроен. Запуск ядра sing-box..."
killall -9 sing-box 2>/dev/null
./sing-box run -c run.json > /dev/null 2>&1 &
echo ""
echo "Ваш IP-адрес роутера: $ROUTER_IP"
echo ""
echo "📺 ДЛЯ ТЕЛЕВИЗОРА (Smart TV, Apple TV):"
echo "  Тип:  HTTP Прокси "
echo "  IP:   $ROUTER_IP"
echo "  Порт: 1080"
echo ""
echo "💻 ДЛЯ БРАУЗЕРОВ (ПК) И TELEGRAM:"
echo "  Тип:  SOCKS5 "
echo "  IP:   $ROUTER_IP"
echo "  Порт: 1081 (а также 1082, 1083)"
echo ""
echo "📱 ДЛЯ ТЕЛЕФОНОВ (v2rayNG / NekoBox / Streisand):"
echo "  Скопируйте эту ссылку:"
echo -e "  \033[1;32m$SS_LINK\033[0m"
echo "=================================================="
echo ""
