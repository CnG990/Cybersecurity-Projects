# Phones and tablets

A phone has two network paths — Wi-Fi and mobile data — and per-network DNS
settings only cover the first one. Use a setting that applies to the whole
device.

## Android 9+ (the right way: Private DNS / DNS-over-TLS)

`Settings` → `Network & internet` → `Private DNS` → *Private DNS provider
hostname*, then enter one of:

| Provider | Hostname |
|----------|----------|
| Cloudflare for Families | `family.cloudflare-dns.com` |
| AdGuard Family | `family.adguard-dns.com` |
| CleanBrowsing Family | `family-filter-dns.cleanbrowsing.org` |

This applies to Wi-Fi **and** mobile data, is encrypted, and survives network
changes. Verify by opening `pornhub.com` in a browser: it must fail to load
(DNS error), while `wikipedia.org` still works.

> [!IMPORTANT]
> A user with the device passcode can undo this in ten seconds. To make it
> stick, add [Google Family Link](https://families.google/familylink/) on a
> child account, or enrol the device in an MDM and lock the Private DNS
> setting.

Android 8 and older have no Private DNS: set the DNS servers per Wi-Fi network
(static IP configuration) and rely on the router for everything else, or
install a local-VPN filtering app.

## iOS / iPadOS

Install a DNS configuration profile — `configs/apple/family-dns-cloudflare.mobileconfig`
in this project is ready to use:

1. AirDrop or e-mail the file to the device (or host it and open the link).
2. `Settings` → `General` → `VPN & Device Management` → install the profile.
3. `Settings` → `General` → `VPN & Device Management` → confirm it is active.

The profile applies to Wi-Fi and cellular. To stop the profile from being
removed, deploy it through an MDM with `PayloadRemovalDisallowed` set to
`true` and the device supervised — on an unsupervised device, removal is
always possible.

Then, on the same device:

- `Settings` → `Screen Time` → `Content & Privacy Restrictions` →
  `Content Restrictions` → `Web Content` → **Limit Adult Websites**. This is
  Apple's own filter and covers Safari plus most in-app browsers.
- Set a Screen Time passcode different from the unlock passcode.

## Both platforms

- The browser's own DNS-over-HTTPS setting overrides the system resolver.
  In Chrome: `Settings` → `Privacy and security` → `Use secure DNS` → off.
  In Firefox: `Settings` → `Privacy & Security` → `DNS over HTTPS` → off.
- A VPN app replaces DNS entirely. Remove VPN apps, or block their install.
- DNS filtering blocks names, not addresses: content reachable by raw IP, or
  inside apps that ship their own resolver, is not covered. Combine with the
  platform's parental controls, as above.
