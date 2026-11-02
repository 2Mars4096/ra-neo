# 18-2-1-4: Hasty positions and engineer upgrades

**Parent:** [18-2-1-m1-infantry-defense](18-2-1-m1-infantry-defense.md)
**Status:** completed
**Goal:** Let one infantry member prepare local cover and an engineer reinforce the same site, preserving work and payment through interruptions.

## Delivery boundary

Continue from completed section 3 (`57f7fa8`) on `codex/m1-section-4`. Recover the section 4 implementation from `3ce3b99` without replacing sections 1–3 corrections or importing section 5 controls. Contextual keys/buttons remain section 5; campaign inventory and integrated mission acceptance remain section 6.

## Implementation sections

- [x] 1. Recover the field-position executor, existing field-work adapters and staged procedural meshes.
- [x] 2. Verify soil, slope, whole-footprint clearance, local access and one-worker ownership.
- [x] 3. Verify real work progress, stage-specific protection, pressure pauses, casualties, replacement orders and resume.
- [x] 4. Verify the paid engineer upgrade, damage retention, cancellation/salvage and exclusive site ownership.
- [x] 5. Run focused M1 and affected field-work/order regressions; inspect native stage presentation.
- [x] 6. Update tracking/evidence and commit the reviewed checkpoint locally.
- [x] 7. Publish `codex/m1-section-4` at `8b6adb8`. Its code-only tree exactly matches tested local checkpoint `40b5f6d`; native screenshots remain local and unpublished.

## Behavior contract

- Rifle, AT and engineer sections can assign one available member to a nearby, clear, level 7 × 2 soil footprint. Free digging takes 18 seconds of actual work. Other members remain available.
- An unfinished survey grants no cover. A completed hasty position grants ordinary infantry cover and 120 maximum integrity.
- An engineer can spend the existing trench price (50 supply) once for ten seconds of work on that site. Completion grants dug-in protection and 320 maximum integrity. Incoming damage remains meaningful.
- Pressure releases the actor while retaining the job; accepted replacement orders end its authority. Interrupted sites retain earned progress and paid materials. Repeated current commands are idempotent.
- Free work cannot generate refunds. Paid cancellation/salvage uses only the materials actually purchased and cannot refund twice.
- Previews use known information; commitment and movement enforce actual geometry. Jobs are capped at 64, living sites at 96, with bounded approach and overall deadlines.

## Verification

Godot 4.5.1. Record current results in `docs/evidence/m1-04-checks.json`; historical staged-branch results are not acceptance for this checkpoint. Functional/native checks do not establish human balance or supported-hardware frame-time acceptance.

## Decisions and findings

- Recover the isolated `3ce3b99` implementation delta; the staged branch also contains section 5 and lacks later section 1–3 fixes.
- Keep the existing construction Resume/Cancel integration and simulation command APIs. Add no section 5 command controls in this checkpoint.

## Verified checkpoint

- All **248 field-position checks** pass: 151 base behavior, 81 lifecycle and 16 order/spacing checks. Together with retained sections 1–3, **715 M1 checks** pass.
- The affected regression selection passes **39/40 suites**. Its only remaining failure is the identical inherited Harbor crowd-spacing case at `(526, 690)` on unchanged `57f7fa8` (2.3 seconds against the 1.5-second limit). No threshold or unrelated combat behavior was changed.
- The final lifecycle suite reproduces 13 failures on the original candidate and none after correction; the order suite reproduces five failures before the spacing guards and none after. Final current work suites were rerun after the recovery correction.
- The obsolete field-visuals fake was replaced with real unpopulated simulation context; all 662,132 existing assertions pass without changing production animation or assertion criteria.
- Three [native captures](../evidence/m1-04-native-review.json) were inspected at 1280 × 720 in Godot 4.5.1 OpenGL/llvmpipe: survey, hasty earth and reinforced trench, using the same real Harbor site. The existing engineer reaches soil by normal movement, the rifle digs, and the engineer pays once and reinforces.

## Review corrections

- Ordinary engagement/unstack spacing cannot relocate the anchor while a local work job owns it; accepted player movement still replaces that work.
- Hull yielding and fresh wreck recovery pause work and release actor/site action claims, retaining earned progress. Leaving the work leash cancels stale ownership without teleporting the worker.
- Accepted work discards obsolete spacing/recovery goals. If a real recovery was active, it recomputes the still-required physical escape before allowing work to resume.
- Deadline/cap checks, repeated orders, rejected provisional placement, accepted queued movement, damage retention and paid/free refund behavior retain their invariants.
- Existing status text now reflects paused/completed work instead of keeping the preparation reason after completion.
