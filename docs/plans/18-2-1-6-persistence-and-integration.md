# 18-2-1-6: Persistence and integration

**Parent:** [18-2-1-m1-infantry-defense](18-2-1-m1-infantry-defense.md)
**Status:** completed
**Goal:** Preserve individual M1 equipment through campaign transitions and verify the completed infantry-defense mechanics together in Harbor.

## Delivery boundary

Continue on `codex/m1-section-6` from published section 5 (`ece3cd7`). Sections 1–5 are implemented and verified. This checkpoint completes the planned M1 persistence/integration scope; broader domain roles, urban actions, grenade replenishment, human balance and hardware performance remain separate work.

## Implementation parts

| Part | Work | Acceptance |
|---|---|---|
| 1. Campaign inventory | Version 3 snapshots and restores per-member frag/smoke stock through deployment, withdrawal/victory/defeat, parked units and retry. | Release spends once; interrupted preparation spends nothing; explicit empty/zero stock stays empty and casualties cannot donate or recreate equipment. |
| 2. Save migration and validation | Upgrade version-1/2 rosters and nested retry checkpoints, including engineers defined in field-unit data. Validate version-3 inventories before loading. | Missing legacy inventory gets a one-time compatible default; present legacy stock remains authoritative. Malformed current saves follow the existing recovery/blocking behavior. |
| 3. Integrated encounter and handoff | Exercise covering, throws/smoke, reserve support and staged work together on actual Harbor terrain; run the affected regression gate and native review. | Physical actions and observations agree, accepted replacements release ownership without deleting committed world effects, outcomes retain stock, and evidence records the exact final sources. |

## Tasks

- [x] 1. Fetch current branches, retain the section 5 baseline and create a separate branch.
- [x] 2. Implement version-3 snapshot/restore and legacy migration with focused persistence checks.
- [x] 3. Verify corruption handling, empty inventories, casualties, retry and campaign scene transitions.
- [x] 4. Build and verify the combined Harbor defense encounter through ordinary command APIs/input.
- [x] 5. Inspect current native presentation and run the affected M1/campaign/integration gate.
- [x] 6. Update tracking, architecture, player guidance and current evidence; distinguish functional completion from open human/performance gates.
- [x] 7. Commit and publish the separate section 6 checkpoint on `codex/m1-section-6`.

## Decisions

- Preserve the operational checkpoint boundary: actor claims/tasks, preparations, released payloads, smoke, support requests, orders and tactical field works remain transient.
- Initialize missing legacy stock once during migration. Do not grant new inventory when a version-3 record explicitly carries none, and do not add a replenishment service.
- Use the reviewed section 1–5 executors and real Harbor geometry for integration. A deterministic encounter verifies mechanisms; it does not establish complete mission pacing or human balance.
- Publish code, tests, documentation and verification metadata. Native review images remain local, consistent with the previous checkpoints.

## Verification

Godot **4.5.1.stable.official.f62fdbde1**. The three new focused suites pass **209 checks**:

| Suite | Checks | What it establishes |
|---|---:|---|
| `test_m1_persistence.gd` | 123 | Actual preparation/release, exact holder stock, empty/partial inventories, casualties, parked units, version-1/2 and mixed-version retry migration, engineer definitions, corruption recovery, failed writes and exact retry. |
| `test_m1_campaign_flow.gd` | 29 | Real Battle input, canceled/released throws, atlas withdrawal to another operation, disk startup, victory, defeat and retry. Terminal outcomes are controlled fixtures; scene transitions and persistence are real. |
| `test_m1_defense.gd` | 57 | One continuous encounter on authored Harbor geometry, real covering fire during concurrent digging/frag preparation, physical payloads and smoke, reserve service/return, interrupted work and one paid upgrade. |

The corrected Harbor encounter lasts **33.73 simulated seconds**. It records one covering shot during concurrent work/preparation, fifteen reserve shots, three enemy shots, **4.27 seconds of useful reserve service**, physical return to the original guard, and **1,012 claim samples with zero ownership errors**. One frag and one smoke are released; every member's inventory balances against its own authoritative release events. Smoke blocks the original optical lane in both directions and expires. The same site reaches stage 2 after one 50-supply charge, including duplicate requests and interruption/resumption.

[Native review](../evidence/m1-06-native-review.json) passes **223 checks across eight inspected captures**, including normal and largest UI scale, concurrent roles, released effects, reserve return, hasty cover and paused/resumed reinforcement. All 103 native source hashes match prelaunch, process start/end and postrun. Screenshots remain local; metadata and the reproducible fixture are committed.

The first native run exposed different fixture initialization: unpopulated headless IDs 1–4 versus Battle's naturally populated IDs 63–66 shifted automatic review timing. The reserve then lost two soldiers and correctly withdrew under pressure before earning four seconds of service. The shared fixture now follows populated Harbor initialization, and the requesting engineer returns fire through its normal policy when the enemy does. Health, geometry, work progress, service thresholds and completion are not forced. The initial failed review is retained as provenance rather than reported as current acceptance.

The final affected gate passes **34/34 suites in 360 seconds**, with **1,045 M1 checks** across thirteen suites, no assertion/script failures, and all 315 recorded sources unchanged between prelaunch, completion and evidence generation. [Functional evidence](../evidence/m1-06-checks.json) contains the exact selection, outputs and hashes. The inherited Harbor crowd-spacing regression and synchronous navigation hitch remain separately documented follow-ups; thresholds and unrelated behavior are unchanged. Functional/native acceptance does not establish human balance, full-mission pacing or supported-hardware performance.
