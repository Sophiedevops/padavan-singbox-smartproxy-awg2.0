#!/bin/sh

CONFIG_DIR="configs"
BASE_JSON="base.json"
RUN_JSON="run.json"
LUA_SCRIPT="parse_conf.lua"

EP_ARRAY="/tmp/sb_eps_$$.json"
TAGS_ARRAY="/tmp/sb_tags_$$.json"

echo "[]" > "$EP_ARRAY"
echo "[]" > "$TAGS_ARRAY"

echo ">>> Начинаем сборку конфигурации из $CONFIG_DIR/*.conf"

for conf_file in "$CONFIG_DIR"/*.conf; do
    [ -e "$conf_file" ] || continue
    tag_name=$(basename "$conf_file" .conf)
    echo -n "Обработка: $tag_name... "
    
    ep_json=$(lua "$LUA_SCRIPT" "$conf_file" "$tag_name")
    
    if [ $? -eq 0 ] && [ -n "$ep_json" ]; then
        if echo "$ep_json" | jq . >/dev/null 2>&1; then
            jq --argjson new_ep "$ep_json" '. + [$new_ep]' "$EP_ARRAY" > "${EP_ARRAY}.tmp" && mv "${EP_ARRAY}.tmp" "$EP_ARRAY"
            jq --arg tag "$tag_name" '. + [$tag]' "$TAGS_ARRAY" > "${TAGS_ARRAY}.tmp" && mv "${TAGS_ARRAY}.tmp" "$TAGS_ARRAY"
            echo "ОК"
        else
            echo "ОШИБКА JSON"
        fi
    else
        echo "ПРОПУСК"
    fi
done

URLTEST_OUTBOUND=$(jq -n --argjson tags "$(cat "$TAGS_ARRAY")" '{
  type: "urltest",
  tag: "auto-balancer",
  outbounds: $tags,
  url: "https://www.cloudflare.com/cdn-cgi/trace",
  interval: "3m",
  tolerance: 50
}')

# Сборка финального конфига БЕЗ перетирания route.final
jq --argjson eps "$(cat "$EP_ARRAY")" \
   --argjson urltest "$URLTEST_OUTBOUND" \
   '.endpoints = ($eps + (.endpoints // [])) | 
    .outbounds = ([$urltest] + (.outbounds // []))' "$BASE_JSON" > "$RUN_JSON"

rm -f "$EP_ARRAY" "$TAGS_ARRAY" "${EP_ARRAY}.tmp" "${TAGS_ARRAY}.tmp"
echo ">>> Сборка завершена. Результат в $RUN_JSON"
