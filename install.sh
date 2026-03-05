#!/bin/sh

# === НАСТРОЙКИ ===
INSTALL_DIR="/opt/awg2_singbox"
BACKUP_DIR="${INSTALL_DIR}.bak"
BIN_URL="https://github.com/Sophiedevops/padavan-singbox-smartproxy-awg2.0/releases/download/main/sing-box"
GEOIP_URL="https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set"
GEOSITE_URL="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set"
REPO_RAW="https://raw.githubusercontent.com/Sophiedevops/padavan-singbox-smartproxy-awg2.0/main"

echo "=================================================="
echo "    SING-BOX ROUTING SETUP (v2.0) - Padavan Edition"
echo "=================================================="

# === 1. ПРОВЕРКА РЕСУРСОВ ===
echo "[1/6] Проверка системы..."
FREE_RAM=$(free -m | awk '/Mem:/ {print $4}')
[ -z "$FREE_RAM" ] && FREE_RAM=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')
FREE_DISK=$(df -m /opt | awk 'NR==2 {print $4}')

if [ "$FREE_RAM" -lt 25 ] || [ "$FREE_DISK" -lt 50 ]; then
    echo "[ERROR] Мало ресурсов (RAM: ${FREE_RAM}MB, Disk: ${FREE_DISK}MB). Установка прервана."
    exit 1
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
    echo "[ERROR] Ошибка скачивания sing-box! Ссылка битая или нет интернета."
    cd /opt && rm -rf "$INSTALL_DIR"
    exit 1
fi

chmod +x sing-box
if ! ./sing-box version > /dev/null 2>&1; then
    echo "[ERROR] Ядро несовместимо с архитектурой роутера! (Segfault/Not found)"
    echo "Очистка мусора..."
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
                echo "(Введите цифры через запятую, например: 1,3,4)"
                echo "[ 1 ] YouTube (Обход замедления)"
                echo "[ 2 ] Instagram / Facebook (Meta)"
                echo "[ 3 ] WhatsApp (Стабильные голосовые звонки и медиа)"
                echo "[ 4 ] Telegram (Обход блокировки дата-центров)"
                echo "[ 5 ] OpenAI / ChatGPT"
                echo "[ 6 ] X (Twitter)"
                echo ""
                echo "[ b ] Вернуться назад к выбору региона"
                echo "[ q ] Выход"
                printf "Ваш выбор (или 0 для отмены): "
                read a_choice

                case "$a_choice" in
                    q|Q) echo "Выход..."; cd /opt && rm -rf "$INSTALL_DIR"; exit 0 ;;
                    b|B) break ;;
                    0) PROFILE="RU_SEL"; APPS=""; break 2 ;;
                    *)
                        PROFILE="RU_SEL"
                        APPS="$a_choice"
                        
                        if echo "$APPS" | grep -q "1"; then
                            echo ""
                            echo "=================================================="
                            echo "НАСТРОЙКА YOUTUBE: QUIC (UDP 443)"
                            echo "Желаете включить экспериментальную блокировку QUIC для YouTube?"
                            echo "[ 1 ] Да, включить (Рекомендуется)"
                            echo "[ 2 ] Нет, стандартная маршрутизация"
                            printf "Ваш выбор: "
                            read q_choice
                            [ "$q_choice" = "1" ] && DROP_QUIC="1"
                        fi
                        break 2
                        ;;
                esac
            done
            ;;
        *) echo "Неверный выбор." ;;
    esac
done

# === 5. УМНАЯ ЗАГРУЗКА БАЗ ===
echo ""
echo "[3/6] Скачивание гео-баз..."

download_srs() {
    local TYPE="$1"
    local NAME="$2"
    local URL=""
    [ "$TYPE" = "ip" ] && URL="$GEOIP_URL/${NAME}.srs"
    [ "$TYPE" = "site" ] && URL="$GEOSITE_URL/${NAME}.srs"
    
    echo "  -> Загрузка $NAME.srs..."
    wget -q --no-check-certificate -O "$NAME.srs" "$URL"
    if [ $? -ne 0 ] || [ ! -s "$NAME.srs" ]; then
        echo "[ERROR] Ошибка загрузки $NAME.srs! Установка прервана."
        cd /opt && rm -rf "$INSTALL_DIR"
        exit 1
    fi
}

RS_STR=""
APP_TAGS=""

add_rs() {
    RS_STR="${RS_STR}, { \"tag\": \"$1\", \"type\": \"local\", \"format\": \"binary\", \"path\": \"$1.srs\" }"
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
    FINAL_OUTBOUND="direct"
elif [ "$PROFILE" = "RU_ALL" ]; then
    RULES_STR="${RULES_STR}, { \"rule_set\": [\"geoip-ru\"], \"outbound\": \"direct\" }"
    FINAL_OUTBOUND="auto-balancer"
elif [ "$PROFILE" = "RU_SEL" ]; then
    RULES_STR="${RULES_STR}, { \"rule_set\": [\"geoip-ru\"], \"outbound\": \"direct\" }"
    if [ "$DROP_QUIC" = "1" ]; then
        RULES_STR="${RULES_STR}, { \"protocol\": \"quic\", \"rule_set\": [\"geosite-youtube\"], \"action\": \"reject\" }"
    fi
    if [ -n "$APP_TAGS" ]; then
        RULES_STR="${RULES_STR}, { \"rule_set\": [${APP_TAGS}], \"outbound\": \"auto-balancer\" }"
    fi
    FINAL_OUTBOUND="direct"
fi

cat << EOF > base.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "google-udp", "type": "udp", "server": "8.8.8.8" },
      { "tag": "cf-doh", "type": "https", "server": "cloudflare-dns.com", "domain_resolver": "google-udp" }
    ],
    "strategy": "prefer_ipv4",
    "final": "cf-doh"
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
    "rule_set": [
      { "tag": "dummy", "type": "local", "format": "binary", "path": "dummy.srs" }
      $RS_STR
    ],
    "rules": [
      { "protocol": "dns", "outbound": "direct" }
      $RULES_STR
    ],
    "final": "$FINAL_OUTBOUND"
  }
}
EOF

sed -i '/"tag": "dummy"/d' base.json

# === 7. СКАЧИВАНИЕ СКРИПТОВ И ДИНАМИЧЕСКИХ КОНФИГОВ ===
echo "[5/6] Загрузка скриптов сборки туннелей..."
wget -q --no-check-certificate -O build.sh "$REPO_RAW/build.sh"
wget -q --no-check-certificate -O parse_conf.lua "$REPO_RAW/parse_conf.lua"
chmod +x build.sh

echo "  -> Создание папки configs и автоматическая загрузка всех пресетов..."
mkdir -p configs

# Обращаемся к GitHub API, вытаскиваем все ссылки download_url из папки configs и качаем файлы
wget -qO- --no-check-certificate "https://api.github.com/repos/Sophiedevops/padavan-singbox-smartproxy-awg2.0/contents/configs" | grep -o '"download_url": *"[^"]*"' | cut -d'"' -f4 | while read -r file_url; do
    if [ -n "$file_url" ] && [ "$file_url" != "null" ]; then
        filename=$(basename "$file_url")
        echo "     Загрузка: $filename"
        wget -q --no-check-certificate -O "configs/$filename" "$file_url"
    fi
done

echo "  -> Сборка балансировщика..."
./build.sh

# === 8. ФИНАЛЬНЫЙ ВЫВОД И ССЫЛКИ ===
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
nohup ./sing-box run -c run.json > /dev/null 2>&1 &
echo ""
echo "Ваш IP-адрес роутера: $ROUTER_IP"
echo ""
echo "📺 ДЛЯ ТЕЛЕВИЗОРА (Smart TV, Apple TV):"
echo "  Тип:  HTTP Прокси"
echo "  IP:   $ROUTER_IP"
echo "  Порт: 1080"
echo ""
echo "💻 ДЛЯ БРАУЗЕРОВ (ПК) И TELEGRAM:"
echo "  Тип:  SOCKS5"
echo "  IP:   $ROUTER_IP"
echo "  Порт: 1081 (а также 1082, 1083)"
echo ""
echo "📱 ДЛЯ ТЕЛЕФОНОВ (v2rayNG / NekoBox / Streisand):"
echo "  Скопируйте эту ссылку:"
echo -e "  \033[1;32m$SS_LINK\033[0m"
echo "=================================================="
echo ""
