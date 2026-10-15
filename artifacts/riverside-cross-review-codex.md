# Riverside cross-review — VFX and navigation

2026-10-14. Independent source/image review only; no source changes, test execution, native processes or timing. This note is the sole write. **No concrete remaining integration blocker found in the reviewed evidence.** This is not full visual or performance acceptance.

## Native VFX evidence

Inspected `effects-review-a4-fireball.png`, `effects-review-b1-splash-rise.png`, `effects-review-d2-events-kill.png` and their capture metadata. Effects are localized and the battlefield remains visible: no white sheets, screen-sized cards or obvious rectangular card backgrounds in these frames. The Riverside capture shows both land and water destruction effects at the far-east shore.

Actual visual weaknesses: the a4 fireball reads as a fairly flat saturated-orange mass with limited internal shading; its long missile trail shows repeated discrete puffs. The b1 splash crown is small and white with little internal detail; the smaller strikes primarily read as rings. The d2 kill cores are clipped white and briefly obscure the immediate impact locations. These are polish/readability limits, not evidence of the former projection failure. Still images cannot establish smooth progression, lifetime, camera-motion stability or transparent-particle ordering in motion.

Reviewed `effects.gd`, all three effect shaders, `battle.gd::consume_events`, and the isolated pixel-test source. Current checked-in code builds camera-facing card/streak bases on the CPU and uses ordinary shader vertex transforms; it no longer contains a `PROJECTION_MATRIX[1][1]` division. Thus the reported `abs(...)` correction describes an earlier/intermediate implementation, not a line independently verified in this snapshot. The reported 1,345 changed pixels is lead-supplied evidence, not a rerun here. The isolated test accepts 30–72,000 changed pixels in an 800×600 view: useful protection against disappearance/full-screen coverage, not visual-quality proof. Retain native captures alongside headless checks.

Event integration gates shot/destruction effects on `event.visible`, passes terrain-derived launch/impact water status and target kind, and clears consumed events. Water misses dispatch spray/foam; vehicle deaths dispatch fireball plus water or ground treatment. Card alpha masks and live-content bounds are present. No source evidence of gameplay damage being applied by the presentation layer.

## Navigation evidence

`simulation.gd::attack_position` now gathers traversable firing candidates within 90% weapon range, checks ground-target sight, sorts by distance from the attacker, and accepts only a nonempty path using the attacker's domain, radius and mobility profile. Exhaustion returns (-1,-1); the caller's route rejection prevents replacing orders with an invalid route. Direct attack retains the exact target ID. This addresses the documented geometrically-near but disconnected HQ pocket without shrinking clearance.

`test_classic_navigation.gd` exercises the blocked HQ arrangement, verifies the selected position has a tracked tank route, accepts the explicit attack and preserves target identity. Its saved log reports **8 checks, 0 failures**, selecting **(51,15)**; the disclosed-base rifle observes HQ at **12.1 s**. Independently read `classic-integrated-playthrough.log`: **VICTORY at 371.9 s**, two friendly structures and zero enemy structures. These are existing integration results, not fresh runs by this reviewer.

Limits: the focused pocket test proves route availability/order acceptance, not tank arrival by itself; the full playthrough supplies broader existing evidence. Candidate path queries are not bounded by a small attempt count, so this review makes no command-latency/scaling claim. No measured regression justifies calling that a blocker. Native VFX acceptance across renderers/zoom and final performance acceptance remain outside this review.
