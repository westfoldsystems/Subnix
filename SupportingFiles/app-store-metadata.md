# Subnix — App Store submission metadata

Everything needed for App Store Connect, ready to paste. Character limits noted; all copy is within them.

---

## Identity

- **App name** (≤30): `Subnix`
- **Subtitle** (≤30) — pick one:
  - `Privacy-first network toolkit` (29) ← recommended
  - `On-device network toolkit` (25)
  - `Network tools, no tracking` (26)
- **Bundle ID:** replace the `app.subnix.Subnix` placeholder with your Team's reverse-DNS ID before archiving.
- **Primary category:** Utilities
- **Secondary category:** Developer Tools
- **Age rating:** 4+ (no objectionable content)
- **Price:** (your choice)
- **Availability:** Universal purchase — iPhone, iPad, Mac (one binary)

---

## Promotional text (≤170, editable without a review)

```
The network toolkit that stays on your device. Subnet math, DNS, TLS, ports, LAN discovery, Ping and Wake-on-LAN — no account, no ads, no tracking. iPhone, iPad, Mac.
```
(159 chars)

---

## Description (≤4000)

```
Subnix is a complete network toolkit that runs entirely on your device. No account. No ads. No tracking. No analytics. The calculators and lookups work with no signal at all — on a plane, in a data center, anywhere.

Fourteen focused tools, one clean app, on iPhone, iPad, and Mac.

CALCULATORS
• Subnet Calculator — network, broadcast, mask, host ranges and counts for any IPv4 CIDR, including the /31 and /32 edge cases.
• VLSM Planner — pack named subnets into a base block, largest-first.
• IPv6 Toolkit — compress and expand addresses, prefix math, EUI-64.
• Converters — IPv4 base conversion and MAC normalization.

LOOKUP
• MAC Vendor Lookup — resolve a MAC address to its manufacturer from the bundled IEEE registry, fully offline, with an optional one-tap refresh.
• TCP Port Check — connect-scan ports on any host: open, closed, or filtered, with latency.
• HTTP Header Inspector — follow the full redirect chain and inspect response and security headers.
• TLS Certificate Inspector — read a host's certificate: subject, issuer, validity, SANs, key, and the negotiated TLS version and cipher.
• DNS Lookup — query A, AAAA, MX, TXT, NS, SOA, PTR, SRV and CAA against Cloudflare, Google, Quad9, or a resolver you choose.
• What's My IP — every local interface address, plus your public IP on an opt-in tap.

DIAGNOSTICS
• Ping — reachability and round-trip time by ICMP or TCP.
• Wake-on-LAN — wake a sleeping device by its MAC with a magic packet.

DISCOVERY
• Bonjour Discovery — find services advertised on your local network.
• LAN Scanner — sweep your subnet and identify live hosts with MAC, vendor, hostname, open ports, device type, latency, and TLS/Bonjour names.

PRIVATE BY DESIGN
Subnix has no user accounts and collects no data about you. The only connections it makes are the ones you ask for — the host you type into a tool, an opt-in public-IP check, or an opt-in vendor-database refresh. Everything else is computed on-device.

BUILT FOR THE PLATFORM
• Universal — one purchase for iPhone, iPad, and Mac.
• Shortcuts and Siri — run "What's my IP", subnet math, and host-reachability checks from the Shortcuts app.
• Full Dynamic Type and light/dark support.

Subnix is for network engineers, sysadmins, developers, students, and home-lab tinkerers who want fast, trustworthy tools without the bloat.
```

---

## Keywords (≤100, comma-separated, no spaces)

```
subnet,cidr,vlsm,ipv6,dns,ping,port,scan,tls,ssl,mac,vendor,oui,lan,bonjour,mdns,wol,ip,sysadmin
```
(96 chars) — don't repeat words already in the name/subtitle; Apple indexes those separately.

---

## What's New (v1.0)

```
First release. Fourteen network tools in one private, on-device app — subnet/VLSM/IPv6 calculators, converters, MAC vendor lookup, TCP port check, HTTP header and TLS certificate inspectors, DNS lookup, What's My IP, Ping (ICMP + TCP), Wake-on-LAN, Bonjour discovery, and a rich LAN scanner. Shortcuts and Siri support. No account, no ads, no tracking.
```

---

## App Privacy ("nutrition label")

**Answer: Data Not Collected.** In App Store Connect → App Privacy, select **"Data Not Collected"** for the developer and all third parties. Rationale:

- No analytics, no SDKs, no advertising, no accounts, no telemetry.
- The app makes network connections, but **no data is collected by the developer**. All connections are user-initiated to destinations the user chooses (a host they type), or clearly labeled opt-in features (public-IP check via Cloudflare/ipify; OUI refresh from IEEE). None of this sends personal data to the developer or a data broker.
- The App Privacy label describes what the **developer** collects — which is nothing.

Set **Privacy Policy URL** (required — host `PRIVACY.md` somewhere public).

---

## App Review notes (paste into "Notes")

```
Subnix is an offline-first network diagnostics utility. No account or login is required — every feature is available immediately.

Network use is core functionality and always user-initiated:
• Tools like Ping, TCP Port Check, HTTP/TLS inspectors, and DNS Lookup connect only to the host the reviewer enters.
• "What's My IP" contacts Cloudflare/ipify only when tapped (to reflect the public IP).
• "Update from IEEE" in MAC Vendor Lookup downloads the public IEEE OUI registry only when tapped.
• Local Network permission (NSLocalNetworkUsageDescription) powers Bonjour Discovery and LAN Scanner, which browse the local network only. No data leaves the LAN for these features.

The app collects no analytics and has no third-party SDKs. To exercise the main flows: open LAN Scanner and tap Scan; open Ping (defaults to TCP) and tap Ping; open TLS Certificate Inspector and inspect example.com.

Note on ICMP: Ping defaults to a TCP connect mode because ICMP is restricted in some sandboxes; ICMP is offered as an option.
```

---

## Export compliance

Subnix uses only standard, OS-provided encryption (HTTPS/TLS via URLSession and Network.framework, and Apple's Security framework for reading certificate key info). It implements no proprietary cryptography. This qualifies as **exempt**.

- Recommended: add `ITSAppUsesNonExemptEncryption = NO` to the build settings / Info.plist so App Store Connect stops asking each submission. (Offer stands to wire this up.)

---

## Screenshots

Required sets (App Store Connect will derive smaller sizes from the largest per family):
- **iPhone 6.9"** (e.g. iPhone 17 Pro Max) — 1320 × 2868 — REQUIRED
- **iPad 13"** — 2064 × 2752 — required (iPad is supported)
- **Mac** — 1280 × 800 (or 1440 × 900 / 2560 × 1600)

Suggested 5–6 shots + caption ideas (lead with the hero tool):
1. **LAN Scanner** results (hosts with vendor/ports/device type) — "See everything on your network."
2. **Main menu** (all 14 tools by category) — "Fourteen tools. One private app."
3. **Subnet Calculator** result — "Subnet math that just works — even offline."
4. **TLS Certificate Inspector** (protocol/cipher + validity) — "Inspect any certificate in seconds."
5. **Ping** summary (TCP, min/avg/max) — "Reachability and latency, ICMP or TCP."
6. **DNS Lookup** or **What's My IP** — "Your resolver, your rules." / "On-device by default."

Capture on a booted simulator: `xcrun simctl io booted screenshot shot.png` after navigating to each tool. (Offer stands to capture the sim-friendly ones — main menu, LAN Scanner, Ping.)
