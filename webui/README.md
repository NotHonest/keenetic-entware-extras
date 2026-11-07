# webui

> 📖 **[Руководство пользователя](docs/user-manual.ru.md)** — пошаговая установка, настройка и устранение неполадок.

Веб-панель мониторинга для Keenetic/Entware — дашборд статуса служб и патч штатного WebUI со своим меню и вставкой карточек.

Типичные сценарии:
- 📊 **Мониторинг:** единый дашборд статуса для geo-split, smartdns-geo-conf, smartdns-redirect и системы (uptime, RAM, диск)
- 🎨 **Интеграция:** карточка Entware Extras на штатном дашборде Keenetic и диалог расположения карточек через inject.js (карточка на дашборде и необязательный сайдбар, по умолчанию `INJECT_SIDEBAR=0`)
- 🔌 **API:** эндпоинты JSON для автоматизации и мониторинга через Lua

## Установка

Нужен настроенный [репозиторий opkg](../releases/README.md).

```sh
opkg install webui
```

Зависимости (`keenetic-entware-extras`, `nginx`, `nginx-mod-lua`, `logrotate`) ставятся автоматически.

> `config/nginx.conf`, `config/logrotate.conf`, `config/config.conf` — conffiles: сохраняются при `opkg upgrade`.

После установки:

```sh
# Дашборд доступен сразу (postinst запускает службу)
# Свой дашборд:
curl http://<router-ip>:8080/custom/

# Пропатченный штатный WebUI:
curl http://<router-ip>:8080/
```

## Удаление

```sh
opkg remove webui
```

Автоматически выполняется: остановка nginx-webui, удаление htdocs-cache, удаление init-скрипта и конфигурации logrotate. Журналы сохраняются для проверки.

## Архитектура

Отдельный экземпляр nginx на порту `:8080`, независимый от штатного httpd Keenetic (:80). Штатный UI патчится в tmpfs при start/reload — исходные файлы не изменяются.

```
Браузер → nginx :8080
  ├── /custom/*     → статика (свой дашборд, JS/CSS)
  ├── /api/*        → content_by_lua (api-router.lua) → shell → JSON
  ├── /auth, /rci/  → proxy_pass 127.0.0.1:80 (штатный httpd, WebSocket)
  └── /*            → статика webui/htdocs-cache/ (пропатченные бандлы) + @stock /usr/share/htdocs_ (flash)
                      └── patch-stock-ui.sh: inject.js + inject.css + автоопределённые патчи бандла
```

### Патч штатного UI

При `start` или `reload` скрипт `patch-stock-ui.sh`:

1. Копирует только файлы бандла (`index.html`, `main-*.js`, `polyfills-*.js`, `styles-*.css`) из `/usr/share/htdocs_/` → `webui/htdocs-cache/`
2. Патчит `index.html` — вставляет теги `<script>` и `<link>` (`inject.js`, `inject.css`)
3. Автоматически определяет семейство патча по архитектурным маркерам в штатном бандле
4. Подключает `patches/families/<family>.sh` и применяет патчи с enum, найденным во время выполнения
5. При любой ошибке патча откатывается к чистому штатному бандлу
6. Заранее сжимает бандлы gzip для `gzip_static`
7. Записывает `webui/htdocs-cache/.patch-state` для `status.sh`
8. nginx отдаёт пропатченные файлы из htdocs-cache/, непропатченные — через запасной `@stock` с flash

**Автоопределение** — скрипт ищет в штатном бандле `Xx={INTERNET:"INTERNET"` (определение enum DashboardSection), затем определяет **семейство** патча по архитектурным маркерам:

| Семейство | Маркер | Прошивка |
|-----------|--------|----------|
| `signal` | `this.templateMap().get` | KeeneticOS 5.1.0+ |
| `setter` | `set order(e){this.elementsOrder=e}` | KeeneticOS 5.0.x |

Переименования enum (изменения минификатора) обрабатываются автоматически — обновление пакета не нужно. См. [patches/README.md](patches/README.md).

## Команды управления

```sh
/opt/etc/init.d/S80nginx-webui <command>
```

| Команда | Действие |
|---------|----------|
| `start` | Патчит штатный UI (`patch-stock-ui.sh`) и запускает nginx-webui |
| `stop` | Останавливает nginx-webui и удаляет `webui/htdocs-cache` |
| `restart` | `stop` + `start` |
| `reload` | Повторный патч + `nginx -s reload` (для обновлений после обновления прошивки) |
| `check` / `status` | Проверка статуса (запущен / не запущен) |

Подробная диагностика:

```sh
/opt/keenetic-entware-extras/webui/scripts/status.sh
/opt/keenetic-entware-extras/webui/scripts/status.sh --json
```

## Конфигурация

Файл конфигурации: `config/config.conf`

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `ENABLED` | `"yes"` | Включить или выключить службу (`"yes"` / `"no"`) |
| `LISTEN_PORT` | `8080` | Порт nginx-webui |
| `INJECT_SIDEBAR` | `0` | Вставка меню в сайдбар штатного UI (0/1) |
| `DASH_POLL_INTERVAL` | `30000` | Интервал опроса API дашборда (мс) |
| `PIDFILE` | `/opt/tmp/nginx-webui.pid` | PID-файл (tmpfs — сбрасывается при перезагрузке) |
| `LOG_TAG` | `"kee-webui"` | Метка для logger |

> **Адрес прослушивания:** создаётся в `config/listen.conf` во время `postinst` (через `detect_router_ip`) + `listen 127.0.0.1:8080`. IP в коде не зашит.

После изменения конфигурации:

```sh
/opt/etc/init.d/S80nginx-webui restart
```

## API

Все эндпоинты обслуживаются через `content_by_lua_file api-router.lua`.

### GET (статус)

| Метод | Эндпоинт | Описание |
|-------|----------|----------|
| GET | `/api/system/info` | Сведения о системе (hostname, uptime, RAM, диск) |
| GET | `/api/system/zones` | Список геозон для выпадающего списка (TTL 1 ч) |
| GET | `/api/system/dns-providers` | DNS-провайдеры для редактора конфигурации (TTL 1 ч) |
| GET | `/api/geo-split/status` | Статус geo-split |
| GET | `/api/smartdns/status` | Статус smartdns-geo-conf |
| GET | `/api/smartdns-redirect/status` | Статус smartdns-redirect |
| GET | `/api/webui/status` | Самодиагностика webui |

### POST (действия)

Возвращают `405 Method Not Allowed`, если вызваны не методом POST.

| Метод | Эндпоинт | Описание |
|-------|----------|----------|
| POST | `/api/geo-split/start` | Запустить geo-split |
| POST | `/api/geo-split/stop` | Остановить geo-split |
| POST | `/api/smartdns/start` | Включить конфигурацию smartdns |
| POST | `/api/smartdns/stop` | Выключить конфигурацию smartdns |
| POST | `/api/smartdns-redirect/start` | Запустить dns-redirect |
| POST | `/api/smartdns-redirect/stop` | Остановить dns-redirect |
| POST | `/api/geo-split/update-subnets` | Обновить подсети (в фоне) |
| POST | `/api/geo-split/update-domains` | Обновить домены (в фоне) |
| POST | `/api/webui/flush-cache` | Сбросить кэш статуса UI (принудительно свежие данные) |
| POST | `/api/smartdns/flush-cache` | Сбросить постоянный кэш SmartDNS (stop + rm + restart) |

### GET/POST (конфигурация)

| Метод | Эндпоинт | Описание |
|-------|----------|----------|
| GET | `/api/{service}/config` | Прочитать текущую конфигурацию службы |
| POST | `/api/{service}/config` | Сохранить конфигурацию и перезапустить службу |

### GET (диагностика)

`route-check` и `dns-check` ограничены 2 запросами в секунду на IP, всплеск 10. `tunnel-check` и `ladder` в это ограничение не входят. `ladder` без curl, экран сценария спрашивает его примерно раз в 30 секунд.

| Метод | Эндпоинт | Описание |
|-------|----------|----------|
| GET | `/api/geo-split/ladder` | Лестница соединений Keenetic: приоритет, `ping-check`, кто сейчас основной, куда привязан зарубежный DNS. Только чтение, без curl |
| GET | `/api/geo-split/tunnel-check` | Проходит ли трафик через интерфейс основного маршрута. `?dev=` задаёт имя `[a-z0-9_]`, не длиннее 15 символов. Только чтение |
| GET | `/api/geo-split/route-check?host=...&from=...` | Проверка маршрута до хоста (from: MAC клиента или `local`) |
| GET | `/api/smartdns/dns-check?host=...` | Диагностика DNS: зона, upstream, разрешение |
| GET | `/api/geo-split/wan-paths` | Список путей WAN (для схемы) |
| GET | `/api/system/clients` | Список клиентов с политиками маршрутизации |
| GET | `/api/system/interfaces` | Сетевые интерфейсы с подписями |

### Формат ответа

**system/info:**
```json
{"ok":true,"hostname":"Keenetic","uptime":"5d 3h 12m","memory":{"total_kb":262144,"available_kb":180000},"disk_opt":{"total_kb":7654321,"used_kb":1234567,"free_kb":6419754}}
```

**Эндпоинты статуса:** JSON напрямую из `status.sh --json`:
```json
{"running":true,"ok":true,"details":{...}}
```

**Эндпоинты действий:**
```json
{"ok":true,"output":"..."}
```

## Диагностика (status.sh)

```sh
/opt/keenetic-entware-extras/webui/scripts/status.sh
```

Пример вывода:

```
nginx-webui status:
  Service:
    Process:     running (pid 1234 via pidfile, RSS 2048kB) ✓
    Config:      /opt/keenetic-entware-extras/webui/config/nginx.conf ✓
    Lua module:  /opt/lib/nginx/modules/ngx_http_lua_module.so ✓
    Port:        :8080 listening ✓

  HTTP:
    Static:      GET / → 200 ✓
    API:         GET /api/system/info → 200 ✓

  Logrotate:
    Binary:      /opt/sbin/logrotate ✓
    Config:      /opt/etc/logrotate.d/nginx-webui ✓
    Cron daily:  /opt/etc/cron.daily/logrotate ✓

  System:
    Uptime:      5d 3h 12m ✓
    Version:     x.y.z
```

**Код выхода:** `0` — всё в порядке, `1` — найдены проблемы (✗ в выводе).

## Файлы

| Файл | Назначение |
|------|------------|
| `config/config.conf` | Конфигурация (ENABLED, порт, сайдбар, интервал опроса) |
| `config/nginx.conf` | Конфигурация nginx (listen, proxy, пути Lua, gzip) |
| `config/logrotate.conf` | Logrotate: ротация журнала ошибок nginx-webui |
| `config/listen.conf` | Адрес прослушивания (создаёт postinst, это не conffile) |
| `lua/api-router.lua` | Маршрутизатор Lua: /api/* → команды shell → JSON |
| `lua/serve-index.lua` | (в текущей архитектуре не используется) |
| `lua/stock-css-init.lua` | Lua: сканирование штатного CSS при старте nginx |
| `lua/api-config.lua` | Lua: чтение и сохранение конфигурации служб |
| `lua/api-data.lua` | Lua: эндпоинты данных зон и провайдеров |
| `lua/api-system.lua` | Lua: сведения о системе, клиенты, интерфейсы |
| `lua/api-utils.lua` | Lua: общие утилиты (exec, JSON, кэширование) |
| `patches/families/setter.sh` | Автоопределяемая логика патча для Angular на setter (5.0.x) |
| `patches/families/signal.sh` | Автоопределяемая логика патча для Angular на signal (5.1.0+) |
| `scripts/patch-stock-ui.sh` | Копирует штатный UI в tmpfs и применяет патчи |
| `scripts/status.sh` | Диагностика: процесс, порт, конфигурация, HTTP, logrotate |
| `static/index.html` | Свой дашборд — HTML, сверху экран сценария |
| `static/scenario.js` | Экран сценария: зона `eas`, выход на провайдера, вход `br0`. Лестница читает приоритет и текущую привязку зарубежного DNS. Приоритет Keenetic не меняет |
| `static/app.js` | Свой дашборд — JS (карточки статуса, вкладки, API) |
| `static/app-sysinfo.js` | Секция сведений о системе на дашборде |
| `static/config-schemas.js` | Схемы полей редактора конфигурации по службам |
| `static/inject-dashboard.js` | Отрисовка карточки на штатном дашборде |
| `static/shared.js` | Общие утилиты EW.* (SERVICE_APIS, форматтеры, ticker, poller) |
| `static/inject.js` | Вставка в штатный UI (сайдбар, карточка дашборда, переключатель, раскрытие) |
| `static/inject.css` | Стили компонентов inject.js |
| `static/common.css` | Общие стили (кнопки обновления, подсказки) |
| `static/layout.css` | Стили раскладки своего дашборда |
| `static/config-form.js` | Отрисовка формы конфигурации (renderDropdown, renderModalForm) |
| `static/config-editor.js` | Жизненный цикл модального редактора конфигурации, сохранение, сброс, события |
| `static/detail-render.js` | Вспомогательная отрисовка подробностей (общее для app.js и inject-dashboard.js) |
| `static/diagnostics.js` | Модальный UI проверки маршрута и проверки DNS |
| `static/diag-render.js` | Отрисовка результата диагностики (маршрут и DNS) |
| `static/diag-batch.js` | Пакетная таблица диагностики и последовательный запуск |
| `static/route-diagram.js` | SVG-схема маршрута |
| `static/route-diagram.css` | Стили SVG-схемы |
| `static/502.html` | Страница ошибки, когда штатный httpd недоступен |
| `init.d/S80nginx-webui` | Init-скрипт (start/stop/restart/check/status/reload) |

## Журналы

| Файл | Описание |
|------|----------|
| `/tmp/nginx-webui-error.log` | Ошибки nginx и Lua (уровень: error, tmpfs — теряются при перезагрузке) |
| Журнал доступа | Отключён (экономия ввода-вывода; диагностика через `status.sh`) |
| `/opt/etc/logrotate.d/nginx-webui` | Конфигурация logrotate (ежедневно, rotate 3, сжатие, повторное открытие по USR1) |

## Зависимости

| Пакет | Тип | Назначение |
|-------|-----|------------|
| `keenetic-entware-extras` | Зависит | Базовый пакет (общие библиотеки) |
| `nginx` | Зависит | Веб-сервер |
| `nginx-mod-lua` | Зависит | Модуль Lua для nginx (API, init) |
| `logrotate` | Зависит | Ротация журналов |

## Для разработчиков

Сборка .ipk:

```sh
./scripts/build-ipk.sh webui
# Результат: dist/webui_<ver>_all.ipk
```

Развёртывание без .ipk:

```sh
scp -O -r webui/ root@<router>:/opt/keenetic-entware-extras/webui/
scp -O -r lib/ root@<router>:/opt/keenetic-entware-extras/lib/
ssh root@<router> '/opt/etc/init.d/S80nginx-webui restart'
```
