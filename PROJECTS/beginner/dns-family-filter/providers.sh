#!/usr/bin/env bash
# =============================================================================
# providers.sh - shared catalogue of family-filtering DNS resolvers.
#
# Sourced by setup-dns.sh, verify-dns.sh and lock-dns.sh. Every provider below
# blocks adult content at the resolution layer: the resolver simply refuses to
# hand back the IP address of a pornographic domain.
#
# Fields (set by provider_load <name>):
#   P_NAME    human readable name
#   P_IPV4    space separated IPv4 resolvers (primary first)
#   P_IPV6    space separated IPv6 resolvers (may be empty)
#   P_DOT     DNS-over-TLS hostname, or "" when the provider has none
#   P_DOH     DNS-over-HTTPS URL, or "" when the provider has none
#   P_SINK    space separated addresses the provider returns for a blocked name
# =============================================================================

PROVIDERS="cloudflare adguard cleanbrowsing opendns"

# shellcheck disable=SC2034  # P_* are consumed by the scripts sourcing this file
provider_load() {
    case "${1:-}" in
        cloudflare)
            P_NAME="Cloudflare for Families (malware + adult)"
            P_IPV4="1.1.1.3 1.0.0.3"
            P_IPV6="2606:4700:4700::1113 2606:4700:4700::1003"
            P_DOT="family.cloudflare-dns.com"
            P_DOH="https://family.cloudflare-dns.com/dns-query"
            P_SINK="0.0.0.0 ::"
            ;;
        adguard)
            P_NAME="AdGuard DNS Family Protection"
            P_IPV4="94.140.14.15 94.140.15.16"
            P_IPV6="2a10:50c0::bad1:ff 2a10:50c0::bad2:ff"
            P_DOT="family.adguard-dns.com"
            P_DOH="https://family.adguard-dns.com/dns-query"
            P_SINK="0.0.0.0 ::"
            ;;
        cleanbrowsing)
            P_NAME="CleanBrowsing Family Filter"
            P_IPV4="185.228.168.168 185.228.169.168"
            P_IPV6="2a0d:2a00:1:: 2a0d:2a00:2::"
            P_DOT="family-filter-dns.cleanbrowsing.org"
            P_DOH="https://doh.cleanbrowsing.org/doh/family-filter/"
            P_SINK="0.0.0.0 ::"
            ;;
        opendns)
            P_NAME="OpenDNS FamilyShield"
            P_IPV4="208.67.222.123 208.67.220.123"
            P_IPV6=""
            P_DOT=""
            P_DOH=""
            # FamilyShield answers with its own block page instead of 0.0.0.0.
            P_SINK="146.112.61.104 146.112.61.106 146.112.61.107 146.112.61.108 146.112.61.110"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

provider_list() {
    local p
    for p in $PROVIDERS; do
        provider_load "$p"
        printf '  %-14s %-42s %s\n' "$p" "$P_NAME" "${P_IPV4// /, }"
    done
}
