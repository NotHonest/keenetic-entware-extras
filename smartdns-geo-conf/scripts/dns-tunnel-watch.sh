#!/opt/bin/sh
# dns-tunnel-watch.sh — if the international-DNS tunnel stays silent, regenerate
# those servers without -interface. Switch back after it answers again.
# Does not change Keenetic connection priority or geo-split routes.
# shellcheck disable=SC3043
# shellcheck disable=SC1091
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_CONFIG_DIR="${SCRIPT_DIR%/*}/config"
# shellcheck source=/dev/null
. "$_CONFIG_DIR/defaults.conf"
if [ -f "$_CONFIG_DIR/config.conf" ]; then
  # shellcheck source=/dev/null
  . "$_CONFIG_DIR/config.conf"
fi

CRON_LINE="*/1 * * * * root $SCRIPT_DIR/dns-tunnel-watch.sh >/dev/null 2>&1"
STAMP="/opt/var/run/smartdns-force-direct"
STATE="/opt/var/run/dns-tunnel-watch.state"
LOCK="/opt/var/run/dns-tunnel-watch.lock"

install_cron() {
  if [ ! -f /opt/etc/crontab ]; then
    return 0
  fi
  if grep -q 'dns-tunnel-watch.sh' /opt/etc/crontab 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$CRON_LINE" >> /opt/etc/crontab
}

if [ "${1:-}" = "install" ]; then
  install_cron
  exit 0
fi

if [ -z "${OTHER_DNS_INTERFACES:-}" ]; then
  exit 0
fi

DEV=""
for _cand in $OTHER_DNS_INTERFACES; do
  case "$_cand" in
    nwg*|awg*|wg[0-9]*|ovpn*|tun[0-9]*|tap*|sstp*|l2tp*|pptp*|ipsec*|gre*|vti*)
      DEV="$_cand"
      break
      ;;
  esac
done
if [ -z "$DEV" ]; then
  exit 0
fi

mkdir -p /opt/var/run
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

fail=0
ok=0
mode=tunnel
if [ -f "$STATE" ]; then
  # shellcheck source=/dev/null
  . "$STATE" || true
fi

reachable=0
if [ -d "/sys/class/net/$DEV" ]; then
  _out="$(/opt/bin/curl -4 -sS --interface "$DEV" --connect-timeout 4 -m 6 -o /dev/null -w '%{http_code}' http://1.1.1.1/cdn-cgi/trace 2>/dev/null || printf '%s' '000')"
  case "$_out" in
    2*|3*) reachable=1 ;;
  esac
fi

if [ "$reachable" = 1 ]; then
  fail=0
  ok=$((ok + 1))
else
  ok=0
  fail=$((fail + 1))
fi
if [ "$ok" -gt 5 ]; then ok=5; fi
if [ "$fail" -gt 5 ]; then fail=5; fi

need_restart=0
if [ "$fail" -ge 2 ] && [ ! -f "$STAMP" ]; then
  : > "$STAMP"
  mode=direct
  need_restart=1
fi
if [ "$ok" -ge 2 ] && [ -f "$STAMP" ]; then
  rm -f "$STAMP"
  mode=tunnel
  need_restart=1
fi

printf 'fail=%s\nok=%s\nmode=%s\n' "$fail" "$ok" "$mode" > "$STATE"

if [ "$need_restart" = 1 ]; then
  /opt/etc/init.d/S37smartdns-conf restart >/dev/null 2>&1 || true
fi
