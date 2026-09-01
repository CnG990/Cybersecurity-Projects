# Guide rapide (français)

Objectif : empêcher l'accès aux sites pornographiques en remplaçant le
résolveur DNS de l'appareil par un résolveur filtrant (Cloudflare for
Families, `1.1.1.3`). Le résolveur refuse simplement de donner l'adresse IP
de ces sites.

## Téléphone Android (5 minutes, couvre le Wi-Fi et la 4G/5G)

`Paramètres` → `Réseau et Internet` → `DNS privé` → *Nom d'hôte du
fournisseur de DNS privé* → saisir :

```
family.cloudflare-dns.com
```

Vérification : ouvrir `pornhub.com` (doit échouer) puis `wikipedia.org` (doit
fonctionner).

## iPhone / iPad

1. Installer le profil `configs/apple/family-dns-cloudflare.mobileconfig`
   (AirDrop ou e-mail), puis `Réglages` → `Général` → `VPN et gestion de
   l'appareil` → installer.
2. Activer aussi `Réglages` → `Temps d'écran` → `Restrictions de contenu` →
   `Contenu web` → **Limiter les sites web pour adultes**, avec un code
   différent du code de déverrouillage.

## PC Linux

```bash
sudo ./setup-dns.sh                 # applique le DNS filtrant (DoT)
./verify-dns.sh                     # vérifie que le filtre fonctionne
sudo ./lock-dns.sh --block-doh      # empêche de contourner par un autre DNS
sudo ./setup-dns.sh --revert        # tout annuler
```

## Box / routeur (toute la maison)

Dans l'interface d'administration de la box, remplacer les serveurs DNS DHCP
par `1.1.1.3` et `1.0.0.3` (et les adresses IPv6 correspondantes, sinon le
filtre est contourné en IPv6). Détails dans `docs/ROUTER.md`.

## À savoir

- Le DNS-over-HTTPS du navigateur court-circuite ce filtre : le désactiver
  (fichiers dans `configs/browser-policies/`).
- Un VPN, un partage de connexion, ou l'accès direct par adresse IP passent
  aussi à côté du filtre — voir `docs/BYPASS.md`.
- Sur un appareil dont on possède le code, le réglage peut être annulé : pour
  un enfant, utiliser Family Link (Android) ou Temps d'écran + supervision
  (iOS) afin de verrouiller le paramètre.
