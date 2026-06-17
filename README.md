# Lantern

A local-only network toolkit for iOS 17+ and macOS 14+ (native, multiplatform
SwiftUI, Swift 6 language mode).

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
| Bonjour Discovery | Discovery | mDNS/Bonjour services on the local network | LAN only |

## Roadmap

- **Phase 1 — Calculators + offline lookup.** ✅ Shipped. VLSM, IPv6, Converters,
  MAC Vendor Lookup (IEEE MA-L bundled).
- **Phase 2 — Lookup (per-host network tools).** ✅ Shipped. TCP Port Check,
  HTTP Header Inspector, TLS Certificate Inspector, What's My IP.
- **Phase 3 — Diagnostics + Discovery (sandbox-constrained).** ⏳ Planned.
  DNS Lookup (custom wire-format codec, UDP + TCP fallback), Ping (ICMP), and the
  hero **LAN Scanner** (sweep → ARP via `sysctl` → reverse-DNS + Bonjour + OUI).
  Traceroute is deliberately omitted (iOS sandbox makes TTL-limited probes
  unreliable).

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
