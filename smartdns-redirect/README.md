# smartdns-redirect

> 📖 **[Руководство пользователя](docs/user-manual.ru.md)** — пошаговая установка, настройка и устранение неполадок.

Универсальный DNS DNAT для Keenetic/Entware — перехват LAN `:53` и перенаправление на локальный DNS-резолвер.

## Что это

iptables DNAT в `PREROUTING` для заданных интерфейсов (`br0` LAN, `br1` Guest, `nwg1` WG Server и т. д.): все DNS-запросы клиентов идут сразу на локальный DNS (по умолчанию SmartDNS `:6053`), а не в ndnproxy Keenetic. Сам роутер (ndnproxy :53) **не затрагивается** — работает как раньше.

**Зачем:**
- **Задержка** — замер: ~130 мс → <80 мс у клиентов LAN (минус переход через ndnproxy).
- **Политика split-DNS** работает для клиентов напрямую (SmartDNS сам выбирает upstream).
- **Целостность Keenetic** — ndnproxy не ломается, webui и диагностика не страдают.

**Совместим с:**
- [`smartdns-geo-conf`](../smartdns-geo-conf) (upstream по умолчанию `:6053`)
- AdGuard Home (`UPSTREAM_PORT=5353`)
- Unbound (`UPSTREAM_PORT=5335`)
- dnsmasq (любой порт)
- [`geo-split`](../geo-split) — работает в паре.

## Требования

- Keenetic с Entware
- `opkg install iptables` (ставится автоматически как зависимость)
- Локальный DNS-резолвер на роутере, слушающий порт UDP/TCP (по умолчанию `:6053`)

## Установка

Нужен настроенный [репозиторий opkg](../releases/README.md).

```sh
opkg install smartdns-redirect
```

`postinst` автоматически:
- создаёт символическую ссылку `/opt/etc/ndm/netfilter.d/smartdns-redirect-hook` (восстановление правил после `iptables flush` со стороны NDM),
- добавляет cron watchdog (`*/5 * * * *`) в `/opt/etc/crontab`,
- запускает `S39smartdns-redirect`.

## Конфигурация

Файл: `/opt/keenetic-entware-extras/smartdns-redirect/config/config.conf`

> 📝 В `config.conf` указывайте только параметры, которые отличаются от значений по умолчанию (`defaults.conf`). Файл не создаётся автоматически — создайте его вручную, если нужно. При обновлении пакета обновляется `defaults.conf`, а `config.conf` не трогается.

```sh
UPSTREAM_PORT=6053         # SmartDNS=6053, AGH=5353, Unbound=5335
INTERFACES="br0"           # интерфейсы LAN (через пробел)
WATCHDOG_SERVICE="S38smartdns"   # init-скрипт, который перезапускать при сбое
REDIRECT_MODE="force"          # "force"=перехват ВСЕХ :53 + блок DoT; "local"=только DNS на IP роутера
PRESERVE_FILTER_PROFILES=no      # фаза 5 (не реализовано)
# Обработка IPv6 DNS полностью автоматическая — настройка не нужна.
# DNAT, если у SmartDNS есть bind IPv6, иначе REJECT (запасной путь Happy Eyeballs).
# Блокировка DoT (порт 853) всегда включена — настройка не нужна.
```

После изменения конфигурации:

```sh
/opt/etc/init.d/S39smartdns-redirect restart
```

## Проверка

```sh
# Правила в NAT PREROUTING
iptables -t nat -S PREROUTING | grep DNAT
# Ожидается (10.0.0.1 = LAN IP роутера):
#   -A PREROUTING -i br0 -p udp -m udp --dport 53 -j DNAT --to-destination 10.0.0.1:6053
#   -A PREROUTING -i br0 -p tcp -m tcp --dport 53 -j DNAT --to-destination 10.0.0.1:6053

# Статус
/opt/etc/init.d/S39smartdns-redirect status

# Журналы
logread | grep smartdns-redirect
```

## Как это работает

### Путь запроса клиента LAN

На всех заданных интерфейсах используется `DNAT` на IP br0 — так SmartDNS получает пакет независимо от того, с какого интерфейса он пришёл. DoT (порт 853) всегда блокируется через `FORWARD REJECT` на тех же интерфейсах — клиенты LAN не могут обойти SmartDNS прямым DNS-over-TLS:

```
Клиент (10.0.0.42) → UDP/TCP :53 → br0/br1/nwg1 →
  [iptables PREROUTING DNAT → 10.0.0.1:6053] →
    SmartDNS (10.0.0.1:6053) → upstream (DoT/DoH/UDP)

Клиент → TCP :853 → br0/br1/nwg1 →
  [iptables FORWARD REJECT] → клиент возвращается на :53 → DNAT → SmartDNS
```

Сам роутер (loopback `127.0.0.1:53`) идёт в ndnproxy — правила интерфейсов LAN на него не действуют.

### Устойчивость к NDM

Keenetic периодически сбрасывает iptables через свои хуки netfilter. Символическая ссылка в `/opt/etc/ndm/netfilter.d/` вызывает [`netfilter-hook.sh`](scripts/netfilter-hook.sh) каждый раз, когда NDM трогает таблицы — правила сразу восстанавливаются.

### Сторож

Cron запускает [`watchdog.sh`](scripts/watchdog.sh) каждые 5 минут:

1. Проверяет правила в `PREROUTING` и `FORWARD` (блок DoT) — восстанавливает, если их нет.
2. Отправляет пробный DNS-запрос на `UPSTREAM_PORT`. Если upstream не отвечает — перезапускает `WATCHDOG_SERVICE` (по умолчанию `S38smartdns`).

## Удаление

```sh
opkg remove smartdns-redirect
```

`prerm` / `postrm` откатывают всё: init-скрипт, символическую ссылку, iptables, cron, PID-файл, каталог установки.

## Архитектура

```
smartdns-redirect/
├── config/
│   ├── defaults.conf               # значения по умолчанию
│   └── config.conf                  # 🔧 переопределения пользователя (создать вручную, если нужно)
├── init.d/
│   └── S39smartdns-redirect        # init (start/stop/restart/status)
├── scripts/
│   ├── dns-redirect.sh             # применить/убрать правила iptables
│   ├── netfilter-hook.sh           # хук NDM: восстановление после flush
│   ├── watchdog.sh                 # cron: наличие правил + доступность upstream
│   └── status.sh                   # диагностика
└── docs/
    └── user-manual.ru.md
```

## Лицензия

MIT — см. [LICENSE](../LICENSE).
