#!/opt/bin/sh
# tunnel-check.sh — probe whether the default route (or a named iface) passes traffic.
# Read-only. Does not change routes, firewall, or Keenetic connection priority.
# shellcheck disable=SC3043
set -eu

JSON=0
DEV=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    *) DEV="$1"; shift ;;
  esac
done

if [ -z "$DEV" ]; then
  DEV="$(ip route show default 2>/dev/null | awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
fi

case "$DEV" in
  ""|*[!a-z0-9_]*)
    echo '{"ok":false,"error":"no_device"}'
    exit 0
    ;;
esac

is_tun=false
case "$DEV" in
  nwg*|awg*|wg[0-9]*|ovpn*|tun[0-9]*|tap*|sstp*|l2tp*|pptp*|ipsec*|gre*|vti*)
    is_tun=true
    ;;
esac

up=false
if [ -d "/sys/class/net/$DEV" ]; then
  up=true
fi

code=0
ms=0
reachable=false
if [ "$is_tun" = true ] && [ "$up" = true ]; then
  _out="$(/opt/bin/curl -4 -sS --interface "$DEV" --connect-timeout 4 -m 6 -o /dev/null -w '%{http_code} %{time_total}' http://1.1.1.1/cdn-cgi/trace 2>/dev/null || printf '%s' '000 0')"
  code="$(printf '%s' "$_out" | awk '{ print $1 }')"
  ms="$(printf '%s' "$_out" | awk '{ printf "%d", $2 * 1000 }')"
  case "$code" in
    ''|*[!0-9]*) code=0 ;;
  esac
  case "$code" in
    2*|3*) reachable=true ;;
  esac
fi

dns_direct=false
if [ -f /opt/var/run/smartdns-force-direct ]; then
  dns_direct=true
fi

if [ "$JSON" = 1 ]; then
  printf '{"ok":true,"dev":"%s","tunnel":%s,"up":%s,"reachable":%s,"http_code":%s,"ms":%s,"dns_direct":%s}\n' \
    "$DEV" "$is_tun" "$up" "$reachable" "$code" "${ms:-0}" "$dns_direct"
fi
