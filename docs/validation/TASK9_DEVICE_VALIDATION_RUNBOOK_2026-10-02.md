# BioMIR Backfill Task 9 — Physical-Device Validation Runbook

Status: **PENDING PHYSICAL-DEVICE EXECUTION**

Baseline: validated Task-8 commit `ad4b32b`.

## Purpose

Validate the complete BioMIR Backfill workflow on a physical iPhone without expanding application scope. This task produces validation evidence only. Personal CSV/XML/Health exports and locally generated smoke inputs must not be committed.

## Controlled sequence

### Gate 9A — signed device build, authorization, and full-source dry preflight

1. Confirm repository is clean at the validated Task-8 baseline.
2. Run the complete simulator regression suite before device use.
3. Configure an Apple development team for the BioMIR Backfill target and install on a physical iPhone.
4. Record iPhone model, iOS version/build, BioMIR Backfill version/build, mapping version, parser version, and source timezone.
5. Select the 1,400-row historical nutrition CSV.
6. Confirm review shows the expected row count and date range `2021-03-11` through `2025-01-08` and capture the source SHA-256.
7. Request the controlled nutrition read/write authorization and run preflight.
8. Record eligible, existing-visible, missing, zero-policy, authorization-blocked, and unsupported counts plus the read-visibility warning state.
9. **STOP. Do not perform the full historical write yet.**

### Gate 9B — controlled two-row write

Use `tools/task9_prepare_validation.py` to create a two-row, one-nutrient CSV from the personal source itself. The fixture is generated outside the repository from observed positive source values so the write is a legitimate subset of the eventual history, not synthetic junk.

1. Select and review the generated smoke CSV.
2. Run preflight and explicitly acknowledge the reviewed results.
3. Explicitly confirm import.
4. Require exact Task-7 reconciliation before accepting `Verified Complete`.
5. Export the audit bundle and retain its SHA-256 manifest.
6. Re-select the identical smoke CSV and rerun preflight/import protection. The two application-authored records must not be written again.
7. Record all evidence and deviations. Do not use an app delete/replace/rollback operation.

### Gate 9C — full historical import

Proceed only after Gates 9A and 9B pass without unexplained deviation.

1. Re-select the original 1,400-row source.
2. Confirm its SHA-256 is unchanged from Gate 9A.
3. Run a fresh preflight and review it explicitly.
4. Confirm full import.
5. Import in bounded batches under the existing Task-6 coordinator.
6. Require exact Task-7 reconciliation for every successfully written sample.
7. Re-run preflight after import; application-authored records must be protected from repeat write.
8. Export the final audit bundle and verify its hash manifest.
9. Complete `VALIDATION_REPORT_v0.1.md` with actual device evidence.

## Stop conditions

Stop immediately if any of these occur:

- source SHA-256 changes after reviewed preflight;
- schema or mapping version differs from the reviewed state;
- authorization is materially narrower than expected;
- verification mismatch occurs;
- an unexpected HealthKit type/unit behavior occurs;
- audit ledger or journal persistence fails;
- HealthKit returns an unclassified error;
- the UI overstates read visibility or duplicate absence.

## Acceptance

Task 9 is not complete until the physical-device run demonstrates:

- signed device installation and intended HealthKit authorization;
- full-source dry preflight with explicit review;
- controlled two-row import with exact post-write verification;
- repeat-import protection for the application-authored two-row subset;
- controlled full historical import with exact reconciliation;
- final re-preflight and hashed audit export;
- no delete, replace, or rollback path used;
- personal health source files remain outside Git.
