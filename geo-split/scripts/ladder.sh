#!/opt/bin/sh
# ladder.sh — read the Keenetic connection ladder.
# Read-only. No curl, no route changes, no ping-check changes.
# Global connections only: VPN tunnels and the ISP. Bridges are not a step.
# shellcheck disable=SC3043
set -eu

json_escape_val() {
  printf '%s' "$1" | awk '
    BEGIN { ORS="" }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\t/, "\\t")
      if (NR > 1) printf "\\n"
      printf "%s", $0
    }
  '
}

json_kv() {
  printf '"%s":"%s"' "$1" "$(json_escape_val "$2")"
}

json_kv_num() {
  printf '"%s":%s' "$1" "${2:-0}"
}

json_kv_bool() {
  if [ "${2:-1}" = "0" ]; then
    printf '"%s":true' "$1"
  else
    printf '"%s":false' "$1"
  fi
}

emit_error() {
  printf '{"ok":false,"error":"%s"}\n' "$1"
  exit 0
}

ADDR_FILE="/tmp/kee-ladder-addr.$$"
PING_FILE="/tmp/kee-ladder-ping.$$"
STEP_FILE="/tmp/kee-ladder-steps.$$"
cleanup() {
  rm -f "$ADDR_FILE" "$PING_FILE" "$STEP_FILE"
}
trap cleanup EXIT INT TERM

ip -o -4 addr show > "$ADDR_FILE" 2>/dev/null || true

ndmc -c "show ping-check" 2>/dev/null | awk '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function flush() {
  if (prof == "" || ndm == "") return
  if (status != "pass" && status != "fail") status = "none"
  printf "%s\t%s\t%s\n", ndm, status, prof
}
BEGIN { prof = ""; ndm = ""; status = "" }
{
  line = $0
  sub(/^[ \t]+/, "", line)
  p = index(line, ":")
  if (p < 2) next
  key = substr(line, 1, p - 1)
  val = trim(substr(line, p + 1))
  if (key == "profile") {
    flush()
    prof = val
    ndm = ""
    status = ""
  } else if (key == "name" && ndm == "") {
    ndm = val
  } else if (key == "status" && status == "") {
    status = val
  }
}
END { flush() }
' > "$PING_FILE" || true

if ! ndmc -c "show interface" 2>/dev/null | awk -v addrfile="$ADDR_FILE" -v pingfile="$PING_FILE" '
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
  if (typ == "WifiStation") return "wwan" num
  return ""
}
function is_tunnel(dev) {
  return dev ~ /^(nwg|awg|wg|ovpn|l2tp|pptp|sstp|ipsec|tun[0-9]|tap|gre|vti|sit|ip6tnl|xfrm)/
}
function flush() {
  dev = ""
  if (id == "" || global != "yes" || index(id, "/") > 0) {
    reset()
    return
  }
  dev = prefix_dev(id)
  if (dev == "" && addr != "" && (addr in ipmap)) dev = ipmap[addr]
  if (dev == "" && iname ~ /^[a-z0-9_]+$/ && (iname in exists)) dev = iname
  if (dev == "" || length(dev) > 15 || dev ~ /[^a-z0-9_]/) {
    reset()
    return
  }
  if (dev == "lo" || dev ~ /^br[0-9]+$/) {
    reset()
    return
  }
  if (dev in seen) {
    reset()
    return
  }
  seen[dev] = 1
  if (prio !~ /^[0-9]+$/) prio = "0"
  kind = is_tunnel(dev) ? "vpn" : "isp"
  check = (id in checks) ? checks[id] : "none"
  if (check != "pass" && check != "fail") check = "none"
  if (link != "up" && link != "down") link = "down"
  if (conn != "yes") conn = "no"
  if (gw != "yes") gw = "no"
  gsub(/\t/, " ", desc)
  if (desc == "") desc = id
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", prio, dev, id, desc, kind, link, conn, check, gw
  reset()
}
function reset(   _i) {
  id = ""; iname = ""; type = ""; desc = ""; link = ""; conn = ""
  global = ""; gw = ""; prio = ""; addr = ""; gw_ind = 999
}
BEGIN {
  while ((getline line < addrfile) > 0) {
    split(line, f, " ")
    ip = f[4]
    sub(/\/.*/, "", ip)
    if (f[2] != "" && ip != "") ipmap[ip] = f[2]
  }
  close(addrfile)
  while ((getline line < "/proc/net/dev") > 0) {
    split(line, f, ":")
    name = f[1]
    gsub(/ /, "", name)
    if (name != "") exists[name] = 1
  }
  while ((getline line < pingfile) > 0) {
    n = split(line, a, "\t")
    if (n < 2 || a[1] == "") continue
    if (a[3] == "default" && (a[1] in checks)) continue
    checks[a[1]] = a[2]
  }
  close(pingfile)
  reset()
}
/^Interface, name = / { flush(); next }
{
  indent = match($0, /^[ ]*/) ? RLENGTH : 0
  line = $0
  sub(/^[ \t]+/, "", line)
  p = index(line, ":")
  if (p < 2) next
  key = substr(line, 1, p - 1)
  val = trim(substr(line, p + 1))
  if (key == "id" && id == "") id = val
  else if (key == "interface-name" && iname == "") iname = val
  else if (key == "type" && type == "") type = val
  else if (key == "description" && desc == "") desc = val
  else if (key == "link" && link == "") link = val
  else if (key == "connected" && conn == "") conn = val
  else if (key == "global" && global == "") global = val
  else if (key == "priority" && prio == "") prio = val
  else if (key == "defaultgw" && indent < gw_ind) { gw = val; gw_ind = indent }
  else if (key == "address" && addr == "" && val ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) addr = val
}
END { flush() }
' > "$STEP_FILE"; then
  emit_error "ndmc"
fi

DEFAULT_DEV="$(ip route show default 2>/dev/null | awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
case "$DEFAULT_DEV" in
  ""|*[!a-z0-9_]*) DEFAULT_DEV="" ;;
esac

TAB="$(printf '\t')"
steps=""
if [ -s "$STEP_FILE" ]; then
  # BusyBox sort ignores -k1,1n. The line starts with the priority, so -nr is enough.
  sorted="$(sort -nr "$STEP_FILE")"
  while IFS="$TAB" read -r prio dev ndm name kind link conn check gw; do
    [ -n "$dev" ] || continue
    role="backup"
    if [ -n "$DEFAULT_DEV" ] && [ "$dev" = "$DEFAULT_DEV" ]; then
      role="primary"
    elif [ "$link" != "up" ] || [ "$conn" != "yes" ] || [ "$check" = "fail" ]; then
      role="down"
    elif [ "$kind" = "isp" ]; then
      role="isp"
    fi
    gw_true=1
    [ "$gw" = "yes" ] && gw_true=0
    case "$prio" in
      ''|*[!0-9]*) prio=0 ;;
    esac
    entry="$(printf '{%s,%s,%s,%s,%s,%s,%s,%s}' \
      "$(json_kv dev "$dev")" \
      "$(json_kv name "$name")" \
      "$(json_kv_num priority "$prio")" \
      "$(json_kv kind "$kind")" \
      "$(json_kv role "$role")" \
      "$(json_kv link "$link")" \
      "$(json_kv check "$check")" \
      "$(json_kv_bool defaultgw "$gw_true")")"
    steps="${steps:+$steps,}$entry"
  done <<EOF
$sorted
EOF
fi

events=""
LOG="/opt/var/log/kee-failover.log"
if [ -f "$LOG" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line="$(printf '%.180s' "$line")"
    item="$(printf '"%s"' "$(json_escape_val "$line")")"
    if [ -z "$events" ]; then
      events="$item"
    else
      events="${item},${events}"
    fi
  done <<EOF
$(tail -n 10 "$LOG" 2>/dev/null || true)
EOF
fi

# What SmartDNS is using now. The generated -interface line is the applied
# binding. The force-direct stamp only asks the next generate to drop it,
# so a stamp next to a remaining -interface is still the old tunnel.
DNS_CONF="/opt/etc/smartdns/dns-servers-other.conf"
DNS_STAMP="/opt/var/run/smartdns-force-direct"
dns_mode="unknown"
dns_dev=""
if [ -f "$DNS_CONF" ]; then
  dns_raw="$(awk '
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^#/) next
      n = split(line, a, " ")
      for (i = 1; i <= n; i++) {
        if (a[i] == "-interface" && (i + 1) <= n) {
          print a[i + 1]
          exit
        }
      }
    }
  ' "$DNS_CONF" 2>/dev/null || true)"
  case "$dns_raw" in
    ""|*[!a-z0-9_]*) dns_raw="" ;;
  esac
  if [ "${#dns_raw}" -gt 15 ]; then
    dns_raw=""
  fi
  case "$dns_raw" in
    nwg*|awg*|wg[0-9]*|ovpn*|tun[0-9]*|tap*|sstp*|l2tp*|pptp*|ipsec*|gre*|vti*)
      dns_dev="$dns_raw"
      dns_mode="tunnel"
      ;;
    *)
      dns_mode="direct"
      ;;
  esac
fi
dns_pending="false"
if [ -f "$DNS_STAMP" ] && [ "$dns_mode" = "tunnel" ]; then
  dns_pending="true"
fi
dns_json="$(printf '%s,%s,"pending":%s' \
  "$(json_kv dev "$dns_dev")" \
  "$(json_kv mode "$dns_mode")" \
  "$dns_pending")"

printf '{"ok":true,"default_dev":"%s","steps":[%s],"events":[%s],"dns":{%s}}\n' \
  "$DEFAULT_DEV" "$steps" "$events" "$dns_json"
