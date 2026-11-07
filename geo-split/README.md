# geo-split

> 📖 **[Руководство пользователя](docs/user-manual.ru.md)** — пошаговая установка, настройка, устранение неполадок.

Раздельная маршрутизация для Keenetic/Entware — направление трафика по подсетям GeoIP и спискам доменов через разные сетевые интерфейсы.

Типичные сценарии:
- 🌐 **Распределение трафика Multi-WAN:** региональные подсети идут через ISP, всё остальное — через туннель (например, ЕАЭС, ЕС, АСЕАН — 232 зоны, 40+ объединений)
- 🔒 **Раздельное туннелирование:** отдельные подсети и домены направляются в туннель ради совместимости сервисов (CDN, банки, государственные порталы)
- ⚡ **Оптимизация производительности:** локальные и региональные сети идут напрямую, остальное — через другой канал
- 🔄 **Отказоустойчивость:** автоматическое согласование маршрутов при изменении состояния интерфейсов

## Установка

Нужен настроенный [репозиторий opkg](../releases/README.md).

```sh
opkg install geo-split
```

Зависимости (`keenetic-entware-extras`, `geo-split-data`, `ip-full`, `curl`, `bind-dig`, `aggregate6`) устанавливаются автоматически.

> `config/config.conf` — conffile: сохраняется при `opkg upgrade`.

После установки:

```sh
# 1. Отредактируйте конфигурацию
vi /opt/keenetic-entware-extras/geo-split/config/config.conf

# 2. Запуск
/opt/etc/init.d/S99geo-split start
```

## Удаление

```sh
opkg remove geo-split
```

Автоматически выполняется: остановка службы, удаление задания cron, очистка хука NDM, удаление batch-файлов.

## Маршрутизация (ROUTE_OUT / ROUTE_IN)

Два ключевых параметра управляют маршрутизацией:

| Параметр | Описание | По умолчанию |
|-----------|-------------|---------|
| `ROUTE_OUT` | Куда отправлять GEO-трафик (исходящий интерфейс) | `"auto"` |
| `ROUTE_IN` | Источник трафика (интерфейсы LAN для `ip rule iif`) | `"br0"` |

**Семантика `ROUTE_OUT`:**
- `"auto"` или пусто → первый default, который не туннель и не мост `br*`. Сначала основная таблица, затем `ip route show table all`
- Явное имя интерфейса (`"lte_br1"`, `"nwg0"`, `"ppp0"`) → использовать напрямую. Если этот интерфейс лежит, хук снимает правила и не переключается на другой выход

`scripts/tunnel-check.sh` только проверяет, открывается ли через интерфейс `http://1.1.1.1/cdn-cgi/trace`. Ответ HTTP 2xx или 3xx считается успехом. Маршруты и приоритет соединений Keenetic скрипт не меняет. Без аргумента берётся интерфейс основного маршрута.

## Архитектура

### Принцип: асинхронные данные + мгновенные правила

Загрузка данных (подсети CIDR, разрешение доменов DNS) идёт **асинхронно** через cron. Прикрепление правил маршрутизации **мгновенное**, из кэша (~1 с для 13K+ маршрутов через `ip-full -batch`). Такое разделение даёт быстрый запуск и надёжную работу при перезагрузках и переключении интерфейсов.

### Подход: на основе маршрутов (без iptables)

Вместо `iptables mangle MARK` (это конфликтует с маршрутизацией Keenetic NDM по устройствам) используется подход **на основе маршрутов**:

1. `ip rule add iif br0 table 1000 priority 50` — маршруты доменов (хостовые маршруты /32)
2. `ip rule add iif br0 table 1001 priority 51` — маршруты подсетей (CIDR GeoIP)
3. Загрузчики заполняют таблицы: домены → таблица 1000, подсети → таблица 1001
4. Трафик, не совпавший ни с одним маршрутом, идёт обычным путём маршрутизации

Таблица доменов (приоритет 50) проверяется первой — так можно точечно направить отдельные домены поверх подсетей.

Проект намеренно не использует iptables mangle/MARK: они конфликтуют с маршрутизацией по устройствам в Keenetic NDM.

## Потоки

### Поток загрузки (`S99geo-split start`)

Последовательное выполнение (холодный старт идёт последовательно, чтобы не столкнуть временные файлы на роутерах с малым объёмом RAM):

```
1. update-subnets.sh  — проверяет кэш, скачивает, если устарел, заполняет таблицу подсетей
2. update-domains.sh  — проверяет кэш, разрешает, если устарел, заполняет таблицу доменов
3. attach-rules.sh    — прикрепляет ip rule для всех интерфейсов из ROUTE_IN
```

### Поток cron (`S99geo-split refresh`, каждые 15 мин)

```
update-subnets.sh & update-domains.sh  (параллельно)
```

Оба скрипта проверяют свежесть кэша (`MAX_CACHE_AGE`, `DOMAINS_UPDATE_INTERVAL`) — фактическая загрузка происходит, только если кэш устарел. Таблицы маршрутизации перезаполняются по необходимости. Команда `refresh` не трогает ip rule.

### Поток хука NDM (интерфейс UP/DOWN)

```
Интерфейс UP:
  sleep 2 (антидребезг)
  → update-subnets.sh --refill & update-domains.sh --refill  (параллельно)
  → attach-rules.sh                                          (в фоне)

Интерфейс DOWN:
  → detach-rules.sh
```

Хук слушает интерфейс в зависимости от `ROUTE_OUT`:
- `"auto"` → интерфейс с маршрутом по умолчанию
- Явное имя → только указанный интерфейс

## Команды управления

```sh
/opt/etc/init.d/S99geo-split <command>
```

| Команда | Действие | Режим |
|---------|--------|------|
| `start` | `update-subnets.sh` → `update-domains.sh` → `attach-rules.sh` | Последовательно |
| `stop` | `detach-rules.sh` — удаляет ip rule и очищает таблицы маршрутов | Синхронно |
| `restart` | `stop` → `sleep 1` → `start` | Синхронно |
| `status` | `status.sh` — диагностика | Синхронно |
| `refresh` | `update-subnets.sh` & `update-domains.sh` (проверка свежести) | Параллельно |
| `update` | `update-subnets.sh --force` & `update-domains.sh --force` | Параллельно |
| `update-subnets` | `update-subnets.sh --force` | Синхронно |
| `update-domains` | `update-domains.sh --force` | Синхронно |

### Диагностика маршрутов

```sh
# Какой интерфейс получит трафик
geo-split/scripts/route-check.sh ozon.ru

# Проверить подсеть CIDR (анализ покрытия по таблицам geo-split)
geo-split/scripts/route-check.sh 5.0.0.0/8

# С точки зрения конкретного клиента (MAC)
geo-split/scripts/route-check.sh github.com --from AA:BB:CC:DD:EE:FF

# JSON для автоматизации / WebUI
geo-split/scripts/route-check.sh --json ozon.ru
```

Принимает домены, IP и запись CIDR. Для CIDR: выбирает 1–3 IP для вердикта маршрута ядра и анализа покрытия по таблицам маршрутизации geo-split (обнаружение пересечений, `geo_split_pct`).

Вердикты: `⇒` geo-split | `⊙` туннель | `⚠` смешанный (CDN) | `→` по умолчанию

## Конфигурация

Файл конфигурации: `config/config.conf`

### Полная таблица параметров

| Параметр | По умолчанию | Описание |
|-----------|---------|-------------|
| `GEO_ZONE` | `"eas"` | Геозона: код ISO 3166-1 (ru, cn) или объединение (eas, cis, brics). См. `lib/geo.sh` |
| `ROUTE_OUT` | `"auto"` | Целевой исходящий интерфейс. `auto` = ISP из маршрута по умолчанию |
| `ROUTE_GW` | `"auto"` | Шлюз: `auto` = определить, `none` = только dev, либо явный IP |
| `ROUTE_IN` | `"br0"` | Входящие интерфейсы LAN (через пробел) |
| `DOMAIN_ROUTE_TABLE` | `"1000"` | Таблица маршрутизации для доменов (хостовые маршруты /32) |
| `DOMAIN_RULE_PRIORITY` | `"50"` | Приоритет ip rule для таблицы доменов |
| `SUBNET_ROUTE_TABLE` | `"1001"` | Таблица маршрутизации для подсетей GeoIP (CIDR) |
| `SUBNET_RULE_PRIORITY` | `"51"` | Приоритет ip rule для таблицы подсетей |
| `SUBNET_URL_PATTERN` | `ipdeny.com/…/{cc}.zone` | Шаблон URL загрузки подсетей (`{cc}` = код страны) |
| `SUBNET_URL` | `""` | Переопределение URL (устаревшее): игнорирует GEO_ZONE |
| `SUBNET_LOADER` | `"cidr-plain"` | Загрузчик из каталога `loaders/` |
| `SUBNET_AGGREGATE` | `1` | Агрегация CIDR (1 = включено, нужен `aggregate6`) |
| `MAX_CACHE_AGE` | `604800` | Максимальный возраст кэша подсетей, секунды (7 дней) |
| `DOWNLOAD_RETRIES` | `2` | Число попыток загрузки на интерфейс |
| `DOWNLOAD_RETRY_DELAY` | `3` | Пауза между попытками (секунды) |
| `DOWNLOAD_INTERFACES` | `"default *"` | Интерфейсы загрузки (шаблоны glob), переключение по списку |
| `DNS_FULL_RESOLVER_PORT` | `""` | Порт резолвера DNS (пусто = автоопределение: SmartDNS 6153 → 6053 → системный) |
| `DOMAINS_LIST_FILE` | `geo-split-data/lists/domains.txt` | Файл списка доменов (поддерживается `@include`) |
| `DOMAINS_UPDATE_INTERVAL` | `3600` | Интервал обновления доменов, секунды (1 час; `0` = отключить) |
| `REFRESH_NICE_ADJUST` | `10` | Поправка приоритета CPU для заданий cron refresh (0 = выкл., 1–19 = ниже приоритет) |

### Примеры конфигурации

**ЕАЭС → ISP (по умолчанию, конфигурация не нужна):**
```sh
GEO_ZONE="eas"
ROUTE_OUT="auto"
```

**Одна страна (пример):**
```sh
GEO_ZONE="ru"
```

**Региональные сервисы через туннель (совместимость сервисов):**
```sh
GEO_ZONE="cis"
ROUTE_OUT="nwg0"
```

**GEO-трафик через конкретный интерфейс ISP:**
```sh
ROUTE_OUT="lte_br0"
```

**Несколько интерфейсов LAN (основная и гостевая сети):**
```sh
ROUTE_IN="br0 br1"
```

**Отключить разрешение доменов:**
```sh
DOMAINS_UPDATE_INTERVAL=0
```

## Файлы

| Файл | Назначение |
|------|---------|
| `scripts/attach-rules.sh` | Прикрепление ip rule для всех интерфейсов из `ROUTE_IN` (домены, приоритет 50; подсети, приоритет 51) |
| `scripts/detach-rules.sh` | Снятие ip rule и очистка таблиц маршрутов |
| `scripts/update-subnets.sh` | Загрузка подсетей GeoIP через загрузчик и заполнение таблицы подсетей |
| `scripts/update-domains.sh` | Разрешение доменов через DNS (dig → хостовые маршруты /32 в таблице доменов) |
| `scripts/ndm-hook.sh` | Хук NDM: согласование таблиц маршрутизации при смене состояния интерфейсов |
| `scripts/route-check.sh` | Диагностика маршрутов: куда уходит трафик к хосту, IP или CIDR |
| `scripts/wan-paths.sh` | Список всех путей выхода WAN (ISP и туннельные интерфейсы) в JSON через API NDM |
| `scripts/status.sh` | Диагностика: режим, правила, таблицы, кэши |
| `loaders/cidr-plain.sh` | Загрузчик: простой CIDR (по умолчанию) |
| `loaders/ripe-json.sh` | Загрузчик: JSON API RIPE (нужен `jq`) |
| `config/config.conf` | Конфигурация (режим, интерфейсы, URL, интервалы) |
| `init.d/S99geo-split` | Скрипт инициализации (start/stop/restart/status/refresh/update) |

Данные (списки доменов, зоны GeoIP) лежат в отдельном пакете [`geo-split-data`](../geo-split-data/).

## Загрузчики

Загрузчики — скрипты в каталоге `loaders/`. Они скачивают подсети CIDR из внешних источников и пишут их в stdout (одна подсеть на строку).

| Загрузчик | Описание | Зависимости |
|--------|-------------|--------------|
| `cidr-plain` | CIDR обычным текстом, фильтрация IPv6. По умолчанию | `curl` |
| `ripe-json` | JSON API RIPE Stat | `curl`, `jq` |

Выбор загрузчика в `config/config.conf`:

```sh
SUBNET_LOADER="cidr-plain"
SUBNET_URL="https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/ru.cidr"
```

## Диагностика (status.sh)

```sh
/opt/etc/init.d/S99geo-split status
```

Пример вывода:

```
geo-split status: ✓ Alive
  Mode:
    Geo zone:    eas → [ru by kz am kg]
    Route in:    br0
    Route out:   auto (detect ISP)
    Active out:  apcli0 (isp, tables 1000,1001)
    Gateway:     192.168.1.1

  IP rules:
    iif br0 → table 1000 (domains) ✓
    iif br0 → table 1001 (subnets) ✓

  Routes:
    Domains:     183 routes in table 1000, filled 32m 56s ago ✓
    Subnets:     9274 routes in table 1001, filled 33m 31s ago ✓

  Caches:
    Subnets:     cache 2d 6h 51m old (max 7d 0h 0m) ✓
    Domains:     183 in cache, 33m 11s old (max 1h 0m 0s) ✓

  Domain sources: 103 domain(s) configured

  System:
    Uptime:      2d 5h ✓
    Cron:        1 job(s) (shift 7m) ✓
    NDM hook:    /opt/etc/ndm/ifstatechanged.d/geo-split-hook ✓
    DL iface:    default (cached)
    DNS:         localhost:6153 (SmartDNS no-speed-check)
    Background:  idle
    Loader:      cidr-plain
    Version:     0.17.4
```

**Код выхода:** `0` — всё в порядке, `1` — есть проблемы (✗ в выводе).

## Компоненты KeeneticOS (прошивка)

Чтобы `geo-split` работал, в прошивке Keenetic должны быть включены определённые базовые компоненты. Это **компоненты прошивки** (не пакеты Entware) — их включают через веб-интерфейс роутера или CLI Keenetic.

### Обязательные

| Компонент | Назначение |
|-----------|---------|
| **OPKG** (установка пакетов из репозитория Entware) | Без него нет `/opt`, Entware, скриптов инициализации `/opt/etc/init.d/` и хуков NDM `/opt/etc/ndm/ifstatechanged.d/`. Это базовое условие всего проекта. |
| **Драйверы файловых систем** (Ext4 / ExFAT — под тип USB-накопителя) | Нужны, чтобы смонтировать накопитель с Entware. |

### Не требуются

Проект использует только политику маршрутизации (`ip rule` и отдельные таблицы маршрутизации). Поэтому следующее **не нужно**:

- ❌ «Модули ядра подсистемы Netfilter» (iptables MARK / mangle) — архитектурное решение: проект идёт путём маршрутов, без fwmark.
- ❌ `ipset`, `nftables` — не используются.
- ❌ «DNS-Override» и модули подмены DNS — при необходимости это делает отдельный подпроект [`smartdns-geo-conf/`](../smartdns-geo-conf/README.md).

### Как включить компоненты

**Через веб-интерфейс:**
1. Откройте *Общие настройки → Изменить набор компонентов* (в других версиях прошивки пункт может называться *Управление → Параметры системы → Обновление компонентов*).
2. В разделе *«Система»* / *«Другое»* включите **OPKG** (часто называется «Поддержка пакетов OPKG»).
3. Убедитесь, что включён драйвер файловой системы под тип USB-накопителя (Ext4 или ExFAT).
4. Примените изменения → роутер обновит прошивку и перезагрузится.

**Через CLI Keenetic** (telnet/ssh на сам роутер, не в Entware):
```
(config)> components install opkg
(config)> system configuration save
```

После этого подключите USB-накопитель с Ext4 и установите Entware по [официальной инструкции Keenetic](https://help.keenetic.com/hc/ru/articles/360021214160).

## Зависимости

| Пакет | Тип | Назначение |
|---------|------|---------|
| `keenetic-entware-extras` | Depends | Базовый пакет (общие библиотеки) |
| `geo-split-data` | Depends | Списки доменов и зоны GeoIP |
| `ip-full` | Depends | `ip rule`, `ip route`, `ip -batch` |
| `curl` | Depends | Загрузка подсетей |
| `bind-dig` | Depends | Разрешение доменов через DNS |
| `aggregate6` | Depends | Агрегация подсетей CIDR |
| `coreutils-touch` | Depends | Метки времени файлов кэша |
| `jq` | Recommends | Для загрузчика `ripe-json` |

## Для разработчиков

Развёртывание на роутер (без .ipk):

```sh
scp -O -r geo-split/ root@<router>:/opt/keenetic-entware-extras/geo-split/
scp -O -r lib/ root@<router>:/opt/keenetic-entware-extras/lib/
ssh root@<router> '/opt/etc/init.d/S99geo-split restart'
```
