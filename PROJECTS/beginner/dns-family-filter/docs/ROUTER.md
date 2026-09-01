# Whole-home filtering on the router

Filtering on the router covers every device on the LAN — TVs, consoles,
guests — without touching each one.

## 1. Set the resolver

In the router's admin page, find the DHCP or WAN settings and replace the DNS
servers with the family filter (Cloudflare for Families shown here):

```
Primary DNS   : 1.1.1.3
Secondary DNS : 1.0.0.3
IPv6 primary  : 2606:4700:4700::1113
IPv6 secondary: 2606:4700:4700::1003
```

Common paths: `Internet` → `DNS` (Freebox, Livebox), `Advanced` → `DHCP
Server` (TP-Link, ASUS), `Network` → `Interfaces` → `LAN` → `DHCP Server` →
`Advanced` (OpenWrt).

> [!WARNING]
> If IPv6 stays enabled and still advertises the ISP's resolver, devices will
> resolve over IPv6 and skip the filter entirely. Set both families, or turn
> IPv6 off while testing.

## 2. Stop clients from using another resolver

A device configured with `8.8.8.8` ignores the router's DNS. Either:

- use the router's own firewall rules ("Block outbound port 53 except to the
  router"), or
- run the nftables lock from this project on a Linux router:

```bash
sudo ./lock-dns.sh --mode router --lan-iface br0 --provider cloudflare \
                   --save /etc/nftables.d/family-dns.nft
```

That drops LAN DNS towards anything but the approved resolver, and DNATs
hard-coded resolvers back to it, so unaware devices keep working while being
filtered.

## 3. Optional: run your own filtering resolver

[Pi-hole](https://pi-hole.net) or [AdGuard Home](https://adguard.com/adguard-home/overview.html)
on a Raspberry Pi gives per-device logs, an adult-content blocklist of your
own, and a bypass report:

1. Install it and set its upstream to `1.1.1.3` / `1.0.0.3`.
2. Add an adult blocklist (for example the StevenBlack `porn-only` list this
   project also uses in `fetch-blocklist.sh`).
3. Point the router's DHCP DNS at the Pi's address.
4. Add the firewall rules above with `--redirect-to <pi-address>` so clients
   cannot skip the Pi.

## 4. Verify

From a LAN client:

```bash
./verify-dns.sh                    # via the router's DNS
./verify-dns.sh --server 1.1.1.3   # against the filter directly
```

Adult domains must come back blocked, control domains must keep resolving.

## Limits

Mobile data bypasses the router completely: a phone on 4G/5G is outside its
scope. Configure the phone itself as well (`docs/MOBILE.md`).
