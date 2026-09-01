#!/usr/bin/env bash
# =============================================================================
# fetch-blocklist.sh - second layer: a local hosts-file blocklist.
#
# DNS filtering is the main control; this adds an on-device list for the case
# where the resolver cannot be changed (captive portal, corporate VPN pushing
# its own DNS, guest Wi-Fi). It downloads the StevenBlack "porn-only" hosts
# list and installs it between markers in /etc/hosts.
#
#   sudo ./fetch-blocklist.sh                 # install / refresh
#   sudo ./fetch-blocklist.sh --revert        # remove the block
#   ./fetch-blocklist.sh --output list.txt    # just download, change nothing
# =============================================================================
set -euo pipefail

LIST_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts"
HOSTS_FILE="/etc/hosts"
BEGIN_MARK="# >>> dns-family-filter blocklist >>>"
END_MARK="# <<< dns-family-filter blocklist <<<"
OUTPUT=""
REVERT=0
DRY_RUN=0

usage() {
    cat <<USAGE
Usage: sudo $0 [options]

Options:
  -u, --url URL      Blocklist URL in hosts format (default: StevenBlack porn-only)
  -o, --output FILE  Write the parsed list to FILE instead of editing $HOSTS_FILE
  -r, --revert       Remove the block from $HOSTS_FILE
  -n, --dry-run      Show what would happen
  -h, --help         Show this help
USAGE
}

log() { printf '[*] %s\n' "$*"; }
ok()  { printf '[+] %s\n' "$*"; }
die() { printf '[x] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--url)    LIST_URL="${2:?}"; shift 2 ;;
        -o|--output) OUTPUT="${2:?}"; shift 2 ;;
        -r|--revert) REVERT=1; shift ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

strip_block() {
    # Remove a previously installed block, keeping the rest of the file intact.
    sed "/^${BEGIN_MARK}$/,/^${END_MARK}$/d" "$HOSTS_FILE"
}

if [[ $REVERT -eq 1 ]]; then
    [[ $EUID -eq 0 || $DRY_RUN -eq 1 ]] || die "run as root"
    grep -qF "$BEGIN_MARK" "$HOSTS_FILE" || { log "no blocklist installed"; exit 0; }
    if [[ $DRY_RUN -eq 1 ]]; then
        log "would remove $(grep -c . <(strip_block)) -> cleaned $HOSTS_FILE"
    else
        tmp="$(mktemp)"; strip_block > "$tmp"; cat "$tmp" > "$HOSTS_FILE"; rm -f "$tmp"
        ok "blocklist removed from $HOSTS_FILE"
    fi
    exit 0
fi

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 60 "$LIST_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=60 "$LIST_URL"
    else
        die "curl or wget is required"
    fi
}

log "downloading $LIST_URL"
raw="$(fetch)" || die "download failed"

# Keep only "0.0.0.0 domain" entries, normalise them, drop duplicates.
entries="$(printf '%s\n' "$raw" \
    | tr -d '\r' \
    | awk '$1 == "0.0.0.0" && $2 != "0.0.0.0" { print "0.0.0.0 " tolower($2) }' \
    | sort -u)"
count="$(printf '%s\n' "$entries" | grep -c . || true)"
[[ "$count" -gt 0 ]] || die "the downloaded list contained no usable entries"
ok "$count domains parsed"

if [[ -n "$OUTPUT" ]]; then
    printf '%s\n' "$entries" > "$OUTPUT"
    ok "written to $OUTPUT"
    exit 0
fi

[[ $EUID -eq 0 || $DRY_RUN -eq 1 ]] || die "run as root to edit $HOSTS_FILE"

block="$BEGIN_MARK
# source: $LIST_URL
# generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ') - $count domains
$entries
$END_MARK"

if [[ $DRY_RUN -eq 1 ]]; then
    log "would add $count entries to $HOSTS_FILE (first 5):"
    printf '%s\n' "$entries" | head -5 | sed 's/^/      /'
    exit 0
fi

[[ -e "${HOSTS_FILE}.family-dns.bak" ]] || cp -a "$HOSTS_FILE" "${HOSTS_FILE}.family-dns.bak"
tmp="$(mktemp)"
{ strip_block; printf '%s\n' "$block"; } > "$tmp"
cat "$tmp" > "$HOSTS_FILE"
rm -f "$tmp"
ok "installed $count blocked domains into $HOSTS_FILE (backup: ${HOSTS_FILE}.family-dns.bak)"
log "refresh monthly, e.g. a systemd timer or: 0 4 1 * * $(readlink -f "$0")"
