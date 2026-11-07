# Репозиторий opkg — keenetic-entware-extras

Готовые пакеты `.ipk` для роутеров Keenetic с Entware.

Пакеты собирает и публикует автор оригинала, [0xkee/keenetic-entware-extras](https://github.com/0xkee/keenetic-entware-extras). Файлы этого форка (экран сценария, `tunnel-check`, `ladder.sh`, `dns-tunnel-watch.sh`) в фид не входят. `opkg upgrade` заменяет их версией из фида. `config.conf` сохраняется.

## Каналы

| Канал | URL | Описание |
|---------|-----|-------------|
| **stable** | `https://0xkee.github.io/keenetic-entware-extras/stable` | Рекомендуется. Проверенные выпуски |
| **dev** | `https://0xkee.github.io/keenetic-entware-extras/dev` | Свежие сборки |

## Быстрое подключение

Добавьте канал **stable**:

```sh
cat >> /opt/etc/opkg.conf << 'EOF'
src/gz kee https://0xkee.github.io/keenetic-entware-extras/stable
src/gz aggr6 https://0xkee.github.io/aggregate6/stable
EOF
opkg update
```

## Смена канала

Со stable на dev:

```sh
sed -i 's|/stable$|/dev|' /opt/etc/opkg.conf
opkg update
```

С dev на stable:

```sh
sed -i 's|/dev$|/stable|' /opt/etc/opkg.conf
opkg update && opkg upgrade
```

## Пакеты

| Пакет | Описание |
|---------|-------------|
| `keenetic-entware-extras` | Общие библиотеки для всех пакетов |
| `geo-split` | Маршрутизация по географии (подсети и ip rule) |
| `geo-split-data` | Списки зон и данные GeoIP |
| `smartdns-geo-conf` | Настройка SmartDNS с разделением по зонам |
| `smartdns-redirect` | Перехват DNS через netfilter |
| `net-check` | Диагностика связности |
| `webui` | Веб-панель (nginx и Lua) |

У всех пакетов `Architecture: all`. Они подходят любому роутеру Keenetic, который поддерживает Entware (mipsel, mips, aarch64).

## Установка

```sh
# Общие библиотеки. Нужны остальным пакетам
opkg install keenetic-entware-extras

# Разделение маршрутов по географии
opkg install geo-split geo-split-data

# Настройка SmartDNS
opkg install smartdns-geo-conf smartdns-redirect

# Диагностика сети
opkg install net-check

# Веб-панель
opkg install webui
```

## Обновление

```sh
opkg update && opkg upgrade
```

## Удаление

```sh
# Снять пакеты по одному
opkg remove webui
opkg remove net-check
opkg remove smartdns-redirect smartdns-geo-conf
opkg remove geo-split geo-split-data

# Общие библиотеки — последними
opkg remove keenetic-entware-extras

# Убрать строки репозитория
sed -i '/^src\/gz kee /d; /^src\/gz aggr6 /d' /opt/etc/opkg.conf
opkg update
```
