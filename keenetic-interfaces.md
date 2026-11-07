# Справка по сетевым интерфейсам Keenetic

Справка для разработки: префиксы сетевых интерфейсов на роутерах Keenetic (KeeneticOS 5.0+).
Используется в чёрном списке [`api-system.lua`](webui/lua/api-system.lua) и в определении туннеля [`lib/ip.sh`](lib/ip.sh).

## Таблица интерфейсов

| Префикс | Описание | Тип | Показ в UI | Пример |
|--------|-------------|------|:----------:|---------|
| `br0`, `br1` | Мост LAN / гостевой сети | user | ✅ | `br0` (домашняя сеть) |
| `eth[0-9]` | Физический Ethernet (IPoE WAN) | user | ⚠️ подпись | `eth3` → провайдер |
| `ppp[0-9]`, `pppoe[0-9]` | PPPoE WAN | user | ✅ | `ppp0` |
| `lte_br*` | USB-модем 3G/4G | user | ✅ | `lte_br0` |
| `nwg*` | WireGuard под управлением NDM | tunnel | ✅ | `nwg0` |
| `awg*` | AmneziaWG | tunnel | ✅ | `awg0` |
| `wg*` | WireGuard, заведённый вручную | tunnel | ✅ | `wg0` |
| `ovpn*` | OpenVPN | tunnel | ✅ | `ovpn0` |
| `l2tp*` | L2TP VPN | tunnel | ✅ | `l2tp0` |
| `pptp*` | PPTP VPN | tunnel | ✅ | `pptp0` |
| `sstp*` | SSTP VPN | tunnel | ✅ | `sstp0` |
| `ipsec*` | Туннель IPsec | tunnel | ✅ | `ipsec0` |
| `tun[0-9]*` | Обычное устройство TUN | tunnel | ✅ | `tun0` |
| `tap*` | Обычное устройство TAP | tunnel | ✅ | `tap0` |
| `wwan*` | Клиент Wi-Fi (WISP) | user | ⚠️ подпись | `wwan0` |
| `usb*` | Раздача с USB | user | ⚠️ подпись | `usb0` |
| `lo` | Петля | infra | ❌ | `lo` |
| `ra[0-9]` | Радио Wi-Fi 2,4 ГГц (MediaTek) | infra | ❌ | `ra0` |
| `rai[0-9]` | Радио Wi-Fi 5 ГГц (MediaTek) | infra | ❌ | `rai0` |
| `rax[0-9]` | Радио Wi-Fi 6 ГГц (Wi-Fi 6E) | infra | ❌ | `rax0` |
| `apcli*` | Клиентский мост Wi-Fi (WISP) | user | ⚠️ подпись | `apcli0` |
| `xfrm*`, `xfrms*` | Интерфейсы состояния IPsec xfrm | infra | ❌ | `xfrms1` |
| `tunl*` | Устройство туннеля IPv4 | infra | ❌ | `tunl0` |
| `ip6tnl*` | Устройство туннеля IPv6 | infra | ❌ | `ip6tnl0` |
| `sit*` | IPv6 внутри IPv4 (SIT) | infra | ❌ | `sit0` |
| `gre*` | Туннель GRE | infra | ❌ | `gre0` |
| `vti*` | Интерфейс VPN-туннеля | tunnel | ✅ | `vti0` |
| `ethoip*` | EtherIP | infra | ❌ | `ethoip0` |
| `dummy*` | Фиктивное устройство | infra | ❌ | `dummy0` |
| `ezcfg*` | EZConfig | infra | ❌ | `ezcfg0` |
| `ifb*` | IFB (формирование трафика) | infra | ❌ | `ifb0` |
| `*.N` | Подынтерфейс VLAN | infra | ❌ | `eth2.1` |

**Обозначения:**
- **Тип:** `user` — WAN или LAN, с которым работает человек; `tunnel` — VPN или туннель; `infra` — ядро или радио
- **Показ в UI:** ✅ — всегда; ⚠️ подпись — только если NDM дал имя; ❌ — в чёрном списке

Тот же набор префиксов туннеля используют проверка `tunnel-check.sh` и сторож `dns-tunnel-watch.sh`: `nwg*`, `awg*`, `wg` с цифрой, `ovpn*`, `tun` с цифрой, `tap*`, `sstp*`, `l2tp*`, `pptp*`, `ipsec*`, `gre*`, `vti*`.

## Где это используется

| Компонент | Файл | Зачем |
|-----------|------|---------|
| Чёрный список интерфейсов | `webui/lua/api-system.lua` → `M.interfaces()` | Не отдаёт служебные интерфейсы в API |
| Определение туннеля | `lib/ip.sh` → `is_tunnel_iface()` | Отличает туннель для route-check и wan-paths |
| Проверка туннеля в UI | `webui/static/shared.js` → `EW.isTunnelIface()` | Та же классификация на схеме маршрута |
| Списки в конфиге | `webui/static/config-editor.js` | Поле типа `iface_select` заполняется из API |
