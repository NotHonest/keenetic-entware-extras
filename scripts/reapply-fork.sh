#!/bin/sh
# reapply-fork.sh — put this fork back after opkg upgrade.
# Run it on the computer that has the git checkout, not on the router.
# The 0xkee feed replaces scripts, Lua and the panel. This copies those
# files from the checkout again. config.conf and defaults.conf stay put.
# If /opt/sbin/conntrack is missing, the Entware conntrack package is
# installed. conntrackd is not. A failed install is reported after the
# panel and SmartDNS have been restarted.
#
#   KEE_PASS_FILE=/path/to/password-file ./scripts/reapply-fork.sh
#   KEE_PASS_FILE=/path/to/password-file ./scripts/reapply-fork.sh --dry-run
#
# The password file is one line, the root shell password. It is not printed.
# KEE_HOST defaults to root@192.168.42.1 and KEE_PORT to 222.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY=1
elif [ -n "${1:-}" ]; then
  echo "Unknown argument: $1" >&2
  echo "Usage: KEE_PASS_FILE=... ./scripts/reapply-fork.sh [--dry-run]" >&2
  exit 2
fi

PASS_FILE="${KEE_PASS_FILE:-}"
HOST="${KEE_HOST:-root@192.168.42.1}"
PORT="${KEE_PORT:-222}"

if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git checkout: $ROOT" >&2
  exit 1
fi
if ! git -C "$ROOT" rev-parse --verify upstream/master >/dev/null 2>&1; then
  echo "upstream/master is missing. Fetch the 0xkee remote first." >&2
  exit 1
fi

list_files() {
  {
    git -C "$ROOT" diff --name-only --diff-filter=ACMRTUXB upstream/master -- .
    if [ -f "$ROOT/geo-split/scripts/ladder.sh" ]; then
      printf '%s\n' "geo-split/scripts/ladder.sh"
    fi
    if [ -f "$ROOT/geo-split/scripts/flush-old-tunnel.sh" ]; then
      printf '%s\n' "geo-split/scripts/flush-old-tunnel.sh"
    fi
  } | awk 'NF && !seen[$0]++' | while IFS= read -r rel; do
    case "$rel" in
      *config.conf|*defaults.conf|*..*) continue ;;
    esac
    if [ -f "$ROOT/$rel" ]; then
      printf '%s\n' "$rel"
    fi
  done
}

FILES="$(list_files)"
if [ -z "$FILES" ]; then
  echo "Nothing to copy." >&2
  exit 1
fi

bad="$(printf '%s\n' "$FILES" | awk '/config\.conf$/ || /defaults\.conf$/ { print }')"
if [ -n "$bad" ]; then
  echo "Refusing to upload conffiles:" >&2
  printf '%s\n' "$bad" >&2
  exit 1
fi

echo "Files:"
printf '%s\n' "$FILES"

if [ "$DRY" = 1 ]; then
  echo "Dry run. Nothing was uploaded."
  exit 0
fi

if [ -z "$PASS_FILE" ] || [ ! -f "$PASS_FILE" ]; then
  echo "Set KEE_PASS_FILE to a file that contains the router root password." >&2
  exit 1
fi
if ! command -v sshpass >/dev/null 2>&1; then
  echo "sshpass is not installed." >&2
  exit 1
fi

kee_ssh() {
  sshpass -f "$PASS_FILE" ssh \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o StrictHostKeyChecking=accept-new \
    -p "$PORT" \
    "$HOST" "$@"
}

conf_sums() {
  kee_ssh 'find /opt/keenetic-entware-extras -type f \( -name config.conf -o -name defaults.conf \) | sort | while IFS= read -r f; do md5sum "$f"; done'
}

echo "Reading config checksums."
before="$(conf_sums)"

stage="$(mktemp -d "${TMPDIR:-/tmp}/kee-reapply.XXXXXX")"
trap 'rm -rf "$stage"' EXIT INT TERM

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  mkdir -p "$stage/$(dirname "$rel")"
  cp "$ROOT/$rel" "$stage/$rel"
  case "$rel" in
    webui/static/*.js|webui/static/*.css|webui/static/*.html)
      gzip -c -n -9 "$stage/$rel" > "$stage/$rel.gz"
      ;;
  esac
done <<EOF
$FILES
EOF

payload="$stage/payload.list"
{
  printf '%s\n' "$FILES"
  find "$stage/webui/static" -type f -name '*.gz' 2>/dev/null | sed "s|^$stage/||"
} | awk 'NF && !seen[$0]++' > "$payload"

echo "Uploading."
tar czf - -C "$stage" . | kee_ssh 'tar xzf - -C /opt/keenetic-entware-extras'

apply="$stage/apply.sh"
{
  echo "set -eu"
  echo "cd /opt/keenetic-entware-extras"
  echo "while IFS= read -r rel; do"
  echo "  [ -n \"\$rel\" ] || continue"
  echo "  [ -f \"\$rel\" ] || continue"
  echo "  chown root:root \"\$rel\""
  echo "  case \"\$rel\" in"
  echo "    *.sh|*/init.d/*) chmod 755 \"\$rel\" ;;"
  echo "    *) chmod 644 \"\$rel\" ;;"
  echo "  esac"
  echo "done <<'LIST'"
  cat "$payload"
  echo "LIST"
  echo "src=/opt/keenetic-entware-extras/smartdns-geo-conf/init.d/S37smartdns-conf"
  echo "dst=/opt/etc/init.d/S37smartdns-conf"
  echo "if [ -f \"\$src\" ] && [ -e \"\$dst\" ] && [ ! -L \"\$dst\" ]; then"
  echo "  cp \"\$src\" \"\$dst\""
  echo "  chown root:root \"\$dst\""
  echo "  chmod 755 \"\$dst\""
  echo "  echo S37_FILE"
  echo "elif [ -L \"\$dst\" ]; then"
  echo "  echo S37_LINK"
  echo "else"
  echo "  echo S37_ABSENT"
  echo "fi"
} > "$apply"

kee_ssh 'sh -s' < "$apply"

after="$(conf_sums)"
if [ "$before" != "$after" ]; then
  echo "config.conf or defaults.conf changed. Services were not restarted." >&2
  printf '%s\n' "$before" > "$stage/before.txt"
  printf '%s\n' "$after" > "$stage/after.txt"
  diff -u "$stage/before.txt" "$stage/after.txt" >&2 || true
  exit 1
fi
echo "config.conf and defaults.conf are unchanged."

conntrack_rc=0
if kee_ssh 'test -x /opt/sbin/conntrack'; then
  echo "conntrack already installed."
else
  echo "Installing conntrack."
  if ! kee_ssh 'opkg update && opkg install conntrack'; then
    echo "conntrack was not installed. Old tunnel flows will not be closed until it is." >&2
    conntrack_rc=1
  fi
fi

echo "Restarting the panel and SmartDNS."
kee_ssh '/opt/etc/init.d/S80nginx-webui restart; /opt/etc/init.d/S37smartdns-conf restart'
if [ "$conntrack_rc" != 0 ]; then
  exit 1
fi
echo "Done. geo-split was not restarted."
