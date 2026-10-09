#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from datetime import datetime, timezone

EXPECTED_ROWS = 1400
EXPECTED_START = "2021-03-11"
EXPECTED_END = "2025-01-08"
DEFAULT_SMOKE_COLUMN = "Sodium (mg)"
DEFAULT_SMOKE_ROWS = 2


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare BioMIR Backfill Task 9 local device-validation artifacts.")
    parser.add_argument("source", type=Path, help="Personal 1,400-day nutrition CSV. Never copied into the repository.")
    parser.add_argument("--output-dir", type=Path, required=True, help="Local output directory outside the repository.")
    parser.add_argument("--smoke-column", default=DEFAULT_SMOKE_COLUMN)
    parser.add_argument("--smoke-rows", type=int, default=DEFAULT_SMOKE_ROWS)
    args = parser.parse_args()

    source = args.source.expanduser().resolve()
    out = args.output_dir.expanduser().resolve()
    if not source.is_file():
        raise SystemExit(f"ERROR: source file not found: {source}")
    if args.smoke_rows < 1 or args.smoke_rows > 10:
        raise SystemExit("ERROR: --smoke-rows must be 1...10")

    data = source.read_bytes()
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise SystemExit(f"ERROR: source must be UTF-8/UTF-8-BOM: {exc}") from exc

    rows = list(csv.DictReader(text.splitlines()))
    if not rows:
        raise SystemExit("ERROR: source contains no data rows")
    headers = list(rows[0].keys())
    if "Date" not in headers:
        raise SystemExit("ERROR: source is missing exact Date header")
    if args.smoke_column not in headers:
        raise SystemExit(f"ERROR: smoke column is absent: {args.smoke_column}")
    if len(rows) != EXPECTED_ROWS:
        raise SystemExit(f"ERROR: expected {EXPECTED_ROWS} rows; found {len(rows)}")
    if rows[0]["Date"] != EXPECTED_START or rows[-1]["Date"] != EXPECTED_END:
        raise SystemExit(
            f"ERROR: expected date range {EXPECTED_START}...{EXPECTED_END}; "
            f"found {rows[0]['Date']}...{rows[-1]['Date']}"
        )

    smoke = []
    for row in rows:
        raw = (row.get(args.smoke_column) or "").strip()
        if not raw:
            continue
        try:
            value = float(raw)
        except ValueError:
            continue
        if value <= 0:
            continue
        smoke.append({"Date": row["Date"], args.smoke_column: raw})
        if len(smoke) == args.smoke_rows:
            break
    if len(smoke) != args.smoke_rows:
        raise SystemExit(f"ERROR: could not find {args.smoke_rows} positive observed values for {args.smoke_column}")

    out.mkdir(parents=True, exist_ok=True)
    smoke_path = out / "Task9_Smoke_FirstObserved.csv"
    with smoke_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["Date", args.smoke_column], lineterminator="\n")
        writer.writeheader()
        writer.writerows(smoke)

    smoke_bytes = smoke_path.read_bytes()
    manifest = {
        "generatedAtUTC": datetime.now(timezone.utc).isoformat(),
        "sourceFilename": source.name,
        "sourceSHA256": sha256_bytes(data),
        "sourceByteCount": len(data),
        "sourceRowCount": len(rows),
        "sourceDateStart": rows[0]["Date"],
        "sourceDateEnd": rows[-1]["Date"],
        "sourceHeaderCount": len(headers),
        "smokeFilename": smoke_path.name,
        "smokeSHA256": sha256_bytes(smoke_bytes),
        "smokeColumn": args.smoke_column,
        "smokeRowCount": len(smoke),
        "smokeDates": [r["Date"] for r in smoke],
        "privacyNote": "Personal source and smoke CSV are local validation inputs and must not be committed to Git."
    }
    manifest_path = out / "Task9_Source_Manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    run_sheet = out / "Task9_Run_Sheet.md"
    run_sheet.write_text(
        "# BioMIR Backfill Task 9 — Physical Device Run Sheet\n\n"
        "Status: IN PROGRESS — do not mark validated until every required gate below is evidenced.\n\n"
        "## Source control\n"
        f"- Source filename: `{source.name}`\n"
        f"- Source SHA-256: `{manifest['sourceSHA256']}`\n"
        f"- Rows: {len(rows)}\n"
        f"- Date range: {rows[0]['Date']} through {rows[-1]['Date']}\n"
        f"- Smoke fixture: `{smoke_path.name}` ({len(smoke)} rows, `{args.smoke_column}` only)\n"
        f"- Smoke SHA-256: `{manifest['smokeSHA256']}`\n\n"
        "## Gate 9A — device build, authorization, full-source dry preflight\n"
        "- [ ] Physical iPhone model recorded\n"
        "- [ ] iOS version/build recorded\n"
        "- [ ] App version/build recorded\n"
        "- [ ] HealthKit availability confirmed\n"
        "- [ ] Intended nutrition read/write authorization requested\n"
        "- [ ] Full 1,400-day CSV selected\n"
        "- [ ] Review shows expected SHA/date range/row count\n"
        "- [ ] Dry preflight completed\n"
        "- [ ] Eligible / existing-visible / missing / zero-policy / auth-blocked counts recorded\n"
        "- [ ] Read-visibility warning state recorded\n"
        "- [ ] STOP before full write\n\n"
        "## Gate 9B — two-row controlled write\n"
        "- [ ] Smoke CSV selected and reviewed\n"
        "- [ ] Smoke preflight completed\n"
        "- [ ] Import explicitly confirmed\n"
        "- [ ] Imported count reconciles\n"
        "- [ ] Exact post-write verification completed\n"
        "- [ ] Audit bundle exported and hashes retained\n"
        "- [ ] Same smoke CSV rerun: application-authored records are not written again\n"
        "- [ ] No delete/replace/rollback operation used\n\n"
        "## Gate 9C — full historical import\n"
        "Proceed only after Gate 9A and 9B pass with no unexplained deviation.\n"
        "- [ ] Re-select original full CSV\n"
        "- [ ] Source SHA-256 unchanged from Gate 9A\n"
        "- [ ] Fresh preflight reviewed and acknowledged\n"
        "- [ ] Full import explicitly confirmed\n"
        "- [ ] Bounded batches completed or controlled interruption/resume evidenced\n"
        "- [ ] Final verification reconciles every imported sample exactly\n"
        "- [ ] Re-run preflight confirms app-authored records are no longer eligible for duplicate write\n"
        "- [ ] Final audit bundle exported and SHA-256 manifest verified\n"
        "- [ ] Validation report completed\n\n"
        "## Stop conditions\n"
        "Stop immediately for source-hash/schema/mapping drift, materially narrower authorization, verification mismatch, unexpected type/unit behavior, audit-persistence failure, or an unclassified HealthKit error.\n",
        encoding="utf-8"
    )

    print("TASK 9 SOURCE PREPARATION: PASS")
    print(f"Source: {source}")
    print(f"SHA-256: {manifest['sourceSHA256']}")
    print(f"Rows/date range: {len(rows)} / {rows[0]['Date']}...{rows[-1]['Date']}")
    print(f"Smoke fixture: {smoke_path}")
    print(f"Smoke SHA-256: {manifest['smokeSHA256']}")
    print(f"Run sheet: {run_sheet}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
