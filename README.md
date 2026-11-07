# Keenetic Entware Extras

> ⚠️ **Это независимый проект сообщества.** Он **не** связан с компанией [Keenetic Ltd](https://keenetic.com), не одобрен и не поддерживается ею. «Keenetic» — товарный знак Keenetic Ltd.

> 📖 **[Руководство пользователя](user-manual.ru.md)** — установка, настройка, диагностика.

Набор пакетов `.ipk` для роутеров Keenetic с Entware. Маршрутизация по странам, DNS по зонам и диагностика сети. Всем этим можно управлять из браузера.

> Этот репозиторий — форк [0xkee/keenetic-entware-extras](https://github.com/0xkee/keenetic-entware-extras). Готовые пакеты публикует автор оригинала. Фид `https://0xkee.github.io/keenetic-entware-extras/stable` и скрипт установки с `raw.githubusercontent.com/0xkee/...` **не** содержат локальные файлы этого дерева: русский экран сценария, `tunnel-check`, `ladder.sh` и сторож `dns-tunnel-watch.sh`. Команда `opkg upgrade` для `webui`, `geo-split` и `smartdns-geo-conf` заменяет эти файлы. `config.conf` — conffile, opkg его сохраняет. Статика, Lua и скрипты — нет. Вернуть форк: `KEE_PASS_FILE=/путь/к/файлу-с-паролем ./scripts/reapply-fork.sh`. Скрипт не загружает `config.conf` и `defaults.conf`.

## Что умеет

- 🌍 **Делит трафик по странам** — региональный трафик через провайдера, остальное через туннель, или наоборот
- 🔗 **DNS по региону** — местные домены спрашивают ближайший DNS, зарубежные — по зашифрованному каналу
- ⚡ **Быстрее DNS для всех устройств** — клиенты получают ответ напрямую, без штатного прокси роутера
- 🔍 **Диагностика сети** — одна команда проверяет, куда ушёл трафик, ищет аномалии и подмену DNS
- 📊 **Веб-панель** — статус, правки конфигов и карточка в штатном интерфейсе Keenetic

## Пакеты

### 🌍 geo-split

**Маршрут по стране.**

Трафик в выбранные страны идёт одним путём (например, через провайдера), всё остальное — другим (например, через шифрованный туннель). Работает со списками GeoIP и доменов: домены резолвятся в IP и тоже получают маршрут.

- 240 стран и 40 региональных союзов (ЕАЭС, БРИКС, ЕС, АСЕАН…)
- Сам подхватывает смену интерфейса (хук NDM)
- Сжатие CIDR: около 13 тысяч подсетей превращаются в около 8,5 тысяч маршрутов
- Политика через `ip rule` и `ip route`, без iptables. Совместимо с маршрутизацией Keenetic по устройствам
- Режим `ROUTE_OUT=auto` берёт первый default, который не туннель и не мост `br*`. Сначала основная таблица, затем `table all`

→ [Подробнее](geo-split/README.md) · [Руководство](geo-split/docs/user-manual.ru.md)

### 🔗 smartdns-geo-conf

**DNS по региону.**

Запросы к региональным доменам (`.ru`, `.рф`, `.by`…) уходят к ближайшим серверам (Яндекс, AdGuard). Остальное — к зарубежным (Google, Cloudflare) по зашифрованному каналу. Свои сайты отвечают быстрее, чужие резолвятся устойчивее.

- 15 DNS-провайдеров, можно выбрать несколько
- Зона: одна страна или союз
- Зарубежный DNS можно привязать к туннелю. Прямой сервер рядом не держится: у SmartDNS 46 нет `-fallback`, а быстрый ответ провайдера мог бы обогнать ответ из туннеля
- Зарубежный DNS идёт в тот VPN, который сейчас является основным маршрутом. Один туннель, без параллельного прямого сервера. Если живого VPN не осталось или текущий дважды молчит, DNS временно спрашивает напрямую. Приоритет соединений Keenetic скрипт не меняет

→ [Подробнее](smartdns-geo-conf/README.md) · [Руководство](smartdns-geo-conf/docs/user-manual.ru.md)

### ⚡ smartdns-redirect

**Быстрее DNS для всех устройств в сети.**

Перехватывает DNS-запросы из LAN и отдаёт их локальному резолверу (SmartDNS, AdGuard Home, Unbound) вместо Keenetic ndnproxy. Собственный DNS роутера не затрагивается.

- Замер: около 130 мс становятся меньше 80 мс
- Переживает сброс iptables Keenetic (хук netfilter.d)
- Закрывает утечку DNS-over-TLS с клиентов
- IPv6: автоматический DNAT или REJECT с откатом Happy Eyeballs

→ [Подробнее](smartdns-redirect/README.md) · [Руководство](smartdns-redirect/docs/user-manual.ru.md)

### 🔍 net-check

**Набор диагностики сети.**

Одна команда проверяет путь трафика, подлинность DNS-ответов и подмену сертификатов. Можно сравнить интерфейсы и скрыть лишние данные перед тем, как делиться выводом.

- 9 модулей: выход GeoIP, связность, утечка IPv6, резолвинг, утечка DNS, доступность HTTP, география CDN, подмена TLS, скорость
- Проверка одного ресурса: `net-check.sh check youtube.com`
- Вывод JSON для автоматизации

→ [Подробнее](net-check/README.md) · [Руководство](net-check/docs/user-manual.ru.md)

### 📊 webui

**Панель в браузере.**

Панель на порту `:8080` со статусом сервисов. Редактор конфигов с проверкой, выбор зоны и провайдеров, переключатели. В штатный дашборд Keenetic добавляется карточка Entware Extras и, по желанию, пункт в боковом меню.

- Редактор конфигов по схемам для всех пакетов
- API статуса с кэшем в общей памяти: несколько вкладок почти не грузят CPU
- Сам патчит бандлы штатного интерфейса KeeneticOS 5.0–5.2
- Сведения о системе: CPU, память, диск, время работы
- Экран сценария на `/custom/`: зона ЕАЭС через провайдера, остальное по основному маршруту Keenetic. Кнопка не меняет приоритет соединений. Лестница соединений только читает приоритет и `ping-check`
- `GET /api/geo-split/tunnel-check` только проверяет, проходит ли трафик через интерфейс. Маршруты не трогает
- `GET /api/geo-split/ladder` только читает лестницу соединений, без curl

→ [Подробнее](webui/README.md) · [Руководство](webui/docs/user-manual.ru.md)

## Установка

### Что нужно заранее

На роутере Keenetic должен стоять Entware. Официальная инструкция: [установка Entware](https://help.keenetic.com/hc/ru/articles/360021214160).

Скрипту установки нужен `curl`. В базовом Entware его нет. Поставьте его отдельно:

```sh
opkg update && opkg install curl
```

### Быстрая установка пакетов из фида

Одна команда подключает opkg-фид, ставит поддержку HTTPS и открывает меню пакетов. Это пакеты **оригинального** фида, без файлов этого форка:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh
```

Сразу конкретные пакеты:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh -s -- geo-split webui
```

Все пакеты:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh -s -- --all
```

### Ручная установка

```sh
# Подключить opkg-фид
cat >> /opt/etc/opkg.conf << 'EOF'
src/gz kee https://0xkee.github.io/keenetic-entware-extras/stable
src/gz aggr6 https://0xkee.github.io/aggregate6/stable
EOF
opkg update

# Зависимости подтянутся сами
opkg install geo-split smartdns-geo-conf smartdns-redirect net-check webui
```

Каналы stable и dev, переключение и обновление: [описание репозитория](releases/README.md).

Файлы из этого дерева кладутся поверх каталога `/opt/keenetic-entware-extras/`. У nginx включён `gzip_static`: рядом со статикой webui нужен свежий файл `.gz`, иначе браузер получит старую копию. Новый адрес API начинает работать после перезапуска `S80nginx-webui`.

### Обновление пакетов из фида

Повторный запуск скрипта видит уже стоящие пакеты и обновляет их:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh
```

Принудительная переустановка выбранных пакетов:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh -s -- --force geo-split webui
```

Или вручную:

```sh
opkg update && opkg upgrade
```

После `opkg upgrade` локальные файлы форка нужно положить на роутер заново. `config.conf` сохранится.

### Удаление

Одна команда снимает все пакеты и фид:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh -s -- --uninstall
```

Или вручную:

```sh
opkg remove webui net-check smartdns-redirect smartdns-geo-conf geo-split geo-split-data
opkg remove keenetic-entware-extras
sed -i '/kee/d' /opt/etc/opkg.conf
```

## Диагностика

После установки `kee-status` показывает сводку сервисов:

```sh
kee-status          # цветной вывод
kee-status -d       # подробно: полный статус каждого пакета
```

Для сообщения об ошибке скрипт собирает сведения о системе без паролей и ключей:

```sh
/opt/keenetic-entware-extras/scripts/bug-report.sh
```

## Требования

- Роутер Keenetic с установленным **Entware**
- **KeeneticOS 5.0+**
- Зависимости пакетов ставятся через opkg

## Лицензия

[MIT](LICENSE)
