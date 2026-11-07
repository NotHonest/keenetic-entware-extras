#!/opt/bin/sh
# dns-tunnel-watch.sh — keep international DNS on the VPN that is the
# current default route. One tunnel at a time, never a parallel direct server.
# If that tunnel stays silent, or the default route leaves the VPNs, regenerate
# without -interface. Does not change Keenetic priority, iptables, or geo-split.
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
IFACE_FILE="/opt/var/run/smartdns-dns-iface"
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

is_tunnel_dev() {
  case "$1" in
    nwg*|awg*|wg[0-9]*|ovpn*|tun[0-9]*|tap*|sstp*|l2tp*|pptp*|ipsec*|gre*|vti*)
      return 0
      ;;
  esac
  return 1
}

# Non-empty OTHER_DNS_INTERFACES with a tunnel name means "DNS via the VPN".
# The names are not a parallel list. The live default route picks the one.
FIRST=""
for _cand in ${OTHER_DNS_INTERFACES:-}; do
  if is_tunnel_dev "$_cand"; then
    FIRST="$_cand"
    break
  fi
done
if [ -z "$FIRST" ]; then
  exit 0
fi

default_route_dev() {
  ip route show default 2>/dev/null | awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
}

probe_dev() {
  _out="$(/opt/bin/curl -4 -sS --interface "$1" --connect-timeout 4 -m 6 -o /dev/null -w '%{http_code}' http://1.1.1.1/cdn-cgi/trace 2>/dev/null || printf '%s' '000')"
  case "$_out" in
    2*|3*) return 0 ;;
  esac
  return 1
}

# What SmartDNS is using now, from the generated file. The stamp and the
# iface file are inputs to the next generate, not proof that it already ran.
current_binding() {
  _b=""
  if [ -f "${CONF_SERVERS_OTHER:-}" ]; then
    _b="$(awk '
      {
        n = split($0, a, " ")
        for (i = 1; i <= n; i++) {
          if (a[i] == "-interface" && (i + 1) <= n) {
            print a[i + 1]
            exit
          }
        }
      }
    ' "$CONF_SERVERS_OTHER")"
  fi
  if is_tunnel_dev "${_b:-}"; then
    printf '%s\n' "$_b"
  else
    printf '%s\n' direct
  fi
}

FAILOVER_LOG="/opt/var/log/kee-failover.log"
LABEL_FILE="/tmp/kee-dns-labels.$$"
ADDR_FILE="/tmp/kee-dns-labels-addr.$$"

# Names for the short log only. Called when the route or DNS binding changes.
ensure_labels() {
  if [ -s "$LABEL_FILE" ]; then
    return 0
  fi
  ip -o -4 addr show > "$ADDR_FILE" 2>/dev/null || true
  ndmc -c "show interface" 2>/dev/null | awk -v addrfile="$ADDR_FILE" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function prefix_dev(id,   i, c, num, typ) {
  num = ""
  i = length(id)
  while (i > 0) {
    c = substr(id, i, 1)
    if (c < "0" || c > "9") break
    num = c num
    i--
  }
  if (num == "" || i < 1) return ""
  typ = substr(id, 1, i)
  if (typ == "Wireguard") return "nwg" num
  if (typ == "AmneziaWG") return "awg" num
  if (typ == "Bridge") return "br" num
  if (typ == "OpenVPN") return "ovpn_br" num
  if (typ == "UsbLte") return "lte_br" num
  if (typ == "UsbQmi") return "qmi_br" num
  if (typ == "PPPoE" || typ == "PPTP" || typ == "L2TP" || typ == "Ip6in4") return "ppp" num
  return ""
}
function flush() {
  dev = ""
  if (id == "" || global != "yes" || index(id, "/") > 0) { reset(); return }
  dev = prefix_dev(id)
  if (dev == "" && addr != "" && (addr in ipmap)) dev = ipmap[addr]
  if (dev == "" || dev ~ /[^a-z0-9_]/) { reset(); return }
  if (prio !~ /^[0-9]+$/) prio = "0"
  gsub(/[\t\r\n]/, " ", desc)
  if (length(desc) > 40) desc = substr(desc, 1, 40)
  if (desc == "") desc = dev
  printf "%s\t%s\t%s\n", dev, desc, prio
  reset()
}
function reset() {
  id = ""; desc = ""; global = ""; prio = ""; addr = ""
}
BEGIN {
  while ((getline line < addrfile) > 0) {
    split(line, f, " ")
    ip = f[4]
    sub(/\/.*/, "", ip)
    if (f[2] != "" && ip != "") ipmap[ip] = f[2]
  }
  close(addrfile)
  reset()
}
/^Interface, name = / { flush(); next }
{
  line = $0
  sub(/^[ \t]+/, "", line)
  p = index(line, ":")
  if (p < 2) next
  key = substr(line, 1, p - 1)
  val = trim(substr(line, p + 1))
  if (key == "id" && id == "") id = val
  else if (key == "description" && desc == "") desc = val
  else if (key == "global" && global == "") global = val
  else if (key == "priority" && prio == "") prio = val
  else if (key == "address" && addr == "" && val ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) addr = val
}
END { flush() }
' > "$LABEL_FILE" || true
  rm -f "$ADDR_FILE"
}

label_of() {
  if [ "$1" = "direct" ]; then
    printf '%s\n' "напрямую"
    return 0
  fi
  ensure_labels || true
  _n=""
  if [ -s "$LABEL_FILE" ]; then
    _n="$(awk -F '\t' -v d="$1" '$1 == d { print $2; exit }' "$LABEL_FILE")"
  fi
  if [ -n "$_n" ]; then
    printf '%s\n' "$_n"
  else
    printf '%s\n' "$1"
  fi
}

prio_of() {
  _p=""
  if [ -s "${LABEL_FILE:-}" ]; then
    _p="$(awk -F '\t' -v d="$1" '$1 == d { print $3; exit }' "$LABEL_FILE")"
  fi
  case "${_p:-}" in
    ''|*[!0-9]*) printf '%s\n' 0 ;;
    *) printf '%s\n' "$_p" ;;
  esac
}

append_event() {
  _line=$(printf '%.160s' "$1" | tr '\r\n\t' '   ')
  [ -n "$_line" ] || return 0
  mkdir -p /opt/var/log
  printf '%s\n' "$_line" >> "$FAILOVER_LOG"
  tail -n 10 "$FAILOVER_LOG" > "${FAILOVER_LOG}.tmp"
  mv "${FAILOVER_LOG}.tmp" "$FAILOVER_LOG"
}

if [ "${1:-}" = "labels" ]; then
  ensure_labels || true
  if [ -s "$LABEL_FILE" ]; then
    cat "$LABEL_FILE"
  fi
  rm -f "$LABEL_FILE" "$ADDR_FILE"
  exit 0
fi

mkdir -p /opt/var/run
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true; rm -f "$LABEL_FILE" "$ADDR_FILE" "${FAILOVER_LOG}.tmp"' EXIT

fail=0
ok=0
isp=0
mode=tunnel
prev_def=""
if [ -f "$STATE" ]; then
  # shellcheck source=/dev/null
  . "$STATE" || true
fi
case "${fail:-}" in ''|*[!0-9]*) fail=0 ;; esac
case "${ok:-}" in ''|*[!0-9]*) ok=0 ;; esac
case "${isp:-}" in ''|*[!0-9]*) isp=0 ;; esac
case "${prev_def:-}" in ''|*[!a-z0-9_]*) prev_def="" ;; esac

DEF="$(default_route_dev)"
case "$DEF" in
  ""|*[!a-z0-9_]*) DEF=""; DEF_OK=0 ;;
  *) DEF_OK=1 ;;
esac
bound="$(current_binding)"
want="$bound"
apply=0

if is_tunnel_dev "$DEF"; then
  isp=0
  if [ -d "/sys/class/net/$DEF" ] && probe_dev "$DEF"; then
    fail=0
    ok=$((ok + 1))
    [ "$ok" -gt 5 ] && ok=5
    want="$DEF"
    # The route already moved. One answer on the new tunnel is enough.
    [ "$want" != "$bound" ] && apply=1
  else
    ok=0
    fail=$((fail + 1))
    [ "$fail" -gt 5 ] && fail=5
    if [ "$fail" -ge 2 ]; then
      want=direct
      [ "$bound" != direct ] && apply=1
    fi
  fi
else
  ok=0
  fail=0
  want=direct
  if [ "$bound" != direct ]; then
    isp=$((isp + 1))
    [ "$isp" -gt 5 ] && isp=5
    # Two looks, so one odd route read does not restart SmartDNS.
    [ "$isp" -ge 2 ] && apply=1
  else
    isp=0
  fi
fi

if [ "$apply" = 1 ]; then
  if [ "$want" = direct ]; then
    : > "$STAMP"
    rm -f "$IFACE_FILE"
    mode=direct
  else
    rm -f "$STAMP"
    printf '%s\n' "$want" > "$IFACE_FILE"
    mode="$want"
  fi
  /opt/etc/init.d/S37smartdns-conf restart >/dev/null 2>&1 || true
else
  if [ "$want" = direct ]; then
    mode=direct
  else
    mode="$want"
  fi
fi

case "$mode" in
  direct) ;;
  ""|*[!a-z0-9_]*) mode=direct ;;
esac

# One line when the default route or the DNS binding changes. The first
# observation only remembers the route, so a reboot does not look like a drop.
route_changed=0
if [ "$DEF_OK" = 1 ] && [ -n "$prev_def" ] && [ "$prev_def" != "$DEF" ]; then
  route_changed=1
fi
if [ "$route_changed" = 1 ] || [ "$apply" = 1 ]; then
  old_name="$(label_of "$prev_def")"
  new_name="$(label_of "$DEF")"
  want_name="$(label_of "$want")"
  old_prio="$(prio_of "$prev_def")"
  new_prio="$(prio_of "$DEF")"
  if [ "$apply" = 1 ]; then
    if [ "$want" = "direct" ]; then
      dns_bit=", DNS ушёл напрямую"
    elif [ "$want" = "$DEF" ]; then
      dns_bit=", DNS ушёл следом"
    else
      dns_bit=", DNS перешёл на ${want_name}"
    fi
  elif [ "$bound" = "direct" ]; then
    dns_bit=". DNS пока напрямую"
  elif [ "$bound" = "$DEF" ]; then
    dns_bit=". DNS уже на нём"
  elif [ -n "$prev_def" ] && [ "$bound" = "$prev_def" ]; then
    dns_bit=". DNS пока на ${old_name}"
  else
    dns_bit=". DNS пока без изменений"
  fi
  when="$(date '+%d.%m %H:%M')"
  if [ "$route_changed" = 1 ]; then
    if is_tunnel_dev "$prev_def" && [ "$old_prio" -gt 0 ] && [ "$new_prio" -gt 0 ] && [ "$new_prio" -lt "$old_prio" ]; then
      event="${when} ${old_name} замолчал, основным стал ${new_name}${dns_bit}"
    elif is_tunnel_dev "$DEF" && [ "$old_prio" -gt 0 ] && [ "$new_prio" -gt 0 ] && [ "$new_prio" -gt "$old_prio" ]; then
      event="${when} ${new_name} снова основной${dns_bit}"
    else
      event="${when} Основным стал ${new_name} вместо ${old_name}${dns_bit}"
    fi
  elif [ "$want" = "direct" ]; then
    event="${when} Зарубежный DNS ушёл напрямую"
  else
    event="${when} Зарубежный DNS перешёл на ${want_name}"
  fi
  append_event "$event"
fi

# Open TCP stays on the tunnel that was the default. Drop only those
# conntrack rows. ISP flows and the router's own flows are not in that set.
# The helper also refuses while the old device is still the default route.
if [ "$route_changed" = 1 ] && is_tunnel_dev "$prev_def"; then
  _flush="$(/opt/keenetic-entware-extras/geo-split/scripts/flush-old-tunnel.sh --apply "$prev_def" 2>/dev/null || true)"
  _del="$(printf '%s\n' "$_flush" | awk '
    {
      for (i = 1; i <= NF; i++) if ($i ~ /^delete=/) {
        split($i, a, "=")
        print a[2]
        exit
      }
    }
  ')"
  case "${_del:-}" in
    ""|*[!0-9]*) _del=0 ;;
  esac
  if [ "$_del" -gt 0 ]; then
    append_event "${when} Закрыл ${_del} соединений, которые ещё шли через ${old_name}"
  fi
fi

if [ "$DEF_OK" = 1 ]; then
  prev_def="$DEF"
fi
case "$prev_def" in
  ""|*[!a-z0-9_]*) prev_def="" ;;
esac
printf 'fail=%s\nok=%s\nisp=%s\nmode=%s\nprev_def=%s\n' "$fail" "$ok" "$isp" "$mode" "$prev_def" > "$STATE"
