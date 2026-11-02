# 18-2-1-1: Coordinated cover and movement

**Parent:** [18-2-1: M1 infantry defense](18-2-1-m1-infantry-defense.md)
**Status:** in-progress
**Goal:** Let infantry cover a teammate's short move to shelter with a real, available weapon while preserving player orders and individual action ownership.

## Scope and baseline

The current request implements and reviews section 1 only, then commits and pushes `codex/m1-section-1`. Existing checkpoint `0f5eb25` supplies the initial implementation over M0 `5850504` and the plan-only commit `b94593a`; this branch reuses that work and addresses review findings. M1.2–M1.6 remain outside this checkpoint.

## Tasks

- [x] 1. Divide M1 into six dependent implementation sections in the parent plan.
- [x] 2. Reuse M1.1 reciprocal coverer/mover roles, actual weapon/visibility eligibility and alternate-magazine readiness.
- [x] 3. Preserve the coverer's position and loaded magazine; replace unavailable support or let an exposed mover finish its validated shelter route.
- [x] 4. Exclude task-owned actors from ordinary movement, firing, reload and medical work; release cooperation on accepted replacement commands.
- [ ] 5. Review movement, support release and player-order integration; correct concrete section 1 defects.
- [ ] 6. Run focused coordination and affected regression suites on this branch; record current results.
- [ ] 7. Update tracking, commit and push the section 1 checkpoint.

## Acceptance

| Situation | Required behavior |
|---|---|
| One soldier moves, another covers | The supporter has loaded equipment, a real firing lane to an observed enemy and permission to fire. It retains its useful firing position. |
| Supporter reloads, is suppressed or becomes a casualty | The claim releases or transfers to another capable member; a member cannot cover two movers simultaneously. |
| No partner is available | Ordinary exposed repositioning waits. Immediate survival or a screened shelter from an observed unanswerable weapon may proceed with an explicit unsupported reason. |
| Support disappears during a bound | The mover can finish its short validated shelter route instead of freezing in the open. |
| A member is working or providing casualty care | It cannot also supply a covering weapon or receive conflicting ordinary movement/fire duties. |
| The player replaces an order | Accepted Move, Hold and Retreat release stale support and remain authoritative; rejected orders preserve their prior accepted assignment. |
| A member has two weapon types | Cover eligibility inspects the appropriate carried magazine without switching weapons, spending stock or bypassing an active reload. |

## Verification

Use Godot 4.5.1. The focused suite is `python3 tools/check.py --group m1`; affected checks are selected from `--group tactical` for readiness, action integration, cover, regrouping and command authority. Record the actual suite selection and current source hashes with the results.

Current review results: **pending**. The inherited M1.1 report is historical and includes hashes for later modules not present here. It cannot establish this branch's current verification. Human playtesting and hardware performance remain separate acceptance work.

## Decisions

- Reuse the already implemented M1.1 checkpoint instead of rebuilding it or importing later M1 sections.
- Keep the six-section parent plan as the handoff order; section 2 is fragmentation grenades and smoke.
- Keep automatic cooperation within existing controls. Later payload, backup, construction and UI work remains in its own section.
- Use current physical movement, visibility and weapon checks; a stationary soldier alone is not evidence of covering capability.

## Notes

Long-distance individual navigation, complete peeking cycles, alternating withdrawal groups and urban entry remain broader plan 18 work. Section 1 does not establish a new performance result or resolve M0's known synchronous navigation hitch.
