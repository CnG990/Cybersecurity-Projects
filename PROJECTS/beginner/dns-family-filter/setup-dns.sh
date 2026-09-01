#!/usr/bin/env bash
# =============================================================================
# setup-dns.sh - point a Linux host at a family-filtering DNS resolver so that
# adult websites stop resolving.
#
#   sudo ./setup-dns.sh                          # Cloudflare for Families
#   sudo ./setup-dns.sh --provider cleanbrowsing # another provider
#   sudo ./setup-dns.sh --revert                 # undo everything
#
# The script picks the backend that actually owns /etc/resolv.conf on this
# machine (systemd-resolved, NetworkManager, or the plain file) and writes a
# clearly marked drop-in so the change can always be reverted.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=providers.sh
source "$SCRIPT_DIR/providers.sh"

PROVIDER="cloudflare"
BACKEND="auto"
REVERT=0
DRY_RUN=0
IMMUTABLE=0

RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/99-family-dns.conf"
NM_DROPIN="/etc/NetworkManager/conf.d/99-family-dns.conf"
RESOLV_CONF="/etc/resolv.conf"
RESOLV_BACKUP="/etc/resolv.conf.family-dns.bak"

usage() {
    cat <<USAGE
Usage: sudo $0 [options]

Options:
  -p, --provider NAME   Filtering resolver to use (default: cloudflare)
  -b, --backend NAME    auto | resolved | networkmanager | resolvconf
  -i, --immutable       chattr +i /etc/resolv.conf (resolvconf backend only)
  -r, --revert          Restore the previous DNS configuration
  -n, --dry-run         Print what would change without touching the system
  -h, --help            Show this help

Providers:
$(provider_list)
USAGE
}

log()  { printf '[*] %s\n' "$*"; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '    would run: %s\n' "$*"
    else
        "$@"
    fi
}

write_file() {
    # write_file <path>, content on stdin
    local path="$1" content
    content="$(cat)"
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '    would write %s:\n' "$path"
        # shellcheck disable=SC2001  # prefixing every line, not a simple substitution
        sed 's/^/      | /' <<<"$content"
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    chmod 0644 "$path"
    ok "wrote $path"
}

require_root() {
    [[ $DRY_RUN -eq 1 ]] && return 0
    [[ $EUID -eq 0 ]] || die "run as root (sudo $0 ...)"
}

service_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

detect_backend() {
    if service_active systemd-resolved; then
        echo resolved
    elif service_active NetworkManager; then
        echo networkmanager
    else
        echo resolvconf
    fi
}

unlock_resolv() {
    command -v chattr >/dev/null 2>&1 || return 0
    lsattr "$RESOLV_CONF" 2>/dev/null | head -1 | grep -q 'i' || return 0
    run chattr -i "$RESOLV_CONF"
}

# --- apply -------------------------------------------------------------------

apply_resolved() {
    local dns="" ip
    for ip in $P_IPV4 $P_IPV6; do
        if [[ -n "$P_DOT" ]]; then
            dns+="${dns:+ }${ip}#${P_DOT}"   # "#hostname" enables TLS name validation
        else
            dns+="${dns:+ }${ip}"
        fi
    done

    write_file "$RESOLVED_DROPIN" <<CONF
# Managed by dns-family-filter/setup-dns.sh - remove this file to revert.
# Provider: $P_NAME
[Resolve]
DNS=$dns
FallbackDNS=
Domains=~.
DNSOverTLS=$([[ -n "$P_DOT" ]] && echo yes || echo no)
DNSSEC=allow-downgrade
Cache=yes
DNSStubListener=yes
CONF

    # Make sure the system actually asks the local stub instead of a DHCP resolver.
    if [[ -e /run/systemd/resolve/stub-resolv.conf ]]; then
        unlock_resolv
        run ln -sf /run/systemd/resolve/stub-resolv.conf "$RESOLV_CONF"
    fi
    run systemctl restart systemd-resolved
}

apply_networkmanager() {
    local servers="${P_IPV4// /,}"
    [[ -n "$P_IPV6" ]] && servers+=",${P_IPV6// /,}"

    write_file "$NM_DROPIN" <<CONF
# Managed by dns-family-filter/setup-dns.sh - remove this file to revert.
# Provider: $P_NAME
[global-dns]
searches=

[global-dns-domain-*]
servers=$servers
CONF
    run systemctl reload NetworkManager || run systemctl restart NetworkManager
}

apply_resolvconf() {
    local ip
    if [[ ! -e "$RESOLV_BACKUP" && -f "$RESOLV_CONF" && $DRY_RUN -eq 0 ]]; then
        cp -a "$RESOLV_CONF" "$RESOLV_BACKUP"
        ok "backed up $RESOLV_CONF -> $RESOLV_BACKUP"
    fi
    unlock_resolv

    {
        echo "# Managed by dns-family-filter/setup-dns.sh - previous file: $RESOLV_BACKUP"
        echo "# Provider: $P_NAME"
        for ip in $P_IPV4 $P_IPV6; do echo "nameserver $ip"; done
        echo "options edns0 trust-ad"
    } | write_file "$RESOLV_CONF"

    if [[ $IMMUTABLE -eq 1 ]]; then
        if command -v chattr >/dev/null 2>&1; then
            run chattr +i "$RESOLV_CONF"
            ok "locked $RESOLV_CONF (chattr +i) so DHCP cannot overwrite it"
        else
            warn "chattr not available, skipping --immutable"
        fi
    fi
}

# --- revert ------------------------------------------------------------------

revert_all() {
    local touched=0
    if [[ -e "$RESOLVED_DROPIN" ]]; then
        run rm -f "$RESOLVED_DROPIN"; ok "removed $RESOLVED_DROPIN"
        service_active systemd-resolved && run systemctl restart systemd-resolved
        touched=1
    fi
    if [[ -e "$NM_DROPIN" ]]; then
        run rm -f "$NM_DROPIN"; ok "removed $NM_DROPIN"
        service_active NetworkManager && { run systemctl reload NetworkManager || true; }
        touched=1
    fi
    if [[ -e "$RESOLV_BACKUP" ]]; then
        unlock_resolv
        run cp -a "$RESOLV_BACKUP" "$RESOLV_CONF"
        run rm -f "$RESOLV_BACKUP"
        ok "restored $RESOLV_CONF"
        touched=1
    fi
    [[ $touched -eq 1 ]] || warn "nothing to revert"
}

# --- main --------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--provider) PROVIDER="${2:?}"; shift 2 ;;
        -b|--backend)  BACKEND="${2:?}";  shift 2 ;;
        -i|--immutable) IMMUTABLE=1; shift ;;
        -r|--revert)   REVERT=1; shift ;;
        -n|--dry-run)  DRY_RUN=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

require_root

if [[ $REVERT -eq 1 ]]; then
    revert_all
    log "run ./verify-dns.sh to confirm the filter is gone"
    exit 0
fi

provider_load "$PROVIDER" || die "unknown provider '$PROVIDER' (see --help)"
[[ "$BACKEND" == "auto" ]] && BACKEND="$(detect_backend)"

log "provider : $P_NAME"
log "resolvers: ${P_IPV4// /, }${P_IPV6:+ / ${P_IPV6// /, }}"
if [[ -n "$P_DOT" ]]; then
    log "transport: DNS-over-TLS ($P_DOT)"
else
    log "transport: plain UDP/53 (this provider offers no DoT)"
fi
log "backend  : $BACKEND"

case "$BACKEND" in
    resolved)       apply_resolved ;;
    networkmanager) apply_networkmanager ;;
    resolvconf)     apply_resolvconf ;;
    *) die "unknown backend '$BACKEND'" ;;
esac

ok "family DNS applied"
log "next: ./verify-dns.sh --provider $PROVIDER"
log "then: sudo ./lock-dns.sh --provider $PROVIDER   (blocks resolvers that bypass the filter)"
