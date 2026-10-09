#!/usr/bin/env python3
import csv
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "build_carbmanager_total_carbs.py"


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="")


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        cm = td / "cm.csv"
        missingness = td / "nutrition.csv"
        out = td / "out"
        write(
            cm,
            ",2021-03-11,2021-03-12,2021-03-13\n"
            "Net Carbs (g),10.1,20,0\n"
            "Fiber (g),5.2,3,0\n"
            "Sugar Alcohols (g),1.3,2,0\n"
            "Allulose (g),0.4,4,0\n",
        )
        write(
            missingness,
            "Date,Dietary Calories (kCal),Fiber (g)\n"
            "2021-03-11,1000,5.2\n"
            "2021-03-12,1100,3\n"
            "2021-03-13,,\n",
        )
        subprocess.run(
            [
                "python3", str(BUILDER), str(cm), str(missingness),
                "--start", "2021-03-11", "--end", "2021-03-13",
                "--output-dir", str(out),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        target = out / "BioMIR_CarbManager_TotalCarbohydrates_20210311_20210313.csv"
        with target.open(newline="", encoding="utf-8") as f:
            records = list(csv.DictReader(f))
        assert list(records[0]) == ["Date", "Carb Manager Total Carbohydrates (g)"]
        assert records[0]["Carb Manager Total Carbohydrates (g)"] == "17"
        assert records[1]["Carb Manager Total Carbohydrates (g)"] == "29"
        assert records[2]["Carb Manager Total Carbohydrates (g)"] == ""

        evidence = out / "BioMIR_CarbManager_TotalCarbohydrates_20210311_20210313_evidence.csv"
        with evidence.open(newline="", encoding="utf-8") as f:
            ev = list(csv.DictReader(f))
        assert ev[0]["Allulose (g)"] == "0.4"
        assert ev[0]["Total Carbohydrates (g)"] == "17"
        assert ev[2]["Status"] == "MISSING_SOURCE"

        provenance = json.loads((out / "BioMIR_CarbManager_TotalCarbohydrates_20210311_20210313_provenance.json").read_text())
        assert provenance["formula"] == "Net Carbs + Fiber + Sugar Alcohols + Allulose"
        assert provenance["mappingVersion"] == "carbmanager-total-carb-v1"
        assert provenance["transformationID"] == "carbmanager-total-carb-reconstruction-v1"
        assert provenance["importableCount"] == 2
        assert provenance["missingCount"] == 1
        assert provenance["alluloseNonzeroCount"] == 2
        assert provenance["outputCSV_SHA256"]
        assert provenance["carbManagerReportSHA256"]
        assert provenance["missingnessSourceSHA256"]

    print("CARB MANAGER TOTAL-CARB BUILDER TEST: PASS")


if __name__ == "__main__":
    main()
