# Info.plist, entitlements & bundled-data setup

Lantern is local-only. This file is the single place that records every
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

**Phase 1 tools make zero network calls.** Everything is pure on-device compute
or reads from a bundled file.

The first and only deliberate external call arrives in Phase 2 with **What's My
IP** (public-IP reflection). When it lands it must be listed here with its exact
endpoint, be opt-in (a tap, never automatic), and be labelled in-UI. Until then
there is nothing to disclose.

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
