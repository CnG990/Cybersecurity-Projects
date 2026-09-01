# What a DNS filter does not stop

DNS filtering is the cheapest effective control, not a wall. Know its holes
before trusting it.

| Bypass | Why it works | Mitigation |
|--------|--------------|-----------|
| Browser DNS-over-HTTPS | Chrome/Firefox/Edge resolve names themselves over 443, ignoring the system resolver | `configs/browser-policies/` (locked policy), `lock-dns.sh --block-doh` |
| Another resolver (`8.8.8.8`) | The device or an app is configured with its own DNS server | `lock-dns.sh` drops 53/853 to anything but the filter; on a router, DNAT it back |
| VPN / proxy app | All traffic, DNS included, leaves through a tunnel | Remove the app, block install (Family Link, Screen Time, MDM), block known VPN endpoints |
| Mobile data | The router's DNS never sees the query | Configure the phone itself: Private DNS (Android) or a DNS profile (iOS) |
| Tethering from another phone | The device leaves your network altogether | Device-level configuration, as above |
| Direct IP access, DoH-in-app | No domain name is ever resolved | Platform content filters (Screen Time, Family Link), network-level category filtering |
| Public DNS over an odd port | Some resolvers listen on 5353, 443/UDP, etc. | Default-deny outbound firewall rather than port-based blocking |
| Reset / factory restore | The configuration is simply removed | Supervised device + MDM, or a filter on the network the device must use |

## Practical layering

1. **Router** — covers every device at home, including ones you cannot configure.
2. **Device** — Private DNS or a DNS profile, so the phone stays filtered on mobile data.
3. **Firewall lock** — `lock-dns.sh`, so a changed DNS setting does not silently work.
4. **Browser policy** — otherwise DoH quietly reopens everything.
5. **Platform parental controls** — Screen Time / Family Link cover what DNS cannot.

## On the honest limits

Anyone with the device passcode and a few minutes can undo a filter they own.
DNS filtering is there to remove casual access and accidental exposure; for a
child's device, pair it with a managed account so the settings cannot be
changed, and with a conversation about why the filter exists.
