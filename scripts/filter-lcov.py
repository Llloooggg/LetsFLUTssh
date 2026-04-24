#!/usr/bin/env python3
"""Strip generated + localisation files from an lcov report in place.

`flutter test --coverage` writes `coverage/lcov.info` listing every
`lib/` file it saw. Drift `*.g.dart` and the 15 `l10n/app_localizations_*.dart`
files together add ~15 K lines that no unit test can reasonably
cover — keeping them inflates the denominator and masks real gaps.

Exclude patterns below must match `sonar-project.properties` →
`sonar.coverage.exclusions` so the local `make test` coverage
number and the SonarCloud dashboard agree.

Usage:
    python3 scripts/filter-lcov.py coverage/lcov.info
"""

from __future__ import annotations

import fnmatch
import sys
from pathlib import Path

# Mirror of sonar.coverage.exclusions. Keep synchronised.
EXCLUDE_PATTERNS = [
    "lib/l10n/*",
    "lib/l10n/**",
    "*.g.dart",
    "*.freezed.dart",
]


def should_exclude(path: str) -> bool:
    for pat in EXCLUDE_PATTERNS:
        if fnmatch.fnmatch(path, pat):
            return True
        # fnmatch does not honour `**` across slashes — emulate by
        # matching the suffix pattern against every path.
        if pat.endswith(".dart") and path.endswith(pat.lstrip("*")):
            return True
    return False


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <path-to-lcov.info>", file=sys.stderr)
        return 2
    lcov_path = Path(argv[1])
    if not lcov_path.exists():
        # Tests ran with --no-coverage or the file was cleaned. Nothing
        # to filter; silently exit so the Makefile target does not
        # fail on a clean checkout.
        return 0

    text = lcov_path.read_text(encoding="utf-8")
    records = text.strip().split("end_of_record\n")
    kept: list[str] = []
    dropped = 0
    for record in records:
        record = record.strip()
        if not record:
            continue
        source_line = next(
            (line for line in record.splitlines() if line.startswith("SF:")),
            None,
        )
        if source_line is None:
            continue
        path = source_line[3:].strip()
        if should_exclude(path):
            dropped += 1
            continue
        kept.append(record + "\nend_of_record\n")

    lcov_path.write_text("".join(kept), encoding="utf-8")
    print(f"filter-lcov: kept {len(kept)} records, dropped {dropped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
