# Browser policies

Modern browsers ship their own DNS-over-HTTPS client. When it is on, the
browser resolves names itself and the system resolver — the one you just
configured — is never asked. These policy files turn that off and pin the
browser to the operating system resolver.

| Browser | File | Install path |
|---------|------|--------------|
| Firefox | `firefox-policies.json` | `/etc/firefox/policies/policies.json` (Linux), `/Applications/Firefox.app/Contents/Resources/distribution/policies.json` (macOS), `HKLM\SOFTWARE\Policies\Mozilla\Firefox` (Windows) |
| Chrome / Chromium | `chrome-dns-policy.json` | `/etc/opt/chrome/policies/managed/family-dns.json` or `/etc/chromium/policies/managed/family-dns.json` (Linux), `/Library/Managed Preferences/com.google.Chrome.plist` (macOS), `HKLM\SOFTWARE\Policies\Google\Chrome` (Windows) |
| Edge | `chrome-dns-policy.json` (same keys) | `/etc/opt/edge/policies/managed/family-dns.json`, `HKLM\SOFTWARE\Policies\Microsoft\Edge` |

Restart the browser, then confirm at `about:policies` (Firefox) or
`chrome://policy` (Chrome/Edge) that the setting is applied and greyed out for
the user.
