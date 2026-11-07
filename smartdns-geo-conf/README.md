# smartdns-geo-conf

> 📖 **[Руководство пользователя](docs/user-manual.ru.md)** — пошаговая установка, настройка и устранение неполадок.

Конфигурация SmartDNS для split-DNS с настраиваемыми геозонами на Keenetic/Entware.

## Что это

Split DNS: маршрутизация DNS-запросов по геозонам.

- **Зоны** (настраиваются: RU, EAEU, CIS, BRICS, EU…) → региональный DNS (Yandex DoT, AdGuard DoT)
- **Всё остальное** → международный DNS (Google DoH, Cloudflare DoH)
- **Защита от MITM** — необязательная привязка DNS-запросов к туннельным интерфейсам

**Зачем:**
- Скорость для доменов внутри зоны — ближайшие узлы CDN через региональный DNS
- Защита целостности DNS для зарубежных доменов — DoH через HTTPS/443
- Гибкость — любая комбинация стран или геоальянсов

## Требования

- Keenetic с Entware
- `opkg install smartdns` (ставится автоматически как зависимость)
- `opkg install ca-certificates` (ставится автоматически как зависимость)

## Установка

Нужен настроенный [репозиторий opkg](../releases/README.md).

```sh
opkg install smartdns-geo-conf
```

## Направление DNS-трафика в SmartDNS

После установки DNS-запросы клиентов нужно направить в SmartDNS. Два варианта:

### Вариант A: smartdns-redirect (рекомендуется)

Установите пакет [`smartdns-redirect`](../smartdns-redirect/) — он автоматически перехватывает DNS-запросы из LAN через iptables DNAT. Менять настройки Keenetic (DNS, DoT/DoH) **не нужно**.

```sh
opkg install smartdns-redirect
```

### Вариант B: ручная настройка DNS Keenetic

Если перехват через DNAT не нужен:

> ⚠️ **Важно:** если в Keenetic настроены серверы DoT/DoH (dns-proxy tls/https), ndnproxy будет использовать их и **игнорировать** обычный DNS, в том числе SmartDNS. Сначала удалите все DoT/DoH.

```sh
# 1. Удалить все серверы DoT/DoH (обязательно для варианта B!)
ndmc -c 'no dns-proxy tls upstream 1.1.1.1'
ndmc -c 'no dns-proxy https upstream https://1.1.1.1/dns-query'
# ... (удалите все свои записи DoT/DoH)

# 2. Добавить SmartDNS как DNS-сервер
ndmc -c 'ip name-server <router-IP>:6053'

# 3. Сохранить
ndmc -c 'system configuration save'
```

**Или через веб-интерфейс:** *Интернет-фильтры → DNS* → удалите все серверы DoT/DoH, добавьте `<router-IP>:6053`.

## Настройка зоны

Файл: `config/config.conf`

```sh
# Зона — одна страна или геоальянс
DNS_ZONE="eas"

# Международные DNS-провайдеры (через пробел)
OTHER_DNS_PROVIDER="google cloudflare"

# Зональные DNS-провайдеры (через пробел)
# По умолчанию: "yandex alidns system" (см. defaults.conf)
ZONE_DNS_PROVIDER="yandex adguard"

# Непустое имя туннеля включает зарубежный DNS через VPN.
# Сторож ведёт его за основным маршрутом: один туннель, без параллельного опроса.
# Запасной VPN задаётся приоритетом соединений Keenetic, не этим списком.
OTHER_DNS_INTERFACES=""

# Туннельный интерфейс для зонального DNS (обычно не нужен)
ZONE_DNS_INTERFACE=""

# Политика шифрования DNS (auto = DoT/DoH + запасной UDP; strict = только шифрование)
DNS_TRANSPORT="auto"
```

### Доступные зоны

| Значение | Описание | Страны |
|----------|----------|--------|
| `ru` | Россия | .ru, .рф, .su |
| `by` | Беларусь | .by |
| `kz` | Казахстан | .kz |
| `am` | Армения | .am |
| `kg` | Кыргызстан | .kg |
| `eas` | ЕАЭС | ru+by+kz+am+kg |
| `cis` | СНГ | ru+by+kz+am+kg+uz+tj+md+az |
| `brics` | БРИКС+ | ru+br+in+cn+za+eg+et+ae+sa+ir |
| `sco` | ШОС | ru+cn+in+kz+kg+pk+tj+uz+ir+by |
| ... | [Полный список →](../lib/geo.sh) | 40+ альянсов |

### DNS-провайдеры

Провайдеры задаются через `OTHER_DNS_PROVIDER` (международные) и `ZONE_DNS_PROVIDER` (зональные/региональные).

**Международные** (`OTHER_DNS_PROVIDER`):

| Значение | Провайдер | Протокол |
|----------|-----------|----------|
| `system` | Системный (Keenetic) | UDP |
| `google` | Google Public DNS | DoH |
| `cloudflare` | Cloudflare | DoH |
| `quad9` | Quad9 (фильтр вредоносного) | DoT |
| `quad9uf` | Quad9 Unfiltered | DoT |
| `mullvad` | Mullvad (без логов) | DoH |
| `mullvad_adblock` | Mullvad + блокировка рекламы | DoH |
| `controld` | ControlD Free | DoH |
| `adguard` | AdGuard (фильтр рекламы) | DoH |

**Зональные/региональные** (`ZONE_DNS_PROVIDER`):

| Значение | Провайдер | Протокол | Регион |
|----------|-----------|----------|--------|
| `system` | Системный (Keenetic) | UDP | — |
| `yandex` | Yandex DNS | DoT+UDP | RU/СНГ |
| `yandex_safe` | Yandex Safe | DoT+UDP | RU/СНГ |
| `yandex_family` | Yandex Family | DoT+UDP | RU/СНГ |
| `adguard` | AdGuard Unfiltered | DoT | RU/СНГ |
| `adguard_ads` | AdGuard Default | DoT | RU/СНГ |
| `alidns` | AliDNS | DoT+UDP | Китай |
| `tencent` | Tencent DNSPod | DoT+UDP | Китай |

### Свои DNS-серверы

Файл `config/dns-providers-custom.conf` позволяет добавить свои DNS-серверы.
При обновлении пакета не перезаписывается. Формат тот же, что у `dns-providers.conf`:

```sh
# Обычный UDP
OTHER_mydns_LABEL="My DNS"
OTHER_mydns_PROTO="udp"
OTHER_mydns_IP1="1.2.3.4"
OTHER_mydns_IP2=""

# Затем в config.conf:
OTHER_DNS_PROVIDER="google mydns"
```

Поддерживаемые протоколы: `udp`, `dot` (DoT), `doh` (DoH).
Для DoH поля `IP1`/`IP2` **необязательны** — если их нет, SmartDNS сам разрешает имя хоста.
Обязательны для Private DoH (AdGuard, NextDNS): привязка к IP ломает определение профиля.
Подробнее — в [user-manual.ru.md](docs/user-manual.ru.md).

> Список провайдеров кэшируется WebUI на 1 час. Чтобы обновить сразу:
> `/opt/etc/init.d/S80nginx-webui restart`

### Применение изменений

```sh
/opt/etc/init.d/S37smartdns-conf restart
```

### Примеры конфигурации

**ЕАЭС (по умолчанию):**
```sh
DNS_ZONE="eas"
OTHER_DNS_PROVIDER="google cloudflare"
ZONE_DNS_PROVIDER="yandex adguard"
```

**Только Россия + Quad9:**
```sh
DNS_ZONE="ru"
OTHER_DNS_PROVIDER="quad9"
ZONE_DNS_PROVIDER="yandex"
```

**Китай (AliDNS + Tencent):**
```sh
DNS_ZONE="cn"
ZONE_DNS_PROVIDER="alidns tencent"
```

**Международный DNS через туннель (защита от MITM):**
```sh
OTHER_DNS_INTERFACES="nwg3 nwg4"
```

## Управление

```sh
# Включить split-DNS
/opt/etc/init.d/S37smartdns-conf enable

# Выключить (полное отключение — DNS возвращается к системе Keenetic/ndnproxy)
/opt/etc/init.d/S37smartdns-conf disable

# Статус
/opt/etc/init.d/S37smartdns-conf status

# Перегенерировать конфиги и перезапустить SmartDNS
/opt/etc/init.d/S37smartdns-conf restart

# Сбросить постоянный кэш DNS (останавливает SmartDNS, удаляет кэш, запускает снова)
/opt/etc/init.d/S37smartdns-conf flush-cache

# Диагностика
/opt/keenetic-entware-extras/smartdns-geo-conf/scripts/status.sh
```

### Диагностика DNS-зоны

`dns-check.sh` — утилита CLI: показывает, какая DNS-зона/группа и какой upstream разрешают заданный домен:

```sh
/opt/keenetic-entware-extras/smartdns-geo-conf/scripts/dns-check.sh <domain>
```

Пример вывода:
```
DNS Zone Check: ya.ru

  Zone:       ru (match: /.ru/, type: ccTLD)

  ✓ eas:  yandex adguard
    default:  google cloudflare

  Upstream:   Yandex DNS, AdGuard Unfiltered
  Servers:    77.88.8.8:853, 94.140.14.140:853
  Interface:  direct

  Result:     5.255.255.242 (TTL 300, 4ms)
```

Вывод JSON (для WebUI / автоматизации):
```sh
/opt/keenetic-entware-extras/smartdns-geo-conf/scripts/dns-check.sh --json ya.ru
```

## Порты

| Порт | Назначение |
|------|------------|
| 6053 | Основной DNS (все запросы) |
| 6153 | geo-split (все IP, без speed-check) |

## Структура

```
smartdns-geo-conf/
├── config/
│   ├── config.conf            # 🔧 конфигурация пользователя
│   ├── defaults.conf          # значения по умолчанию
│   ├── dns-providers.conf     # каталог DNS-провайдеров (15 провайдеров)
│   ├── zone-routing-rules.conf # IDN TLD + дополнительные домены CDN (80+ стран)
│   ├── test-domains.conf      # тестовые домены для status.sh
│   └── smartdns.conf          # шаблон режима split-DNS
├── init.d/
│   └── S37smartdns-conf       # init-скрипт (enable/disable/restart)
├── scripts/
│   ├── dns-check.sh           # диагностика DNS-зоны
│   ├── generate-conf.sh       # динамический генератор конфигурации
│   ├── status.sh              # диагностика
│   └── toggle.sh              # помощник enable/disable (устаревший, используется API)
└── docs/
    └── user-manual.ru.md
```

## Добавление домена в зону

Чтобы добавить дополнительные домены в DNS-маршрутизацию зоны (например, для оптимизации CDN):

1. Отредактируйте `config/zone-routing-rules.conf` — добавьте домен в секцию нужной страны
2. `/opt/etc/init.d/S37smartdns-conf restart`

Пример (добавить `example.com` в зону RU):
```conf
# В zone-routing-rules.conf, в секции [extra:ru]:
example.com
```
