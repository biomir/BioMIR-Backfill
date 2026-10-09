# Regulatory Readiness and Auditability

**Document version:** 0.1  
**Date:** 2026-10-02

## Current posture

BioMIR Backfill is presently intended as a personal wellness-data transfer utility. It is **not claimed to be**:
- a CLIA-certified laboratory system;
- an FDA-cleared/approved medical device;
- Software as a Medical Device (SaMD);
- a diagnostic or treatment-support product.

This document defines readiness controls, not regulatory status.

## Why regulated-readiness controls are being used

BioMIR development already applies change-control, provenance, deterministic processing, validation, and auditability concepts. The companion should preserve the same discipline so that future regulated-use assessment can reuse structured evidence rather than retrofitting it.

## Controlled boundaries

### Backfill owns
- source-file intake;
- deterministic parsing;
- semantic mapping;
- unit normalization;
- Apple Health collision preflight;
- user-authorized Health writes;
- provenance;
- post-write verification;
- audit export.

### Backfill does not own
- diagnostics;
- biological-age calculation;
- laboratory interpretation;
- clinical recommendations;
- treatment;
- measurement generation;
- BioMIR analytical engines.

## Change-control triggers requiring regulatory reassessment

Reassess intended use before implementing:
1. diagnostic claims;
2. therapeutic/treatment recommendations;
3. clinical decision support;
4. laboratory-result interpretation or generation;
5. risk prediction used for patient management;
6. direct clinical workflow integration;
7. automatic data transformation that changes clinical meaning;
8. new write support for clinical/laboratory data families;
9. autonomous AI affecting imported health values.

## Auditability controls

Every release should maintain:
- immutable release tag;
- reproducible build identifier;
- source and mapping version;
- requirements traceability;
- risk register;
- verification evidence;
- known-limitations document;
- compatibility matrix;
- dependency inventory/SBOM;
- change log.

Every import should maintain:
- source-file SHA-256;
- schema hash;
- parser version;
- mapping version;
- transformation version;
- batch identifiers;
- record dispositions;
- Health write results;
- verification results;
- audit-file hashes.

## Mapping-as-reagent principle

Mapping tables and conversion constants are controlled scientific/technical reagents.

A mapping change requires:
1. rationale;
2. version increment;
3. updated tests;
4. risk review;
5. traceability update;
6. validation evidence;
7. change-log entry.

No silent mapping change is permitted.

## CLIA-readiness boundary

The companion does not perform examination of human specimens. If future functionality begins accepting, calculating, interpreting, or reporting laboratory results in a manner tied to clinical testing, the CLIA applicability assessment must be reopened.

## SaMD/device-readiness boundary

The present utility moves data. If a future version performs diagnosis, treatment recommendation, clinical-risk assessment, or software functions intended for medical decision-making, the FDA/software-device assessment must be reopened before implementation.

## Quality-system compatibility

Use development practices compatible with future formalization under a medical-device QMS:
- documented requirements;
- risk management;
- configuration management;
- software verification and validation;
- defect control;
- release controls;
- traceability;
- lifecycle documentation.

Do not claim ISO 13485, ISO 14971, IEC 62304, FDA QMSR, CLIA, or other certification/compliance until those requirements have actually been implemented and independently determined applicable.
