# 🛡️ padavan-singbox-smartproxy-awg2.0

<div align="center">

![Static Badge](https://img.shields.io/badge/Language-Bash-blue?style=for-the-badge&logo=gnubash&logoColor=white)
![Static Badge](https://img.shields.io/badge/Language-Lua-yellow?style=for-the-badge&logo=lua&logoColor=white)
![Static Badge](https://img.shields.io/badge/github-repo-green?style=for-the-badge&logo=github&logoColor=white)
![Static Badge](https://img.shields.io/badge/Platform-Padavan-orange?style=for-the-badge&logo=linux&logoColor=white)
![Static Badge](https://img.shields.io/badge/Core-sing--box-purple?style=for-the-badge)
![Static Badge](https://img.shields.io/badge/Tunnel-AmneziaWG-red?style=for-the-badge)

**Умный прокси-сервер на базе sing-box и AmneziaWG 1.5–2.0 для роутеров Padavan.**
Интерактивная гео-маршрутизация, точечный обход блокировок и минимальное потребление ресурсов (SOCKS5 / HTTP / Shadowsocks)

</div>

---

# 🚀 Padavan SmartProxy (sing-box + AmneziaWG)

> 💡 **Основа проекта:** В данной сборке используется модифицированное ядро `sing-box` с нативной поддержкой протокола AmneziaWG. Выражаем благодарность автору репозитория **[hoaxisr/amnezia-box](https://github.com/hoaxisr/amnezia-box)** за предоставленные исходники и бинарники!

Легковесный и умный автоматический установщик для настройки точечного обхода блокировок на роутерах со слабым железом (прошивка Padavan, чипы MT7620 и аналоги). Базируется на современном ядре `sing-box` и туннелях `AmneziaWG` с интегрированным балансировщиком.

---

## 🌟 Главные особенности

| # | Возможность | Описание |
|---|-------------|----------|
| ⚡ | **Экономия ресурсов (CPU/RAM)** | Внутри домашней Wi-Fi сети трафик не шифруется. Роутер выступает как умный шлюз (HTTP/SOCKS5 Proxy), что позволяет достигать высоких скоростей без перегрузки слабого процессора |
| 🤖 | **Полная автоматизация** | Скрипт сам скачивает ядро `sing-box`, устанавливает зависимости (`jq` через Entware), выкачивает гео-базы и генерирует рабочие конфигурации |
| 🌍 | **Интерактивная гео-маршрутизация** | Три готовых профиля маршрутизации под разные сценарии использования |
| 🔪 | **Kill QUIC** | Опциональная блокировка протокола QUIC (UDP 443) для форсирования стабильного TCP-соединения (идеально для обхода замедления YouTube на Smart TV) |
| 🔗 | **Динамические конфиги по API** | Скрипт автоматически скачивает все ваши AmneziaWG конфигурации из папки `configs/` в этом репозитории и собирает их в единый балансировщик |

---

### 🗺️ Профили гео-маршрутизации

<details>
<summary>🇺🇦 <b>Профиль UA</b> — показать описание</summary>
<br>
Трафик РФ (<code>geoip-ru</code>) принудительно заворачивается в туннель, остальной мир идет напрямую.
</details>

<details>
<summary>🇷🇺 <b>Профиль RU — Точечный обход</b> — показать описание</summary>
<br>
Локальный трафик идет напрямую провайдеру, а в туннель уходят только выбранные заблокированные сервисы:<br><br>
📺 YouTube &nbsp;|&nbsp; 👥 Meta &nbsp;|&nbsp; ✈️ Telegram &nbsp;|&nbsp; 🤖 OpenAI/ChatGPT &nbsp;|&nbsp; 🐦 X/Twitter
</details>

<details>
<summary>🌐 <b>Профиль RU — Весь мир</b> — показать описание</summary>
<br>
Трафик РФ идет напрямую, весь остальной мир — через VPN.
</details>

---

## 📋 Требования

- 🖥️ Роутер с кастомной прошивкой **Padavan** (AsusRT, Prometheus и т.д.)
- 📦 Установленная среда **Entware** (смонтированная USB-флешка в `/opt`)
- 🧠 Свободная ОЗУ (RAM): от **25 МБ**
- 💾 Свободное место на флешке: от **50 МБ**

---

## 🚀 Установка

Зайдите в терминал роутера (через SSH) и выполните команду:

```bash
wget --no-check-certificate -O install.sh https://raw.githubusercontent.com/Sophiedevops/padavan-singbox-smartproxy-awg2.0/main/install.sh && chmod +x install.sh && ./install.sh
```

---

## 🔄 Автозагрузка при перезапуске роутера

Чтобы `sing-box` запускался автоматически после отключения или перезагрузки роутера:

1. 🌐 Зайдите в **веб-интерфейс Padavan**
2. 📂 Перейдите в раздел **Персонализация → Скрипты → вкладка «Выполнить после полного запуска роутера»** *(Run After Router Started)*
3. ✏️ Добавьте в самый конец этот код:

```bash
# Запуск Padavan SmartProxy
sleep 10
/opt/awg2_singbox/sing-box run -c /opt/awg2_singbox/run.json > /dev/null 2>&1 &
```

4. ✅ Нажмите кнопку **Применить** внизу страницы

---

## 📁 Как добавить свои сервера AmneziaWG?

Инсталлятор настроен так, что он обращается к **GitHub API** и автоматически скачивает все конфигурации из папки `configs/`.

Если вы хотите обновить туннели или добавить свои платные сервера:

1. 📤 Загрузите ваши файлы `.conf` от AmneziaWG в папку `configs` на роутере, удалив неиспользуемые/нерабочие

> [!IMPORTANT]
> **📌 Файлы `*.conf`:** Скрипт автоматически сканирует туннели и выбирает с наименьшим ping, поэтому старайтесь не держать большое количество неиспользуемых конфигураций в папке `configs`.

2. 🔑 Зайдите в **SSH** роутера и снова запустите установку:
```bash
cd /opt && ./install.sh
```
*(или скачайте его заново командой из раздела Установки)*

3. 🗑️ В появившемся меню выберите **«2 — Удалить старую папку полностью»**

4. 🎉 Скрипт установится «начисто», подтянет ваши новые конфиги и соберёт свежий балансировщик!
// REFERENCE
<details>
<summary>📋 &nbsp;<b>Таблица-памятка (шпаргалка) по типам переменных AmneziaWG</b> &nbsp;— нажмите чтобы развернуть</summary>
<br>

🧩 Справочник по параметрам конфигурации sing-box для протокола AmneziaWG. Типы данных критичны — неверный тип (строка вместо числа) приведёт к ошибке парсинга конфига.

<div align="center">
ПАРАМЕТРОПИСАНИЕТИП В JSONПРИМЕРserverIP-адрес или домен VPS сервераString · Строка"123.45.67.89"server_portПорт сервераInteger · Целое51820 ⚠️ без кавычекsystem_interfaceИспользовать ли системный интерфейсBoolean · Логическийtrue или falseinterface_nameНазвание сетевого интерфейсаString · Строка"awg0"local_addressВнутренний IP клиента (из блока [Interface])Array of Strings · Массив["10.8.0.2/24"]private_keyПриватный ключ клиентаString · Строка"aBcDeF..."peer_public_keyПубличный ключ сервераString · Строка"XyZaBc..."jcJunk packet countInteger · Целое120 ⚠️ без кавычекjminJunk packet minimum sizeInteger · Целое23 ⚠️ без кавычекjmaxJunk packet maximum sizeInteger · Целое91 ⚠️ без кавычекs1Init packet junk sizeInteger · Целое0 ⚠️ без кавычекs2Response packet junk sizeInteger · Целое0 ⚠️ без кавычекh1Init packet magic headerInteger · Целое1 ⚠️ без кавычекh2Response packet magic headerInteger · Целое2 ⚠️ без кавычекh3Underload packet magic headerInteger · Целое3 ⚠️ без кавычекh4Transport packet magic headerInteger · Целое4 ⚠️ без кавычек
</div>

[!TIP]
⚠️ Частая ошибка: Параметры server_port, jc, jmin, jmax, s1, s2, h1–h4 — это Integer. Если обернуть их в кавычки "120" — sing-box выдаст ошибку при запуске. Только server, interface_name, private_key, peer_public_key и local_address являются строками/массивами строк.

</details>

<div align="center">
<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=6,11,20&height=120&section=footer&text=SagerNet%20geosite%20%26%20geoip&fontSize=18&fontColor=00f5ff&animation=twinkling&fontAlignY=65"/>
</div>
*Проект создан для удобной маршрутизации домашнего трафика.*
*Базы `geosite` и `geoip` скачиваются напрямую из официальных репозиториев **SagerNet**.*

</div>
