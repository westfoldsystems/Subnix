#!/usr/bin/env python3
"""
Regenerate Subnix/oui-mal.tsv from the official IEEE MA-L (OUI) registry.

Run before a release to refresh the bundled MAC-vendor database. The app stays
fully offline — this only regenerates the file that ships inside the bundle.

    python3 Tools/refresh_oui.py                 # download from IEEE, overwrite the bundled file
    python3 Tools/refresh_oui.py oui.csv         # convert a local CSV instead
    python3 Tools/refresh_oui.py oui.csv out.tsv # explicit output path

The IEEE CSV columns are: Registry, Assignment, Organization Name, Organization
Address. We keep MA-L rows, take Assignment (6 hex) + Organization Name, collapse
internal whitespace, and emit "ASSIGNMENT<TAB>Organization" sorted by assignment.
"""
import csv
import io
import os
import sys
import urllib.request

SOURCE = "https://standards-oui.ieee.org/oui/oui.csv"
MIN_ROWS = 10_000  # sanity floor — refuse to overwrite with a truncated/garbage file
DEFAULT_OUT = os.path.join(os.path.dirname(__file__), "..", "Subnix", "oui-mal.tsv")


def load(src: str) -> str:
    if src.startswith(("http://", "https://")):
        req = urllib.request.Request(src, headers={"User-Agent": "octet-oui-refresh"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read().decode("utf-8", errors="replace")
        except urllib.error.URLError as e:
            reason = getattr(e, "reason", e)
            sys.exit(
                f"Download failed: {reason}\n"
                "If you're behind a TLS-intercepting proxy (or offline), download the\n"
                "CSV yourself and pass its path:\n"
                f"    curl -o oui.csv {SOURCE}\n"
                "    python3 Tools/refresh_oui.py oui.csv"
            )
    with open(src, encoding="utf-8", errors="replace") as f:
        return f.read()


def convert(csv_text: str) -> dict[str, str]:
    rows: dict[str, str] = {}
    reader = csv.reader(io.StringIO(csv_text))
    next(reader, None)  # header
    for row in reader:
        if len(row) < 3:
            continue
        registry, assignment, org = row[0].strip(), row[1].strip().upper(), row[2].strip()
        if registry != "MA-L" or len(assignment) != 6:
            continue
        if not all(c in "0123456789ABCDEF" for c in assignment) or not org:
            continue
        rows[assignment] = " ".join(org.split())  # collapse internal whitespace
    return rows


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else SOURCE
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT

    rows = convert(load(src))
    if len(rows) < MIN_ROWS:
        sys.exit(f"Refusing to write: only {len(rows)} MA-L rows parsed "
                 f"(expected >= {MIN_ROWS}). Source may be malformed.")

    with open(out, "w", encoding="utf-8") as f:
        f.write("# IEEE MA-L (OUI) registry — Assignment<TAB>Organization Name\n")
        f.write(f"# Source: {SOURCE}\n")
        for assignment in sorted(rows):
            f.write(f"{assignment}\t{rows[assignment]}\n")

    print(f"Wrote {len(rows)} assignments to {os.path.normpath(out)}")


if __name__ == "__main__":
    main()
