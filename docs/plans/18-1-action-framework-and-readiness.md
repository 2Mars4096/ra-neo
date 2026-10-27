# 18-1: Action framework and readiness

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Give every action clear prerequisites, ownership, interruption and completion while removing avoidable hesitation in current units.

## Baseline and evidence

[Simulation](../../scripts/simulation.gd) currently distributes behavior across `orders`, `intent`, `maneuver`, target/aim state, cover phases and regroup flags. [TacticalDirector](../../scripts/tactical_director.gd) retains player intent during temporary maneuvers. [Infantry](../../scripts/infantry.gd) and [Cover](../../scripts/cover_behavior.gd) manage additional commitments. Extend these in small adapters; do not replace the whole simulation at once.

Static review findings to reproduce before changing behavior:

- `infantry_combat` starts reloads after target, movement and posture gates; a quiet empty weapon can stay unprepared.
- Vehicle acquisition keeps a valid target before ranking new threats; an urgent aircraft need not preempt an existing ground target.
- Infantry target-section changes reset aim; candidate ordering can spend the line-check budget before reaching an explicit target.
- `Infantry.capacity` excludes down/dead members. It is appropriate for some recovery bookkeeping but does not measure losses against assigned strength.
- `contact_drill` can keep a contact hold ahead of the separate high-suppression withdrawal rule.
- The AT launcher and cover-role helper identify the operator by member index zero, rather than transferable equipment.

These are source/control-flow findings, not newly reproduced runtime bugs or measured slowdowns.

## Proposed state contract

| Record | Minimum fields and purpose |
|---|---|
| Order/assignment | Stable identity, issuer, player-intent version, objective/target, engagement permission, permitted autonomy, boundary, priority, spending permission and completion policy |
| Capability | Living/available members, equipment ownership, ammunition, mobility/firepower condition, required crew, activity exclusions and service eligibility |
| Situation | Observed contacts and age/confidence, known hazards, nearby support readiness, useful positions, geometry version and current resources |
| Action instance | Action ID, owner, originating order version, target snapshot, phase, reserved roles/positions/resources, start/deadline, reason, fallback and completion outcome |
| Result/event | Tick, stable event ID, known-to teams/actors, state change, completion/failure reason and invalidated cached facts |

Fields are a proposed contract, not implemented classes. Use typed small records at module boundaries before introducing new modules. Initial candidate modules, if justified during implementation, are an action registry, executor and tactical context beside the existing scripts; final filenames are not fixed by this plan.

## Lifecycle and decision policy

An action moves through candidate, reserved, preparing, executing, recovering and completed/failed/cancelled states. Reservation must be atomic: two soldiers cannot claim one firing slot, one grenade or one specialist item. Interrupted preparation releases unused reservations. Released ordnance and other irreversible world effects finish under simulation ownership; cancelling a soldier action does not erase them or refund consumed items.

Separate a received replacement order from executor-owned child movement. Only a valid replacement order increments the player-intent version; an internal reposition/approach retains its parent assignment and has its own action/route identity. Provide an intent-preserving internal movement path rather than reusing `record_order` unchanged. Multiple child movements must not cancel their own escort, service or support task.

Engagement permission is authoritative and checked before scoring and immediately before weapon/payload commitment. Hold fire suppresses autonomous damaging or revealing releases, including automatic smoke; an explicit attack/throw grants permission only for that requested action, then the standing policy resumes. Emergency target priority does not silently override Hold fire. Local posture, observation and allowed movement can still respond; any self-defense exception must be an explicit player policy.

Evaluate the explicit target first, the viable current action next, then a small ranked shortlist. Rank contribution to intent, useful effect, urgency, exposure, support availability, resource cost and switching cost. Apply hard capability/geometry/information constraints before scoring. Use deterministic tie-breaking and thresholds so near-equal options do not cause aim or posture churn.

Player orders replace obsolete intent immediately after valid receipt. Within the selected initiative policy, known immediate danger may interrupt a temporary action; ordinary opportunities respect minimum commitment. A hard Hold keeps its established position constraint while allowing legal local posture, aim and reload. Do not silently turn it into autonomous long-distance retreat. Severe danger under hard Hold produces a concise alert when relocation is disallowed.

Separate original/assigned strength, current effective strength and recoverable condition. Losses, specialist availability and support determine willingness to continue; medical restoration remains tied to actual survivors. Original strength does not reset merely because a casualty disappears from the effective roster.

## Tasks

- [ ] 1. Reproduce the readiness, target-priority and strength cases using small fixtures; record intentional old behavior separately from defects.
- [ ] 2. Add order/assignment versions, capability views and a minimal action contract around existing reload/aim/cover executors.
- [ ] 3. Move reload readiness outside target acquisition; coordinate magazine timing through section-role reservations in [18-2](18-2-infantry-fire-and-movement.md).
- [ ] 4. Apply explicit-target-first validation, stable aim tracking and a cheap urgent-threat override; retain actual weapon acquisition requirements.
- [ ] 5. Unify interruption precedence for contact holds, withdrawal, aid, digging, throwing and direct orders; add bounded failure backoff and a valid temporary action.
- [ ] 6. Separate assigned strength and equipment identity from healing capacity/member array indices; provide the handover interface without automatically completing a transfer.
- [ ] 7. Add event invalidation and bounded work scheduling with [18-12](18-12-performance-and-validation.md), plus compact state reasons with [18-11](18-11-command-interface-and-feedback.md).
- [ ] 8. Adapt one action at a time, proving old mission, collision, casualty and campaign invariants before broad adoption.

## Integration slices

**M0:** reload/targeting/strength and action traces on the existing roster. **M1:** reserve one throw, one cover role and one support request; interruption leaves no orphan reservations. **M2 onward:** reusable vehicle/air/sea action adapters. Resource durability belongs to [18-10](18-10-logistics-medical-and-recovery.md); observations to [18-9](18-9-information-and-electronic-warfare.md); support task ownership to [18-4](18-4-coordination-and-support-requests.md).

No per-soldier unbounded planner is needed. The first executor can remain single-threaded with deterministic work limits. Background work, if later justified, returns proposals tagged by order/geometry version for validation on the simulation thread.

## Acceptance scenarios

- An empty soldier reloads during a quiet interval, then responds to contact without an avoidable extra reload; another available member maintains coverage.
- An AA vehicle retains an ordinary target until a genuinely urgent known air threat arrives; a short-lived marginal alternative does not produce repeated switching.
- The player's infantry target is evaluated before incidental targets exhaust line checks.
- A three-person section with one healthy survivor is recognized as depleted; ordinary recovery never resurrects lost members or resets loss history.
- Cancelling a prepared throw, revoking a work order, losing a supporter and destroying a target each release exactly the appropriate reservations; released effects persist.
- An old route/result cannot overwrite a newer order. Same seed/input yields the same authoritative decisions regardless of camera view or render rate.
- Several executor-owned repositionings preserve an escort assignment; one received player replacement cancels it. An urgent threat under Hold fire changes awareness but does not release a weapon until a scoped permission exists.

## Decisions

- Keep the existing 30 Hz authoritative simulation until profiling establishes a need to change it; responsiveness comes from useful event handling and less wasted work.
- Diagnostic reasons are structured codes with short display text. UI wording is not authoritative action state.
- Reserve resources before execution, consume at a defined commitment point, and delegate refund/restock rules to the shared ledger.

## Notes

Placeholder presentation: existing posture/weapon/route cues plus a small action icon. New animation quality is not a prerequisite for validating state ownership, but native review must establish that start, interruption and completion are visible.
