# 18-2-1-1: Coordinated cover and movement

**Parent:** [18-2-1: M1 infantry defense](18-2-1-m1-infantry-defense.md)
**Status:** completed
**Goal:** Let infantry cover a teammate's short move to shelter with a real, available weapon while preserving player orders and individual action ownership.

## Scope and baseline

The current delivery implements and reviews section 1 only on `codex/m1-section-1`. Existing checkpoint `0f5eb25` supplies the initial implementation over M0 `5850504` and the plan-only commit `b94593a`; this branch reuses that work and corrects its combat integration. The initial plan checkpoint was published at `14caa85`, followed by the verified implementation. M1.2–M1.6 remain outside this checkpoint.

## Tasks

- [x] 1. Divide M1 into six dependent implementation sections in the parent plan.
- [x] 2. Reuse M1.1 reciprocal coverer/mover roles, actual weapon/visibility eligibility and alternate-magazine readiness.
- [x] 3. Preserve the coverer's position and loaded magazine; replace unavailable support or let an exposed mover finish its validated shelter route.
- [x] 4. Exclude task-owned actors from ordinary movement, firing, reload and medical work; release cooperation on accepted replacement commands.
- [x] 5. Review movement, support release and player-order integration; make actual combat honor the assigned covering threat/weapon and release support on explicit or urgent preemption.
- [x] 6. Run focused coordination and affected regression suites on this branch; record current results and verify the new tests detect the original defects.
- [x] 7. Update tracking, commit and push the section 1 checkpoint.

## Acceptance

| Situation | Required behavior |
|---|---|
| One soldier moves, another covers | The supporter has loaded equipment, a real firing lane to an observed enemy and permission to fire. It retains its useful firing position and actual combat engages the assigned threat with the appropriate weapon. |
| Supporter reloads, is suppressed or becomes a casualty | The claim releases or transfers to another capable member; a member cannot cover two movers simultaneously. |
| No partner is available | Ordinary exposed repositioning waits. Immediate survival or a screened shelter from an observed unanswerable weapon may proceed with an explicit unsupported reason. |
| Support disappears during a bound | The mover can finish its short validated shelter route instead of freezing in the open. |
| A member is working or providing casualty care | It cannot also supply a covering weapon or receive conflicting ordinary movement/fire duties. |
| The player replaces an order | Accepted Move, Hold and Retreat release stale support and remain authoritative; rejected orders preserve their prior accepted assignment. |
| A member has two weapon types | Cover eligibility inspects the appropriate carried magazine without switching weapons, spending stock or bypassing an active reload. |
| A different explicit target or urgent threat takes priority | The coverer follows that target and releases both sides of its old support claim. An ATGM operator can select its rifle for explicitly targeted infantry before considering incidental armor. |

## Review corrections

The initial checkpoint could label a member as covering while ordinary combat selected another target or weapon. Combat now prioritizes the assigned covering threat and its suitable weapon over incidental targets. Higher-priority explicit attacks and urgent threats remain authoritative, but release the superseded covering claim. An ATGM operator also selects its rifle for a valid explicit infantry target before incidental armor can steer it toward the launcher.

The coordination regression now follows a real shelter path through arrival, observes ammunition expenditure and the covering member's authoritative shot event, and checks role cleanup. It also exercises alternative weapons, support loss/replacement, player overrides and target preemption.

## Verification

Use Godot 4.5.1. The focused suite is `python3 tools/check.py --group m1`; the [current report](../evidence/m1-01-checks.json) records the exact affected selection from `--group tactical` and 83 current source hashes.

- **Current result:** 17/17 affected suites pass, including 79 coordination checks with zero failures. Coverage includes readiness, action ownership/targeting/integration, cover and contact behavior, soldier targeting, garrison fire, ATGM flight, regrouping, tactical pressure and world damage.
- **Negative control:** the identical final 79-check coordination test against unchanged production checkpoint `0f5eb25` reports 10 expected failures and no script errors. The new assertions therefore detect the corrected behavior rather than only confirming the new implementation.
- **Recorded warning:** the existing ATGM flight suite emits its known ObjectDB shutdown warning; its functional checks pass. The report retains the output.

The fresh evidence replaces the inherited M1.1 snapshot. No native rendering or hardware-performance benchmark was run for this integration correction. Human playtesting and hardware performance remain separate acceptance work.

## Decisions

- Reuse the already implemented M1.1 checkpoint instead of rebuilding it or importing later M1 sections.
- Keep the six-section parent plan as the handoff order; section 2 is fragmentation grenades and smoke.
- Keep automatic cooperation within existing controls. Later payload, backup, construction and UI work remains in its own section.
- Use current physical movement, visibility and weapon checks; a stationary soldier alone is not evidence of covering capability.

## Notes

Long-distance individual navigation, complete peeking cycles, alternating withdrawal groups and urban entry remain broader plan 18 work. Section 1 does not establish a new performance result or resolve M0's known synchronous navigation hitch.
