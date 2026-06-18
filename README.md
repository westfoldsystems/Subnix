# Octet

A local-only network toolkit for iOS 17+ and macOS 14+ (native, multiplatform
SwiftUI, Swift 6 language mode).

> Note: the Xcode target/module/scheme is still named `Lantern` pending a
> separate module-rename step, so the `xcodebuild -scheme Lantern …` commands
> below remain accurate until that lands.

**Privacy is the product.** No analytics, no third-party SDKs, no dependencies.
Tools are either fully on-device or contact only the host you explicitly type.
The single deliberate third-party call — public-IP reflection in *What's My IP* —
is opt-in, labelled in-app, and documented in
[`SupportingFiles/Info-plist-setup.md`](SupportingFiles/Info-plist-setup.md).

## Architecture

Each tool is a **pure engine type** + a **thin SwiftUI view** + a **one-line
`ToolRegistry` entry**, filed under a `ToolCategory`. Output uses the shared
copyable `ResultRow`. Pure-compute engines have Swift Testing files; network
engines are `@MainActor @Observable` and hop background callbacks back to the
main actor with `Task { @MainActor in … }`.

## Tools

| Tool | Category | What it does | Network |
|---|---|---|---|
| Subnet Calculator | Calculators | IPv4 CIDR, masks, host ranges/counts | Offline |
| VLSM Planner | Calculators | Pack named subnets into a base block, largest-first | Offline |
| IPv6 Toolkit | Calculators | RFC 5952 compress/expand, prefix math, EUI-64 | Offline |
| Converters | Calculators | IPv4 dotted/hex/binary/integer + MAC normaliser | Offline |
| MAC Vendor Lookup | Lookup | Manufacturer from the bundled IEEE MA-L registry | Offline |
| TCP Port Check | Lookup | Connect-scan ports on a host you type | Typed host only |
| HTTP Header Inspector | Lookup | Redirect chain + response & security headers | Typed host only |
| TLS Certificate Inspector | Lookup | Certificate chain, SANs, validity, key | Typed host only |
| What's My IP | Lookup | All local interfaces; public IP on an opt-in tap | Local + opt-in reflection |
| DNS Lookup | Lookup | A/AAAA/MX/TXT/… via a hand-rolled wire codec, UDP+TCP | Chosen resolver |
| Ping | Diagnostics | ICMP echo: RTT, loss, min/avg/max/stddev | Typed host only |
| Bonjour Discovery | Discovery | mDNS/Bonjour services on the local network | LAN only |
| LAN Scanner | Discovery | Sweep the /24 → live hosts + MAC + vendor + hostname | LAN only |

## Roadmap

- **Phase 1 — Calculators + offline lookup.** ✅ Shipped. VLSM, IPv6, Converters,
  MAC Vendor Lookup (IEEE MA-L bundled).
- **Phase 2 — Lookup (per-host network tools).** ✅ Shipped. TCP Port Check,
  HTTP Header Inspector, TLS Certificate Inspector, What's My IP.
- **Phase 3 — Diagnostics + Discovery (sandbox-constrained).** ✅ Shipped, with
  device caveats below. DNS Lookup (hardened wire codec, UDP + TCP fallback),
  Ping (clean-room SOCK_DGRAM ICMP), and the hero **LAN Scanner**
  (TCP sweep → ARP via `sysctl` → reverse-DNS + OUI).
  Traceroute remains deliberately omitted — TTL-limited probes are unreliable in
  the iOS sandbox.

## Verification status

Pure engines are unit-tested (79 tests). Network/socket tools were validated on
**macOS with a real network**; **no physical iPhone was available, so iOS-device
behaviour is UNVERIFIED** for the sandbox-sensitive tools:

| Tool | macOS | iOS device | Notes |
|---|---|---|---|
| DNS Lookup | ✅ codec + live UDP/TCP | ⚠️ unverified | "System" resolver deferred (needs C bridging) |
| Ping (ICMP) | ⚠️ socket opens/sends; **replies blocked by macOS sandbox** | ⚠️ unverified | Logic verified unsandboxed; likely works on device |
| LAN Scanner | ✅ sweep + `sysctl` ARP + enrichment | ⚠️ unverified | ARP read is **macOS-only** (`rt_msghdr` absent on iOS); iOS gets liveness+hostname, no MAC |

Bonjour cross-reference in the LAN Scanner is not implemented — `BonjourScanner`
captures service names but not resolved IPs, so there's no honest IP↔service join
without address resolution the app doesn't do.

## Brand colors

The palette lives as Asset Catalog color sets in `Assets.xcassets` (each with a
light and a warm-dark variant). With Swift asset-symbol generation on, every set
is exposed as a semantic token usable in any style position — no hex in views:

```swift
Text(value).foregroundStyle(.octetInk)        // primary text
Text(label).foregroundStyle(.octetMuted)      // secondary text
Circle().fill(.statusOnline)                  // status
.background(.octetSurface)                     // cards/rows
```

Tokens: `.octetPaper`, `.octetSurface`, `.octetHairline`, `.octetInk`,
`.octetMuted`, `.octetAccent`, `.octetAccentDeep`, `.octetTint`, `.statusOnline`,
`.statusOffline`, `.statusTimeout`, `.statusError`.

`ResultRow` is wired as the reference example. **Roll-out:** screen by screen,
replace ad-hoc styles with tokens — `.secondary` → `.octetMuted`, the orange
warning labels → `.statusTimeout`, port/ping status text → `.statusOnline` /
`.statusError`, and set `.octetPaper` as the list/form background with
`.octetSurface` rows. Set the app `.tint(.octetAccent)` once at the `RootView`
level to recolor controls globally.

## Building & testing

```sh
# macOS
xcodebuild -scheme Lantern -destination 'platform=macOS' build
# iOS simulator
xcodebuild -scheme Lantern -destination 'platform=iOS Simulator,name=iPhone 17' build
# Tests (Swift Testing)
xcodebuild -scheme Lantern -destination 'platform=macOS' test
```

The macOS build is sandboxed with client-networking only; see
[`SupportingFiles/Info-plist-setup.md`](SupportingFiles/Info-plist-setup.md) for
entitlements, the Bonjour declarations, the bundled OUI database, and every
external endpoint.
