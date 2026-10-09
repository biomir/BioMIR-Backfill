#!/usr/bin/env python3
import argparse
import csv
import hashlib
import json
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path

REQUIRED_ROWS = (
    "Net Carbs (g)",
    "Fiber (g)",
    "Sugar Alcohols (g)",
    "Allulose (g)",
)
OUTPUT_COLUMN = "Carb Manager Total Carbohydrates (g)"
MAPPING_VERSION = "carbmanager-total-carb-v1"
TRANSFORMATION_ID = "carbmanager-total-carb-reconstruction-v1"
FORMULA = "Net Carbs + Fiber + Sugar Alcohols + Allulose"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def decimal_text(value: Decimal) -> str:
    if value == 0:
        return "0"
    text = format(value.normalize(), "f")
    return text.rstrip("0").rstrip(".") if "." in text else text


def date_range(start: date, end: date):
    current = start
    while current <= end:
        yield current
        current += timedelta(days=1)


def load_carb_manager(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.reader(f))
    if not rows or len(rows[0]) < 2:
        raise ValueError("Carb Manager report is empty or malformed")

    date_headers = rows[0][1:]
    if len(date_headers) != len(set(date_headers)):
        raise ValueError("Carb Manager report contains duplicate date columns")

    values = {}
    for row in rows[1:]:
        if not row:
            continue
        label = row[0].strip()
        if label in values:
            raise ValueError(f"Carb Manager report contains duplicate nutrient row: {label}")
        if len(row) != len(rows[0]):
            raise ValueError(f"Carb Manager row has wrong column count: {label}")
        values[label] = row[1:]

    missing = [name for name in REQUIRED_ROWS if name not in values]
    if missing:
        raise ValueError("Carb Manager report missing required rows: " + ", ".join(missing))

    return date_headers, values


def load_missingness(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or "Date" not in reader.fieldnames:
            raise ValueError("Missingness source must contain Date")
        non_date = [h for h in reader.fieldnames if h != "Date"]
        if not non_date:
            raise ValueError("Missingness source must contain at least one non-Date field")
        result = {}
        for row in reader:
            d = row["Date"].strip()
            if d in result:
                raise ValueError(f"Missingness source contains duplicate date: {d}")
            result[d] = all((row.get(h) or "").strip() == "" for h in non_date)
    return result


def parse_decimal(raw: str, label: str, day: str) -> Decimal:
    text = raw.strip()
    if text == "":
        raise ValueError(f"Blank {label} on non-missing date {day}")
    try:
        value = Decimal(text)
    except InvalidOperation as exc:
        raise ValueError(f"Invalid {label} value on {day}: {text}") from exc
    if not value.is_finite():
        raise ValueError(f"Non-finite {label} value on {day}: {text}")
    if value < 0:
        raise ValueError(f"Negative {label} value on {day}: {text}")
    return value


def build(cm_path: Path, missingness_path: Path, start: date, end: date, output_dir: Path):
    if end < start:
        raise ValueError("End date precedes start date")

    date_headers, cm_values = load_carb_manager(cm_path)
    index_by_date = {d: i for i, d in enumerate(date_headers)}
    missingness = load_missingness(missingness_path)
    expected_days = [d.isoformat() for d in date_range(start, end)]

    absent_cm = [d for d in expected_days if d not in index_by_date]
    absent_mask = [d for d in expected_days if d not in missingness]
    if absent_cm:
        raise ValueError(f"Carb Manager report missing {len(absent_cm)} target dates; first: {absent_cm[0]}")
    if absent_mask:
        raise ValueError(f"Missingness source missing {len(absent_mask)} target dates; first: {absent_mask[0]}")

    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = f"{start:%Y%m%d}_{end:%Y%m%d}"
    output_csv = output_dir / f"BioMIR_CarbManager_TotalCarbohydrates_{stamp}.csv"
    evidence_csv = output_dir / f"BioMIR_CarbManager_TotalCarbohydrates_{stamp}_evidence.csv"
    provenance_json = output_dir / f"BioMIR_CarbManager_TotalCarbohydrates_{stamp}_provenance.json"

    import_rows = []
    evidence_rows = []
    allulose_nonzero = 0
    importable = 0
    missing_count = 0
    totals = []

    for day in expected_days:
        if missingness[day]:
            import_rows.append({"Date": day, OUTPUT_COLUMN: ""})
            evidence_rows.append({
                "Date": day,
                "Net Carbs (g)": "",
                "Fiber (g)": "",
                "Sugar Alcohols (g)": "",
                "Allulose (g)": "",
                "Total Carbohydrates (g)": "",
                "Status": "MISSING_SOURCE",
            })
            missing_count += 1
            continue

        i = index_by_date[day]
        terms = {name: parse_decimal(cm_values[name][i], name, day) for name in REQUIRED_ROWS}
        total = sum(terms.values(), Decimal("0"))
        if terms["Allulose (g)"] != 0:
            allulose_nonzero += 1
        total_text = decimal_text(total)
        totals.append(total)
        importable += 1

        import_rows.append({"Date": day, OUTPUT_COLUMN: total_text})
        evidence_rows.append({
            "Date": day,
            "Net Carbs (g)": decimal_text(terms["Net Carbs (g)"]),
            "Fiber (g)": decimal_text(terms["Fiber (g)"]),
            "Sugar Alcohols (g)": decimal_text(terms["Sugar Alcohols (g)"]),
            "Allulose (g)": decimal_text(terms["Allulose (g)"]),
            "Total Carbohydrates (g)": total_text,
            "Status": "RECONSTRUCTED",
        })

    with output_csv.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["Date", OUTPUT_COLUMN])
        writer.writeheader()
        writer.writerows(import_rows)

    evidence_fields = [
        "Date", "Net Carbs (g)", "Fiber (g)", "Sugar Alcohols (g)", "Allulose (g)",
        "Total Carbohydrates (g)", "Status",
    ]
    with evidence_csv.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=evidence_fields)
        writer.writeheader()
        writer.writerows(evidence_rows)

    provenance = {
        "profile": "Carb Manager total carbohydrate reconstruction",
        "mappingVersion": MAPPING_VERSION,
        "transformationID": TRANSFORMATION_ID,
        "formula": FORMULA,
        "sourceWindowStart": start.isoformat(),
        "sourceWindowEnd": end.isoformat(),
        "rowCount": len(expected_days),
        "importableCount": importable,
        "missingCount": missing_count,
        "alluloseNonzeroCount": allulose_nonzero,
        "minimumTotalCarbohydrates_g": decimal_text(min(totals)) if totals else None,
        "maximumTotalCarbohydrates_g": decimal_text(max(totals)) if totals else None,
        "missingnessPolicy": "Blank output when every non-Date field is blank in the previously validated nutrition backfill source; Carb Manager zero-filled no-log dates are not treated as observed zeros.",
        "carbManagerReportFilename": cm_path.name,
        "carbManagerReportSHA256": sha256(cm_path),
        "missingnessSourceFilename": missingness_path.name,
        "missingnessSourceSHA256": sha256(missingness_path),
        "outputCSVFilename": output_csv.name,
        "outputCSV_SHA256": sha256(output_csv),
        "evidenceCSVFilename": evidence_csv.name,
        "evidenceCSV_SHA256": sha256(evidence_csv),
    }
    provenance_json.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print("CARB MANAGER TOTAL-CARB RECONSTRUCTION: PASS")
    print(f"Rows: {len(expected_days)}")
    print(f"Importable: {importable}")
    print(f"Missing: {missing_count}")
    print(f"Allulose nonzero: {allulose_nonzero}")
    print(f"Range g: {provenance['minimumTotalCarbohydrates_g']}...{provenance['maximumTotalCarbohydrates_g']}")
    print(f"Output: {output_csv}")
    print(f"Output SHA-256: {provenance['outputCSV_SHA256']}")
    print(f"Evidence: {evidence_csv}")
    print(f"Provenance: {provenance_json}")


def main():
    parser = argparse.ArgumentParser(description="Build a controlled Carb Manager total-carbohydrate backfill CSV.")
    parser.add_argument("carb_manager_report", type=Path)
    parser.add_argument("missingness_source", type=Path)
    parser.add_argument("--start", type=date.fromisoformat, default=date(2021, 3, 11))
    parser.add_argument("--end", type=date.fromisoformat, default=date(2025, 1, 8))
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    build(args.carb_manager_report, args.missingness_source, args.start, args.end, args.output_dir)


if __name__ == "__main__":
    main()
