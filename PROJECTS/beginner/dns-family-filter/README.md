```ruby
██████╗ ███╗   ██╗███████╗    ███████╗ █████╗ ███╗   ███╗██╗██╗  ██╗   ██╗
██╔══██╗████╗  ██║██╔════╝    ██╔════╝██╔══██╗████╗ ████║██║██║  ╚██╗ ██╔╝
██║  ██║██╔██╗ ██║███████╗    █████╗  ███████║██╔████╔██║██║██║   ╚████╔╝
██║  ██║██║╚██╗██║╚════██║    ██╔══╝  ██╔══██║██║╚██╔╝██║██║██║    ╚██╔╝
██████╔╝██║ ╚████║███████║    ██║     ██║  ██║██║ ╚═╝ ██║██║███████╗██║
╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝     ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚═╝
```

[![Cybersecurity Projects](https://img.shields.io/badge/Cybersecurity--Projects-DNS%20Family%20Filter-red?style=flat&logo=github)](./)
[![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![nftables](https://img.shields.io/badge/nftables-0B4F6C?style=flat&logo=linux&logoColor=white)](https://netfilter.org/projects/nftables/)
[![License: AGPLv3](https://img.shields.io/badge/License-AGPL_v3-purple.svg)](https://www.gnu.org/licenses/agpl-3.0)

> Block adult content at the DNS layer — on a Linux host, a phone, or a whole home network — and prove it actually works.

**Français : [docs/GUIDE-FR.md](docs/GUIDE-FR.md)**

## What It Does

- Points a Linux machine at a family-filtering resolver over DNS-over-TLS (`setup-dns.sh`)
- Tests the result against real adult and control domains, with a meaningful exit code (`verify-dns.sh`)
- Closes the obvious bypasses with nftables: hard-coded resolvers, DoT, well-known DoH front-ends (`lock-dns.sh`)
- Adds a local hosts-file blocklist as a second layer, ~77k domains (`fetch-blocklist.sh`)
- Ships ready-made configs for systemd-resolved, dnsmasq, Unbound, browser policies, and an iOS/macOS DNS profile

## Quick Start

```bash
sudo ./setup-dns.sh                  # apply Cloudflare for Families (1.1.1.3) over DoT
./verify-dns.sh                      # confirm adult domains are blocked, normal sites are not
sudo ./lock-dns.sh --block-doh       # stop the easy ways around it
sudo ./setup-dns.sh --revert         # undo
```

Nothing is installed system-wide; every change is written to a marked drop-in
or backed up first, and each script has `--revert` and `--dry-run`.

## Scripts

| Script | Purpose |
|--------|---------|
| `setup-dns.sh` | Configure the system resolver (systemd-resolved, NetworkManager, or `/etc/resolv.conf`) |
| `verify-dns.sh` | Resolve canary domains and report BLOCKED / RESOLVED; exit 1 if the filter leaks, 2 if it over-blocks |
| `lock-dns.sh` | nftables table allowing DNS only towards the approved resolver; router mode DNATs stray clients back |
| `fetch-blocklist.sh` | Install the StevenBlack `porn-only` hosts list between markers in `/etc/hosts` |
| `providers.sh` | Shared resolver catalogue, sourced by the others |

## Providers

| Name | IPv4 | DNS-over-TLS hostname | Notes |
|------|------|------------------------|-------|
| `cloudflare` | `1.1.1.3`, `1.0.0.3` | `family.cloudflare-dns.com` | Default. Adult content + malware |
| `adguard` | `94.140.14.15`, `94.140.15.16` | `family.adguard-dns.com` | Adult content + ads + trackers |
| `cleanbrowsing` | `185.228.168.168`, `185.228.169.168` | `family-filter-dns.cleanbrowsing.org` | Also forces safe search |
| `opendns` | `208.67.222.123`, `208.67.220.123` | — | Answers with a block page instead of `0.0.0.0` |

```bash
sudo ./setup-dns.sh --provider cleanbrowsing
```

## Coverage by scenario

| Scenario | Do this |
|----------|---------|
| One Linux PC | `setup-dns.sh` + `lock-dns.sh` + browser policies |
| Android phone | Private DNS → `family.cloudflare-dns.com` ([docs/MOBILE.md](docs/MOBILE.md)) |
| iPhone / iPad | Install `configs/apple/family-dns-cloudflare.mobileconfig` + Screen Time |
| Whole home | Router DHCP DNS + firewall rules ([docs/ROUTER.md](docs/ROUTER.md)) |
| Can't change DNS | `fetch-blocklist.sh` (hosts file) |

## How it works

A browser cannot open `example-adult-site.com` until something turns that name
into an IP address. A filtering resolver answers those specific names with
`0.0.0.0` (or a block page) and everything else normally, so the block happens
before a single byte of the site is fetched — no proxy, no TLS interception, no
per-app configuration.

Two things decide whether that holds:

1. **Which resolver the device really uses.** DHCP, VPN clients, and browsers
   all try to choose it for you. `setup-dns.sh` pins it; `lock-dns.sh` makes the
   alternatives fail instead of silently working.
2. **Whether the query is visible.** DNS-over-TLS (port 853) keeps the ISP from
   reading or rewriting queries, while still letting the local firewall enforce
   *which* resolver is used — unlike browser DoH, which hides the query from your
   own controls too.

## Limits

DNS filtering removes casual access; it is not an access-control system. Raw IP
addresses, VPNs, tethering, and apps with a built-in resolver all bypass it —
see [docs/BYPASS.md](docs/BYPASS.md) for the full list and what to pair it with.

## Documentation

| Document | Topic |
|----------|-------|
| [docs/GUIDE-FR.md](docs/GUIDE-FR.md) | Guide rapide en français |
| [docs/MOBILE.md](docs/MOBILE.md) | Android Private DNS, iOS profiles, Screen Time |
| [docs/ROUTER.md](docs/ROUTER.md) | Router DHCP settings, Pi-hole/AdGuard Home, LAN enforcement |
| [docs/BYPASS.md](docs/BYPASS.md) | Every known bypass and its mitigation |

## Requirements

`bash`, `curl` (or `wget`), and `nftables` for the lock script. `dig`
(`dnsutils` / `bind-utils`) makes verification precise; the script falls back to
`getent` or `python3` when it is missing.

## License

AGPL-3.0 — see [LICENSE](LICENSE).
