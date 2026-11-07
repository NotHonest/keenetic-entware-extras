# geo-split-data

> 📖 **[Руководство пользователя](docs/user-manual.ru.md)**

Подсети GeoIP и списки доменов для [geo-split](../geo-split/).

## Состав

| Путь | Описание |
|------|-------------|
| `lists/domains.txt` | Подобранный список доменов (conffile — opkg не перезапишет) |
| `lists/ru-whitelist.txt` | Приоритетный список RU: 100+ доменов (госуслуги, банки, стриминг и т. д.) |
| `lists/geoip/*.zone.gz` | Готовые сжатые gzip подсети IP стран (232 зоны с [ipdeny.com](https://www.ipdeny.com)) |
| `scripts/fetch-zones.sh` | Загрузка и агрегация файлов зон (скрипт этапа сборки) |

## Установка

Нужен настроенный [репозиторий opkg](../releases/README.md).

```sh
opkg install geo-split-data
```

> **conffiles:** `lists/domains.txt` и `lists/ru-whitelist.txt` объявлены как conffiles —
> правки пользователя **не перезаписываются** при `opkg upgrade`.
> opkg оставит вашу версию и положит версию из пакета рядом, с суффиксом `.opkg-new`.

## Путь установки

```
/opt/keenetic-entware-extras/geo-split-data/
  lists/
    domains.txt
    ru-whitelist.txt
    geoip/
      ru.zone.gz       ← Россия (~13K CIDR)
      by.zone.gz       ← Беларусь
      kz.zone.gz       ← Казахстан
      cn.zone.gz       ← Китай
      us.zone.gz       ← США
      de.zone.gz       ← Германия
      ...              ← всего 232 зоны
```

## Файлы зон

Файлы зон забираются с ipdeny.com при сборке пакета (`scripts/fetch-zones.sh`).
CIDR агрегируются (слияние пересекающихся и соседних), чтобы сократить число маршрутов.
Файлы хранятся как `.zone.gz` (сжатие gzip) и экономят ~60–70% места во flash на роутерах.
geo-split прозрачно распаковывает их во время работы.

**В комплекте 232 файла зон** — все страны с зарегистрированными блоками IP-адресов.

По умолчанию geo-split использует `GEO_ZONE="eas"` (ЕАЭС: ru+by+kz+am+kg).
Другая зона задаётся параметром `GEO_ZONE` в `geo-split/config/config.conf`.

### Ручная загрузка

```sh
./geo-split-data/scripts/fetch-zones.sh          # пропустить, если свежие (<30 дней)
./geo-split-data/scripts/fetch-zones.sh --force   # скачать заново
```

Скрипт скачивает зоны, агрегирует CIDR и сжимает каждую через `gzip`.

### Сборка

Загрузка зон встроена в `scripts/build-ipk.sh`:

```sh
./scripts/build-ipk.sh geo-split-data   # если зоны устарели — скачивает, затем собирает .ipk
./scripts/build-ipk.sh all               # собирает все 3 пакета
```

## Сведения о пакете

- **Пакет:** `geo-split-data`
- **Depends:** `keenetic-entware-extras`
- **Архитектура:** all
