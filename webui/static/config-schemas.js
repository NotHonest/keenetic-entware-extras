// config-schemas.js — Config field definitions (pure data) for Entware Extras WebUI.
// Extracted from config-editor.js for maintainability.
// No dependencies. Referenced by: config-editor.js, app.js (buildUI).
// Visible labels are Russian. Config keys and stored values stay as-is.
"use strict";

// ── Config Schemas ───────────────────────────────────────────────────────────

/** Config field definitions per service (schema for form rendering). */
var CONFIG_SCHEMAS = {
    'geo-split': [
        { key: 'GEO_ZONE', label: 'Зона', type: 'zone_selector',
          desc: 'Какие страны идут через выбранный выход. Союз раскрывается в несколько стран. Для домашнего сценария оставьте ЕАЭС.' },
        { key: 'ROUTE_IN', label: 'Сегменты', type: 'iface_select', hint: 'Где действует правило',
          desc: 'Сети, для которых строятся отдельные маршруты. Домашняя сеть — br0. Сегмент пылесоса сюда не добавляйте, если он должен ходить своим маршрутом.' },
        { key: 'ROUTE_OUT', label: 'Куда идёт зона', type: 'iface_select', multi: false, hint: 'Выход для сайтов выбранной зоны',
          preItems: [{ value: 'auto', label: 'Авто (как основной маршрут)' }],
          desc: '«Авто» повторяет основной маршрут Keenetic. Если основной маршрут — VPN, зона тоже уйдёт в VPN. Для сценария «ЕАЭС напрямую» укажите интерфейс провайдера, например ММТ.' },
        { key: 'ROUTE_GW', label: 'Шлюз', type: 'radio_text', hint: 'Обычно оставьте авто', advanced: true,
          presets: [{ value: 'auto', label: 'Авто' }, { value: 'none', label: 'Без шлюза' }],
          desc: 'Авто берёт шлюз с маршрута выбранного выхода. На LTE и PPP шлюз не нужен, маршрут пойдёт через сам интерфейс.' },
        { key: 'SUBNET_LOADER', label: 'Формат списков', type: 'select', advanced: true,
          options: [{ value: 'cidr-plain', label: 'Простой список CIDR' }, { value: 'ripe-json', label: 'RIPE JSON (нужен jq)' }],
          hint: 'Как читать скачанный список подсетей',
          desc: 'Простой список — одна подсеть на строку. RIPE JSON нужен только если список в формате RIPE и на роутере есть jq.' },
        { key: 'SUBNET_URL', label: 'Свой адрес списка', type: 'text', hint: 'Пусто — брать зону выше', advanced: true,
          desc: 'Если заполнено, зона игнорируется и скачивается только этот адрес. Для обычной работы оставьте пустым.' },
        { key: 'SUBNET_AGGREGATE', label: 'Склеивать подсети', type: 'toggle', on: '1', off: '0', hint: 'Меньше записей в таблице', advanced: true,
          desc: 'Соседние подсети объединяются после загрузки. Маршрутов становится меньше.' },
        { key: 'DOWNLOAD_INTERFACES', label: 'Откуда качать списки', type: 'iface_select', hint: 'Интерфейсы по порядку', advanced: true,
          preItems: [{ value: 'default', label: 'Основной маршрут' }, { value: '*', label: 'Все VPN (*)' }],
          desc: 'Через какие интерфейсы пробовать скачать списки. «Основной маршрут» — то, что сейчас выбрано в Keenetic. «Все VPN» — все поднятые туннели.' },
        { key: 'DOMAINS_UPDATE_INTERVAL', label: 'Как часто обновлять домены', type: 'number', min: 0, hint: 'Секунды, 0 — не обновлять', advanced: true,
          desc: 'Как часто заново узнавать адреса доменов из списка. Меньше — быстрее реакция на смену адресов CDN, больше — меньше запросов DNS.' },
        { key: 'DNS_FULL_RESOLVER_PORT', label: 'Порт DNS', type: 'text', hint: 'Пусто — найти самому', advanced: true,
          desc: 'Куда спрашивать все адреса домена. Пусто: сначала порт 6153, потом 6053, потом системный DNS роутера.' },
        { key: 'MAX_CACHE_AGE', label: 'Срок жизни списка подсетей', type: 'number', min: 0, hint: 'Секунды, по умолчанию 7 дней', advanced: true,
          desc: 'Через сколько секунд список подсетей считается устаревшим и скачивается заново.' }
    ],
    'smartdns': [
        { key: 'DNS_ZONE', label: 'Зона DNS', type: 'zone_selector',
          desc: 'Для каких стран использовать отдельный DNS. Союз раскрывается в несколько стран.' },
        { key: 'ZONE_DNS_PROVIDER', label: 'DNS для зоны', type: 'multi_select',
          dynamicOptions: 'zone',
          hint: 'Кто отвечает за сайты зоны',
          desc: 'Один или несколько DNS для доменов выбранной зоны.' },
        { key: 'ZONE_DNS_INTERFACE', label: 'Выход DNS зоны', type: 'iface_select', multi: false, hint: 'Обычно напрямую через провайдера',
          desc: 'Через какой интерфейс ходят запросы DNS зоны. Обычно это провайдер, не VPN.' },
        { key: 'OTHER_DNS_PROVIDER', label: 'DNS для остальных', type: 'multi_select',
          dynamicOptions: 'other',
          hint: 'Кто отвечает за зарубежные сайты',
          desc: 'Один или несколько DNS для доменов вне зоны.' },
        { key: 'OTHER_DNS_INTERFACES', label: 'Выход зарубежного DNS', type: 'iface_select', hint: 'Обычно через VPN',
          desc: 'Через какие интерфейсы спрашивать зарубежный DNS. Пока туннель отвечает, прямого сервера рядом нет: иначе быстрый ответ провайдера мог бы победить. Если туннель молчит пару минут, запросы временно идут напрямую и возвращаются в туннель, когда он снова отвечает.' },
        { key: 'DNS_TRANSPORT', label: 'Шифрование DNS', type: 'select',
          options: [{ value: 'auto', label: 'Авто (DoT/DoH, запасной UDP)' }, { value: 'strict', label: 'Только DoT/DoH, без UDP' }],
          hint: 'Можно ли спрашивать обычный DNS',
          desc: 'Авто предпочитает шифрованный DNS и оставляет обычный UDP как запасной. Строгий режим не отправляет открытые запросы.' }
    ],
    'smartdns-redirect': [
        { key: 'UPSTREAM_PORT', label: 'Порт DNS на роутере', type: 'number', min: 1, max: 65535, hint: 'SmartDNS 6053, AGH 5353, Unbound 5335',
          desc: 'На какой локальный порт направлять перехваченные запросы DNS.' },
        { key: 'INTERFACES', label: 'Сегменты', type: 'iface_select', hint: 'Где перехватывать DNS',
          desc: 'Обычно br0, домашняя сеть. br1 добавляйте только если этот сегмент тоже должен спрашивать DNS роутера.' },
        { key: 'REDIRECT_MODE', label: 'Режим', type: 'select',
          options: [{ value: 'force', label: 'Перехватывать весь DNS и блокировать DoT' }, { value: 'local', label: 'Только запросы к роутеру' }],
          hint: 'Полный перехват или только запросы к роутеру',
          desc: 'Полный режим забирает все запросы на порт 53 и блокирует DoT на 853. Мягкий режим трогает только DNS, адресованный роутеру: 8.8.8.8 и DoT проходят мимо.' },
        { key: 'WATCHDOG_SERVICE', label: 'Служба для перезапуска', type: 'text', hint: 'Например S38smartdns',
          desc: 'Если DNS на роутере замолчит, перезапустить эту службу. Пусто — не перезапускать.' },
        { key: 'PRESERVE_FILTER_PROFILES', label: 'Не трогать профили фильтра', type: 'toggle', hint: 'Пока не работает',
          desc: 'Задумано так: устройства с профилем фильтра Keenetic не попадают под перехват. Сейчас настройка ничего не меняет.' }
    ],
    'webui': [
        { key: 'LISTEN_PORT', label: 'Порт панели', type: 'number', min: 1, max: 65535, hint: 'После сохранения страница откроется заново',
          desc: 'Порт nginx этой панели. После смены страница перезагрузится уже на новом порту.' },
        { key: 'INJECT_SIDEBAR', label: 'Пункт в меню Keenetic', type: 'toggle', on: '1', off: '0', hint: 'Добавляет раздел в обычное меню',
          desc: '1 — в боковом меню Keenetic появляется раздел «Маршруты». 0 — меню роутера без изменений.' },
        { key: 'DASH_POLL_INTERVAL', label: 'Как часто обновлять', type: 'number', min: 1000, hint: 'Миллисекунды',
          desc: 'Как часто карточка на главной Keenetic спрашивает состояние. Меньше — отзывчивее и больше запросов.' }
    ]
};

/** Labels for modal title per service. */
var CONFIG_LABELS = {
    'geo-split': 'Разделение по странам',
    'smartdns': 'DNS по зонам',
    'smartdns-redirect': 'Перехват DNS',
    'webui': 'Панель'
};
