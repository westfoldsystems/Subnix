# Info.plist, entitlements & bundled-data setup

Octet is local-only. This file is the single place that records every
platform declaration the app needs and every byte of data or endpoint it
touches, so the privacy posture stays auditable.

The app's `Info.plist` is **generated** (`GENERATE_INFOPLIST_FILE = YES`) and
**merged** with a small hand-written partial at `Lantern/Info.plist`. Scalar
keys live as `INFOPLIST_KEY_*` build settings; array keys live in the partial.

---

## Local network / Bonjour (ships today)

Used by **Bonjour Discovery**. Required or the browse silently returns nothing
on iOS, and (since macOS 15) prompts the user on macOS too.

| Key | Where it's set | Value |
|---|---|---|
| `NSBonjourServices` | `Lantern/Info.plist` (array) | the 14 service types in `BonjourScanner.defaultServiceTypes` — keep them in sync |
| `NSLocalNetworkUsageDescription` | `INFOPLIST_KEY_…` build setting | user-facing reason string |

macOS sandbox (`Lantern/Lantern.entitlements`, applied via
`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`):

- `com.apple.security.app-sandbox` = true
- `com.apple.security.network.client` = true — outbound only; nothing else.

> When the **LAN Scanner** (Phase 3) lands it reuses `NSLocalNetworkUsageDescription`
> and the same client-networking entitlement.

---

## External endpoints

Almost everything is on-device. The **only** outbound connections are:

- **Per-host tools** (TCP Port Check, HTTP Header Inspector, TLS Certificate
  Inspector) contact exactly the host the user types — nothing else. Local-only
  in spirit.
- **What's My IP — public-IP reflection.** The single deliberate third-party
  call. **Opt-in only** (a tap; never automatic), IPv4 and IPv6 are independent,
  and the UI names the provider contacted. Each family tries its provider then a
  fallback:

  | Family | Provider (primary) | Fallback |
  |---|---|---|
  | IPv4 | `https://1.1.1.1/cdn-cgi/trace` (parse `ip=`) | `https://api.ipify.org?format=json` |
  | IPv6 | `https://[2606:4700:4700::1111]/cdn-cgi/trace` | `https://api6.ipify.org?format=json` |

  IP literals pin the address family (the literals are valid SANs on Cloudflare's
  cert; ipify's `api`/`api6` hostnames are family-specific). Nothing is sent but
  the request itself; the response is the caller's own public IP. No analytics,
  no identifiers.

Local interface enumeration (What's My IP) uses `getifaddrs` — that's a local
syscall, not a network call.

### Phase 3 (Diagnostics + Discovery)

- **DNS Lookup** contacts only the resolver the user selects (1.1.1.1 / 8.8.8.8
  / 9.9.9.9 / a custom IP) over UDP, falling back to TCP on a truncated reply. A
  "System resolver" option is intentionally not shipped — discovering it needs
  `res_getservers` via a C bridging header and is sandbox-variable.
- **Ping** sends ICMP echo to the typed host via an unprivileged `SOCK_DGRAM`
  socket. Verified unsandboxed on macOS; inbound ICMP replies are **dropped by
  the macOS app-sandbox** (no entitlement covers them) so the sandboxed mac build
  shows 100% loss. iOS-device behaviour is unverified.
- **LAN Scanner** sweeps the local /24 with TCP connects (which also populate the
  ARP cache) and reads the cache via `sysctl(NET_RT_FLAGS)`. Uses
  `NSLocalNetworkUsageDescription` (already declared for Bonjour). The ARP read
  is **macOS-only** — `rt_msghdr` isn't in Swift's iOS Darwin overlay; on iOS the
  scanner returns liveness + hostname but no MAC/vendor until a bridging-header
  path is validated on a device. On macOS 15+ / iOS the OS shows a local-network
  permission prompt on first scan.

---

## OUI database — ✅ SOURCED (IEEE MA-L registry)

The **MAC Vendor Lookup** is backed by the official IEEE MA-L registry, bundled
offline. No vendor names are invented or hardcoded; the data is the IEEE file,
converted verbatim.

- **Source:** `https://standards-oui.ieee.org/oui/oui.csv` (the public MA-L
  registry).
- **Bundled file:** `Lantern/oui-mal.tsv` (~39.5k assignments, ~1.2 MB). Picked
  up automatically by the synchronized `Lantern` group → Copy Bundle Resources;
  read at runtime via `Bundle.main`, parsed once into `OUILookup.shared`.
- **Refreshing:** re-download `oui.csv`, keep `Registry == MA-L` rows, and emit
  `Assignment<TAB>Organization Name` (collapsing internal whitespace) over the
  bundled file. The app needs no code changes.
- **Still open:** MA-M (28-bit) and MA-S (36-bit) assignments are not bundled —
  v1 is MA-L only (see schema note below).
- **No network at runtime:** the download is a build-time/maintenance step; the
  app never contacts IEEE.

### What the engine expects

A UTF-8 file **`oui-mal.tsv`** added to the `Lantern` target (so it lands in the
app bundle). One assignment per line, `#` comments and blank lines ignored:

```
# 24-bit MA-L assignments
001B63	Apple, Inc.
3C5AB4	Google, Inc.
```

- **Column 1** — the 24-bit MA-L prefix, 6 hex digits, no separators, any case.
- **Column 2** — organization name, verbatim (tab-separated).

v1 is **MA-L (24-bit) only**. The IEEE registry also publishes **MA-M (28-bit)**
and **MA-S (36-bit)** assignments, where the vendor owns only part of the third
byte; supporting those needs a longer key + mask and is a later schema bump.

### Candidate sources (for the owner to choose)

1. **IEEE official CSV** — `https://standards-oui.ieee.org/oui/oui.csv`
   (MA-L). Authoritative, updated by IEEE, public. Needs a one-time conversion
   to the `oui-mal.tsv` format above (strip to `Assignment` + `Organization
   Name` columns). License: IEEE provides the registry publicly; confirm
   redistribution terms before bundling.
2. **Wireshark `manuf`** — curated, includes short names, widely used. Check the
   GPL licensing implications of bundling it in a closed app.
3. **A trimmed subset** — bundle only the OUIs you care about to keep app size
   down (the full MA-L list is ~35k rows / a few MB).

**Decision needed:** which source, full vs. trimmed, and whether the license
permits bundling. Drop the converted `oui-mal.tsv` into `Lantern/` and add it to
the target — the engine and UI pick it up with no code changes.
