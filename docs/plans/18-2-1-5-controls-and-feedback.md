# 18-2-1-5: Controls and feedback

**Parent:** [18-2-1-m1-infantry-defense](18-2-1-m1-infantry-defense.md)
**Status:** completed
**Goal:** Expose the completed infantry actions through compact controls, accurate previews and clear feedback while preserving player command authority.

## Delivery boundary

Continue on `codex/m1-section-5` from published section 4 commit `8b6adb8`, whose tree exactly matches tested local checkpoint `40b5f6d`. Recover only the section 5 candidate delta from `1f42d24`; preserve the reviewed section 1–4 executors. Campaign inventory persistence and the integrated Harbor encounter belong to section 6.

## Implementation parts

| Part | Work | Acceptance |
|---|---|---|
| 1. Commands and cancellation | Contextual strip; G frag, V smoke, D dig, U upgrade, B backup, H Hold fire; explicit Reserve and Auto Frag toggles. | Real input dispatches the intended action; unsupported selections cannot arm it; ordinary commands and Escape/right-click retain their documented authority. |
| 2. Preview and feedback | Shared executor validation for targets; stock, cost, policy and concise current activity. | Known-information previews agree with eligible actors; rejected orders preserve orders/resources; partial radio acknowledgements and terminal work history remain truthful. |
| 3. Verification and handoff | Focused regressions, affected input/UI gates, native layout review, documentation and separate branch checkpoint. | Strip and target feedback fit supported layouts with Field Guide and roster; evidence distinguishes verified behavior from later persistence/performance work. |

## Tasks

- [x] 1. Record the scope and create a separate branch from completed section 4.
- [x] 2. Recover and review the isolated command/feedback candidate.
- [x] 3. Complete command authority, selection and cancellation integration.
- [x] 4. Complete truthful previews, policy state and feedback.
- [x] 5. Verify real input, mixed/radio-limited selections and affected existing UI behavior.
- [x] 6. Review native rendering and layout; record current evidence and update tracking.
- [x] 7. Commit the completed checkpoint and publish `codex/m1-section-5` with code, tests, documentation and verification metadata.

## Decisions

- Keep labels short and put explanations in context or hover text. Extend the existing command deck rather than adding permanent explanatory panels.
- Escape/right-click cancels the pending targeting gesture. Accepted Hold/Move/Retreat replacements cancel unreleased preparation through existing executor rules; released payloads remain world objects.
- Use the current executor preview APIs and physical commitment validation. Do not duplicate simulation ownership, spending or release logic in the UI.
- Native captures remain local review evidence; screenshot publication was not approved during section 4.

## Verification

- The [functional gate](../evidence/m1-05-checks.json) passes **22/22 suites**, including **836 M1 checks** and **121 command checks** (62 command, 59 lifecycle), with no assertion or script errors. The existing input-suite ObjectDB shutdown warning is retained in the report.
- The identical final lifecycle suite produces **14 assertion failures** on the recovered candidate and **zero** after correction, without script errors. It covers unsupported hotkeys, partial radio feedback and repeated toggles, snapped work previews, paused engineers, Resume eligibility and paid-upgrade cost.
- The [native review](../evidence/m1-05-native-review.json) passes **399 checks across eleven inspected Harbor captures**, including actual D/U work, targeting/rejection feedback and strip/guide/roster layout at 1280×800 and 1600×900 with UI scales 1.0/1.5. Prelaunch, run-end and current source hashes match. Captures remain local; the repository contains verification metadata and the reproducible fixture.
- The inherited Harbor crowd-spacing regression and synchronous navigation hitch remain separately documented follow-ups. This selected gate does not establish full-repository, supported-hardware, human-playtest or section 6 acceptance.

## Review corrections

- Buttons and hotkeys share capability/stock gates. Policies derive their toggle direction from connected sections, acknowledge actual reception and display mixed state.
- Work previews retain the executor's snapped rectangle and additional cost. A paid interrupted upgrade previews zero new supply, and Resume eligibility uses the same local/radio/access checks as commitment.
- Selected status checks the retained work assignment before temporary actor claims, keeping paused engineers visibly assigned with remaining time.
- Target previews respect opaque UI, remain within the viewport and yield their reason text to a commitment acknowledgement. A new targeting gesture clears stale cursor feedback.
