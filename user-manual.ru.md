# keenetic-entware-extras — Руководство пользователя

> ⚠️ **Это независимый проект сообщества.** Он **не** связан с компанией [Keenetic Ltd](https://keenetic.com), не одобрен и не поддерживается ею. «Keenetic» — товарный знак Keenetic Ltd.

## Что это такое

**keenetic-entware-extras** — базовый пакет проекта. Содержит общие shell-библиотеки и CLI-утилиту `kee-status` для агрегированной диагностики всех установленных модулей.

### Состав

| Компонент | Описание |
|-----------|----------|
| `lib/common.sh` | Логирование, валидация, определение IP роутера, JSON-хелперы |
| `lib/ip.sh` | IP/интерфейс утилиты: CIDR-агрегация, определение ISP, DNS-резолвер |
| `lib/lists.sh` | Обработка списков (@include, дедупликация) |
| `lib/status.sh` | Общие check/show функции для диагностики сервисов |
| `lib/geo.sh` | Гео-данные: 40+ союзов/альянсов (EAEU, BRICS, CIS, SCO…), работа с зонами |
| `lib/zones.sh` | Метки зон: полный ISO 3166-1 alpha-2 справочник (249 стран/территорий) |
| `kee-status` | CLI команда — агрегированный статус всех подпакетов |
| `bug-report.sh` | Сбор диагностики для баг-репортов (безопасный, без паролей/ключей) |

### Зачем нужен

Этот пакет **обязателен** для работы всех остальных модулей проекта (geo-split, smartdns-geo-conf, smartdns-redirect, webui). Устанавливается первым.

### Пакеты opkg и этот репозиторий

Готовые `.ipk` ставит фид автора оригинала:

```sh
src/gz kee https://0xkee.github.io/keenetic-entware-extras/stable
```

Скрипт `https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh` берёт пакеты оттуда же. В этих пакетах нет файлов этого форка:

- русский экран сценария в webui;
- проверка туннеля `geo-split/scripts/tunnel-check.sh` и `GET /api/geo-split/tunnel-check`;
- лестница соединений `geo-split/scripts/ladder.sh` и `GET /api/geo-split/ladder`;
- сторож зарубежного DNS `smartdns-geo-conf/scripts/dns-tunnel-watch.sh`.

`opkg upgrade` пакетов `webui`, `geo-split` и `smartdns-geo-conf` заменяет эти файлы версией из фида. `config.conf` объявлен conffile, opkg его не затирает. Статика, Lua и скрипты — не conffile.

Файлы из этого дерева кладутся в `/opt/keenetic-entware-extras/`. У nginx включён `gzip_static`: рядом со статикой webui нужен свежий `.gz`. Новый адрес API начинает отвечать после перезапуска `S80nginx-webui`.

---

## Требования

- Роутер Keenetic с установленным **Entware** — [инструкция по установке Entware](https://help.keenetic.com/hc/ru/articles/360021214160)
- **KeeneticOS 5.0+**

### Программные зависимости

| Пакет | Назначение |
|-------|-----------|
| `curl` | Скрипт установки и API-запросы (не входит в базовый Entware) |
| `cron` | Планировщик задач (обновление данных по расписанию) |

---

## Установка

### Быстрая установка (рекомендуется)

Скрипт установки требует `curl` (не входит в базовый Entware). Установите его:

```sh
opkg update && opkg install curl
```

Одна команда — настраивает opkg-фид, устанавливает HTTPS-поддержку и предлагает меню выбора пакетов:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh
```

Установить конкретные пакеты:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh -s -- geo-split webui
```

Установить все:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh -s -- --all
```

### Ручная установка

#### Подключение opkg-репозитория

```sh
cat >> /opt/etc/opkg.conf << 'EOF'
src/gz kee https://0xkee.github.io/keenetic-entware-extras/stable
src/gz aggr6 https://0xkee.github.io/aggregate6/stable
EOF
opkg update
```

Доступны два канала:
- **stable** (рекомендуемый) — протестированные релизы
- **dev** — последние сборки

Переключение канала:

```sh
sed -i 's|/stable$|/dev|' /opt/etc/opkg.conf
opkg update
```

### Установка пакетов

```sh
opkg install keenetic-entware-extras
```

Устанавливается в `/opt/keenetic-entware-extras/`. Зависимость `cron` подтягивается автоматически.

---

## Использование

### kee-status — агрегированная диагностика

После установки доступна команда `kee-status` (`/opt/bin/kee-status`), которая запускает `status.sh` каждого установленного подпакета и показывает сводку.

```sh
kee-status
```

Пример вывода (все сервисы работают):

```
keenetic-entware-extras status:
  geo-split            Alive
  smartdns-geo-conf    Alive
  smartdns-redirect    Alive
  webui                Alive
```

Пример вывода (есть проблемы):

```
keenetic-entware-extras status:
  geo-split            Alive
  smartdns-geo-conf    FAIL
    Service:
      Ports:       none listening ✗
  smartdns-redirect    Alive
  webui                Disabled
```

При сбое показываются только строки с `✗`, сгруппированные по секциям.

### Флаги

| Флаг | Описание |
|------|----------|
| `-d` / `--details` | Показать полный вывод status для каждого пакета |
| `-n` / `--no-color` | Отключить ANSI-цвета (plain text для логов) |
| `-c` / `--color=always` | Принудительные цвета (для `kee-status \| less -R`) |
| `-h` / `--help` | Справка |

Также поддерживается переменная окружения `NO_COLOR=1`.

### Код возврата

| Код | Значение |
|-----|----------|
| `0` | Все пакеты `Alive` или `Disabled` |
| `1` | Хотя бы один пакет `FAIL` |

### bug-report.sh — сбор диагностики для баг-репортов

Скрипт собирает полную информацию о системе для отправки в форум/тикет. Вывод **очищен от паролей, ключей и WAN-IP** — безопасен для публичной вставки.

```sh
/opt/keenetic-entware-extras/scripts/bug-report.sh
```

Собирает:
- Версия прошивки, ядро, архитектура
- Память и диск
- Установленные kee-пакеты (версии)
- Полный `kee-status --details`
- ip rules, route tables
- Cron, NDM hooks
- Конфиги (без секретов)

Вывод можно скопировать и вставить в сообщение на форуме — или сохранить в файл:
```sh
/opt/keenetic-entware-extras/scripts/bug-report.sh > /tmp/bug-report.txt
```

---

## Порядок установки проекта

После подключения репозитория (см. выше), установите пакеты:

```sh
# 1. Базовый пакет (обязательно первым)
opkg install keenetic-entware-extras

# 2. Данные (опционально, для быстрого старта geo-split)
opkg install geo-split-data

# 3. Модули (в любом порядке)
opkg install geo-split
opkg install smartdns-geo-conf
opkg install smartdns-redirect
opkg install net-check
opkg install webui
```

### Зависимости между модулями

```
keenetic-entware-extras  ← обязательная база для всех
  ├── geo-split          ← требует geo-split-data
  │     └── geo-split-data
  ├── smartdns-geo-conf
  ├── smartdns-redirect
  ├── net-check
  └── webui
```

---

## Обновление

Перезапустите установочный скрипт — он определяет уже установленные пакеты и обновляет их:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh
```

Принудительная переустановка конкретных пакетов:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh -s -- --force geo-split webui
```

Или вручную через opkg:

```sh
opkg update && opkg upgrade
```

Библиотеки обновляются на месте. Все модули продолжают использовать обновлённые версии `lib/*.sh` автоматически.

`opkg upgrade` не сохраняет файлы этого форка: экран сценария, `tunnel-check`, `ladder.sh` и `dns-tunnel-watch.sh`. Конфиги `config.conf` и `defaults.conf` остаются. Вернуть форк одной командой с компьютера, где лежит этот репозиторий:

```sh
KEE_PASS_FILE=/путь/к/файлу-с-паролем ./scripts/reapply-fork.sh
```

Файл пароля — одна строка, пароль root-шелла. Скрипт его не печатает. `--dry-run` показывает список и ничего не отправляет. Команда копирует отличия от `upstream/master`, кроме `config.conf` и `defaults.conf`, заново собирает `.gz` для статики и перезапускает панель и SmartDNS. Службу geo-split она не перезапускает. По умолчанию хост `root@192.168.42.1`, порт `222`. Другие значения задаются `KEE_HOST` и `KEE_PORT`.

---

## Удаление

Одна команда — удаляет все пакеты и opkg-фид:

```sh
curl -fsSL https://raw.githubusercontent.com/0xkee/keenetic-entware-extras/master/scripts/install.sh | sh -s -- --uninstall
```

Или вручную:

```sh
# Удалить модули
opkg remove webui net-check smartdns-redirect smartdns-geo-conf geo-split geo-split-data

# Удалить базовый пакет (последним)
opkg remove keenetic-entware-extras

# Удалить репозиторий
sed -i '/kee/d' /opt/etc/opkg.conf
```

> ⚠️ Перед удалением базового пакета удалите все зависящие модули — без `lib/*.sh` они не смогут работать.
