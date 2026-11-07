# net-check

Диагностика сетевого подключения и контроль деградации для Keenetic/Entware.

Сквозная проверка доступности через интерфейсы WAN,
обнаружение аномалий MITM/DPI, анализ CDN geo-steering,
тест DNS-утечек, сравнение качества пути.

> 📖 **[Руководство пользователя](docs/user-manual.ru.md)**

## Использование

```sh
# Полная диагностика (9 шагов: geo → conn → ipv6 → dns → dns-leak → comp → cdn → tls → speed)
net-check.sh all

# Глубокая проверка — один ресурс (HTTP + DNS + TLS + CDN)
net-check.sh check youtube.com

# Глубокая проверка — несколько ресурсов (bulk-таблицы)
net-check.sh check youtube.com google.com github.com

# Диагностика по отдельности
net-check.sh geo              # Проверка точки выхода (GeoIP)
net-check.sh conn             # TCP/TLS timing, traceroute, потери, MTU
net-check.sh ipv6             # Обнаружение IPv6-утечек
net-check.sh speed            # Пропускная способность download/upload

# Массовые проверки ресурсов (все цели из конфигурации)
net-check.sh comp             # Таблица сравнения HTTP-доступности
net-check.sh dns              # DNS-резолвинг и фильтрация ISP
net-check.sh dns-leak         # Тест DNS-утечек (цепочка резолверов)
net-check.sh cdn              # Анализ CDN geo-steering
net-check.sh tls              # Проверка TLS-сертификата на MITM

# Варианты для одного ресурса
net-check.sh cdn youtube.com  # Анализ CDN для одного домена
net-check.sh tls youtube.com  # Проверка TLS для одного хоста

# Массовые проверки со своими доменами (вместо конфигурации)
net-check.sh comp youtube.com google.com
net-check.sh dns youtube.com google.com

# Параметры
net-check.sh --json check youtube.com   # Вывод JSON
net-check.sh --privacy all              # Анонимизация IP, ASN, geo
net-check.sh --iface nwg0 comp         # Проверка через указанный интерфейс
net-check.sh --quiet all                # Однострочная сводка по секции
```

## Конфигурация

- `config/defaults.conf` — настройки по умолчанию (не редактировать)
- `config/config.conf` — пользовательские переопределения (создать при необходимости)
- `config/check-targets.conf` — список целей HTTP/DNS/TLS
- `config/cdn-domains.conf` — домены CDN для анализа geo-steering
- `config/dns-providers.conf` — определение поставщиков DNS
- `config/anomaly-markers.conf` — обнаружение страниц аномалий ISP
- `config/mitm-issuers.conf` — шаблоны известных CA MITM-прокси

Все файлы конфигурации защищены от перезаписи при обновлении пакета.

## Коды выхода

- `0` — все проверки пройдены
- `1` — деградация (часть проверок не прошла)
- `2` — критический сбой

## Структура файлов

```
net-check/
├── config/
│   ├── defaults.conf           # Настройки по умолчанию (не редактировать)
│   ├── config.conf             # Пользовательские переопределения (создать при необходимости)
│   ├── check-targets.conf      # Список целей HTTP/DNS/TLS
│   ├── check-targets-custom.conf # Пользовательские цели (не перезаписывается)
│   ├── cdn-domains.conf        # Домены CDN для анализа geo-steering
│   ├── cdn-domains-custom.conf # Пользовательские домены CDN (не перезаписывается)
│   ├── dns-providers.conf      # Определение поставщиков DNS
│   ├── anomaly-markers.conf    # Шаблоны страниц аномалий ISP
│   ├── mitm-issuers.conf       # Шаблоны известных CA MITM-прокси
│   ├── known-cas.conf          # Известные национальные и региональные CA (allowlist)
│   ├── privacy-providers.conf  # Шаблоны поставщиков для анонимизации
│   └── wellknown-ips.conf      # IP известных публичных резолверов DNS
├── scripts/
│   ├── net-check.sh            # Основная точка входа
│   ├── domain-check.sh         # Ярлык: глубокая проверка одного ресурса
│   ├── status.sh               # Диагностика для статуса init.d
│   └── lib/                    # Модули команд и общие библиотеки
│       ├── cmd-all.sh          # Оркестрация команды "all"
│       ├── cmd-geo.sh          # Проверка точки выхода (GeoIP)
│       ├── cmd-connectivity.sh # TCP/TLS timing, traceroute, потери, MTU
│       ├── cmd-ipv6-leak.sh    # Обнаружение IPv6-утечек
│       ├── cmd-dns.sh          # DNS-резолвинг и фильтрация ISP
│       ├── cmd-dns-leak.sh     # Тест DNS-утечек (цепочка резолверов)
│       ├── cmd-compare.sh      # Таблица сравнения HTTP-доступности
│       ├── cmd-cdn.sh          # Анализ CDN geo-steering
│       ├── cmd-tls.sh          # Проверка TLS-сертификата на MITM
│       ├── cmd-speed.sh        # Пропускная способность download/upload
│       ├── cmd-check.sh        # Глубокая проверка одного ресурса
│       ├── batch.sh            # Адаптивный размер пакета, параллельный запуск
│       ├── wan.sh              # Обнаружение WAN, iface_type
│       ├── geoip.sh            # API геолокации IP
│       ├── geo-cache.sh        # Операции и поиск в кэше Geo
│       ├── zone.sh             # Контекст геозоны, маршрутизация
│       ├── http-core.sh        # curl, проверка содержимого, метрики
│       ├── verdict.sh          # Классификация сбоев, подписи причин
│       ├── privacy.sh          # Фильтр приватности (анонимизация IP/ASN)
│       ├── output.sh           # Ошибки, справка, чтение конфигурации
│       ├── sections.sh         # Индикатор, баннеры, подробность вывода
│       ├── table.sh            # Каркас таблиц
│       └── colors.sh           # Цвета, отметки, emoji
└── docs/
    └── user-manual.ru.md       # Руководство пользователя
```

### domain-check.sh

Ярлык глубокой проверки одного ресурса. То же, что `net-check.sh check <domain>`:

```sh
domain-check.sh youtube.com
```

## Зависимости

- `curl` — проверки HTTP, сервисы GeoIP, API теста DNS-утечек
- `bind-dig` — проверки DNS/CDN, EDNS Client Subnet, зондирование DNS-утечек
- `iputils-ping` — связность ICMP, измерение потерь и jitter
- `netcat` (рекомендуется) — проверки TCP connect
- `openssl-util` (рекомендуется) — инспекция TLS-сертификатов
- `traceroute` (необязательно) — трассировка пути

## Стандарты

Методика измерений соответствует ITU-T Y.1540 (параметры переноса IP-пакетов)
и ITU-T Y.1541 (нормы характеристик сети).
