#!/opt/bin/sh
# flush-old-tunnel.sh — drop conntrack entries that still egress an old VPN.
# Only the tunnel named on the command line. Flows out of the ISP (eth3 and
# any other ifw) stay. Router-owned flows stay. Refuses to run while that
# tunnel is still the default route.
#
#   flush-old-tunnel.sh --dry nwg0
#   flush-old-tunnel.sh --apply nwg0
# shellcheck disable=SC3043
set -eu

MODE=""
DEV=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry) MODE=dry; shift ;;
    --apply) MODE=apply; shift ;;
    *)
      DEV="$1"
      shift
      ;;
  esac
done

case "$MODE" in
  dry|apply) ;;
  *)
    echo "usage: flush-old-tunnel.sh --dry|--apply DEV" >&2
    exit 2
    ;;
esac

case "$DEV" in
  nwg*|awg*|wg[0-9]*|ovpn*|tun[0-9]*|tap*|sstp*|l2tp*|pptp*|ipsec*|gre*|vti*) ;;
  *)
    echo "mode=$MODE dev=skipped reason=not_tunnel"
    exit 0
    ;;
esac

case "$DEV" in
  ""|*[!a-z0-9_]*)
    echo "mode=$MODE dev=skipped reason=bad_name"
    exit 0
    ;;
esac

if [ ! -d "/sys/class/net/$DEV" ]; then
  echo "mode=$MODE dev=$DEV delete=0 reason=absent"
  exit 0
fi

IDX="$(cat "/sys/class/net/$DEV/ifindex" 2>/dev/null || true)"
case "$IDX" in
  ""|*[!0-9]*)
    echo "mode=$MODE dev=$DEV delete=0 reason=no_index"
    exit 0
    ;;
esac

CUR="$(ip route show default 2>/dev/null | awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
if [ "$MODE" = "apply" ] && [ "$CUR" = "$DEV" ]; then
  echo "mode=apply dev=$DEV delete=0 reason=still_default"
  exit 0
fi

CT="/opt/sbin/conntrack"
if [ "$MODE" = "apply" ] && [ ! -x "$CT" ]; then
  echo "mode=apply dev=$DEV delete=0 reason=no_tool"
  exit 0
fi

BR_IDXS=""
for _br in /sys/class/net/br*; do
  [ -f "$_br/ifindex" ] || continue
  _i="$(cat "$_br/ifindex" 2>/dev/null || true)"
  case "$_i" in
    ""|*[!0-9]*) continue ;;
  esac
  BR_IDXS="$BR_IDXS $_i"
done

# awk prints: delete|keep proto src dst sport dport
# keep lines are ISP-shaped flows (ifl is a bridge, ifw is not this tunnel).
# They are counted and never passed to conntrack.
picked="$(awk -v want="$IDX" -v bridges="$BR_IDXS" '
function is_bridge(id,    n, i, b) {
  n = split(bridges, b, " ")
  for (i = 1; i <= n; i++) if (b[i] == id) return 1
  return 0
}
function octet(ip) {
  return ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/
}
$1 != "ipv4" { next }
{
  proto = ""; src = ""; dst = ""; sport = ""; dport = ""
  ifw = ""; ifl = ""
  for (i = 1; i <= NF; i++) {
    eq = index($i, "=")
    if (eq < 2) continue
    key = substr($i, 1, eq - 1)
    val = substr($i, eq + 1)
    if (key == "src" && src == "") src = val
    else if (key == "dst" && dst == "") dst = val
    else if (key == "sport" && sport == "") sport = val
    else if (key == "dport" && dport == "") dport = val
    else if (key == "ifw" && ifw == "") ifw = val
    else if (key == "ifl" && ifl == "") ifl = val
  }
  if (!is_bridge(ifl)) next
  if (proto == "") {
    if ($3 ~ /^(tcp|udp|sctp)$/) proto = $3
  }
  if (proto !~ /^(tcp|udp|sctp)$/) next
  if (!octet(src) || !octet(dst)) next
  if (sport !~ /^[0-9]+$/ || dport !~ /^[0-9]+$/) next
  if (ifw == want) print "delete", proto, src, dst, sport, dport
  else if (ifw != "" && ifw != "0") print "keep", proto, src, dst, sport, dport
}
' /proc/net/nf_conntrack)"

delete_n=0
keep_n=0
if [ -n "$picked" ]; then
  while read -r kind proto src dst sport dport; do
    [ -n "$kind" ] || continue
    if [ "$kind" = "keep" ]; then
      keep_n=$((keep_n + 1))
      continue
    fi
    [ "$kind" = "delete" ] || continue
    delete_n=$((delete_n + 1))
    if [ "$MODE" = "apply" ]; then
      "$CT" -D -s "$src" -d "$dst" -p "$proto" --sport "$sport" --dport "$dport" >/dev/null 2>&1 || true
    fi
  done <<EOF
$picked
EOF
fi

echo "mode=$MODE dev=$DEV delete=$delete_n keep_other=$keep_n"
