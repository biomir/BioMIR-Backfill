#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
required_tests = [
    root / "BioMIRBackfillTests/CSVParserTests.swift",
    root / "BioMIRBackfillTests/SourceFingerprintTests.swift",
    root / "BioMIRBackfillTests/CalendarIntervalTests.swift",
]
required_prod = [
    root / "BioMIRBackfill/Core/CSV/CSVModels.swift",
    root / "BioMIRBackfill/Core/CSV/CSVParser.swift",
    root / "BioMIRBackfill/Core/CSV/SourceDocumentService.swift",
    root / "BioMIRBackfill/Core/Audit/SourceFingerprint.swift",
]
missing_tests = [str(p.relative_to(root)) for p in required_tests if not p.exists()]
missing_prod = [str(p.relative_to(root)) for p in required_prod if not p.exists()]
if missing_tests:
    print("TASK 2 TEST STRUCTURE: FAIL")
    print("Missing tests:", *missing_tests, sep="\n - ")
    sys.exit(1)
if missing_prod:
    print("TASK 2 STRUCTURE: FAIL (expected RED before implementation)")
    print("Missing production files:", *missing_prod, sep="\n - ")
    sys.exit(1)
print("TASK 2 STRUCTURE: PASS")
