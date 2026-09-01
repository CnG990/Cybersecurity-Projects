#!/usr/bin/env bash
# =============================================================================
# verify-dns.sh - prove that the filter is actually in effect.
#
#   ./verify-dns.sh                       # test the system resolver
#   ./verify-dns.sh --server 1.1.1.3      # test one resolver directly
#   ./verify-dns.sh --provider opendns    # know that provider's block-page IPs
#
# A domain counts as BLOCKED when the resolver returns nothing (NXDOMAIN /
# empty answer) or a sinkhole address (0.0.0.0, ::, a provider block page).
# Exit status: 0 = filter working, 1 = at least one adult domain resolved,
# 2 = a control domain broke (the resolver is unreachable or over-blocking).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=providers.sh
source "$SCRIPT_DIR/providers.sh"

PROVIDER="cloudflare"
SERVER=""

# Well-known adult domains, used purely as canaries for the filter.
ADULT_DOMAINS=(pornhub.com xvideos.com xnxx.com xhamster.com redtube.com)
# Ordinary sites that must keep working, so we can tell filtering from breakage.
CONTROL_DOMAINS=(example.com wikipedia.org github.com)

SINK_ALWAYS="0.0.0.0 :: 127.0.0.1 ::1"

usage() {
    cat <<USAGE
Usage: $0 [options]

Options:
  -p, --provider NAME   Provider whose block-page addresses to recognise
                        (default: cloudflare)
  -s, --server IP       Query this resolver directly instead of the system one
  -h, --help            Show this help
USAGE
}

green() { printf '\033[32m%s\033[0m' "$1"; }
# Keep the report readable: some CDNs answer with a dozen A records.
addrs_summary() {
    local n=${#ADDRS[@]}
    [[ $n -eq 0 ]] && { echo "(no answer)"; return; }
    if [[ $n -le 3 ]]; then echo "${ADDRS[*]}"; else echo "${ADDRS[*]:0:3} (+$((n - 3)) more)"; fi
}
red()   { printf '\033[31m%s\033[0m' "$1"; }

# resolve <domain> -> one address per line, empty output when unresolvable
resolve() {
    local domain="$1"
    if command -v dig >/dev/null 2>&1; then
        if [[ -n "$SERVER" ]]; then
            dig +short +time=3 +tries=1 "@$SERVER" A "$domain" 2>/dev/null | grep -E '^[0-9a-fA-F:.]+$' || true
        else
            dig +short +time=3 +tries=1 A "$domain" 2>/dev/null | grep -E '^[0-9a-fA-F:.]+$' || true
        fi
    elif command -v kdig >/dev/null 2>&1; then
        kdig +short ${SERVER:+@"$SERVER"} A "$domain" 2>/dev/null | grep -E '^[0-9a-fA-F:.]+$' || true
    elif [[ -z "$SERVER" ]] && command -v getent >/dev/null 2>&1; then
        getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u || true
    elif [[ -z "$SERVER" ]] && command -v python3 >/dev/null 2>&1; then
        python3 - "$domain" <<'PY' || true
import socket, sys
try:
    for info in socket.getaddrinfo(sys.argv[1], None):
        print(info[4][0])
except OSError:
    pass
PY
    else
        echo "RESOLVER_MISSING"
    fi
}

is_sinkholed() {
    local addr="$1" sink
    for sink in $SINK_ALWAYS $P_SINK; do
        [[ "$addr" == "$sink" ]] && return 0
    done
    return 1
}

# classify <domain> - sets VERDICT to blocked|allowed|error and ADDRS to the
# answers. Deliberately not a subshell: the caller needs both values.
classify() {
    local domain="$1" addr
    mapfile -t ADDRS < <(resolve "$domain" | sort -u)
    if [[ ${#ADDRS[@]} -eq 1 && "${ADDRS[0]}" == "RESOLVER_MISSING" ]]; then
        VERDICT=error; return
    fi
    if [[ ${#ADDRS[@]} -eq 0 ]]; then
        VERDICT=blocked; return          # NXDOMAIN / empty answer
    fi
    for addr in "${ADDRS[@]}"; do
        is_sinkholed "$addr" || { VERDICT=allowed; return; }
    done
    VERDICT=blocked
}

show_current_resolver() {
    echo "Current DNS configuration"
    echo "-------------------------"
    if [[ -n "$SERVER" ]]; then
        echo "  querying $SERVER directly"
    elif command -v resolvectl >/dev/null 2>&1 && resolvectl status >/dev/null 2>&1; then
        resolvectl status 2>/dev/null \
            | grep -E 'Current DNS Server|DNS Servers|DNSOverTLS|DNS Domain' \
            | sed 's/^ */  /' | sort -u
    fi
    if [[ -r /etc/resolv.conf ]]; then
        grep -E '^\s*nameserver' /etc/resolv.conf | sed 's/^/  \/etc\/resolv.conf: /'
    fi
    echo
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--provider) PROVIDER="${2:?}"; shift 2 ;;
        -s|--server)   SERVER="${2:?}";   shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

provider_load "$PROVIDER" || { echo "unknown provider '$PROVIDER'" >&2; exit 1; }

show_current_resolver
echo "Adult domains (expected: BLOCKED)"
echo "---------------------------------"
adult_leaks=0
for d in "${ADULT_DOMAINS[@]}"; do
    classify "$d"
    case "$VERDICT" in
        blocked) printf '  %-16s %s %s\n' "$d" "$(green 'BLOCKED')" "$(addrs_summary)" ;;
        allowed) printf '  %-16s %s %s\n' "$d" "$(red 'RESOLVED')" "$(addrs_summary)"; adult_leaks=$((adult_leaks + 1)) ;;
        error)   echo "  no DNS client available (install dnsutils/bind-utils)"; exit 2 ;;
    esac
done

echo
echo "Control domains (expected: RESOLVED)"
echo "------------------------------------"
control_breaks=0
for d in "${CONTROL_DOMAINS[@]}"; do
    classify "$d"
    case "$VERDICT" in
        allowed) printf '  %-16s %s %s\n' "$d" "$(green 'OK')" "$(addrs_summary)" ;;
        *)       printf '  %-16s %s %s\n' "$d" "$(red 'BROKEN')" "$(addrs_summary)"; control_breaks=$((control_breaks + 1)) ;;
    esac
done

echo
if [[ $control_breaks -gt 0 ]]; then
    echo "[x] $control_breaks control domain(s) failed: the resolver is unreachable or over-blocking."
    exit 2
fi
if [[ $adult_leaks -gt 0 ]]; then
    echo "[x] $adult_leaks adult domain(s) still resolve: the filter is not (yet) active on this path."
    echo "    Re-run 'sudo ./setup-dns.sh --provider $PROVIDER', then check the browser's own"
    echo "    DNS-over-HTTPS setting (see docs/BYPASS.md) - it silently bypasses the system resolver."
    exit 1
fi
echo "[+] filter is working: adult domains blocked, normal browsing intact."
