# 4: Combat relationships and disrupted communications

**Status:** completed
**Goal:** Separate hit difficulty from damage, enforce sensible weapon counters, and integrate readable radio disruption.

## Tasks
- [x] Audit all seven weapon/target rows; prohibit rifle damage to armored hulls.
- [x] Add seeded hit/miss resolution, range/motion/suppression accuracy, and fragile small UAVs.
- [x] Use individual surviving weapons for squad engagement decisions; expose AA recruitment.
- [x] Prototype industrial EXCHANGE interference: retain orders/local defense, reject remote commands, suppress sensor uploads, restore on capture.
- [x] Add matrix, UAV, immunity, and communications regression checks.
- [x] Resolve newly exposed industrial traffic stall without relaxing model clearance.
- [x] Run complete regression suites and inspect the native UI.
- [x] Record evidence and limitations.

## Decisions
- These are dimensionless game values, not validated ballistic or radio propagation measurements.
- One successful rifle hit disables the small GHOST UAV. A helicopter remains a separate, tougher class.
- Interference does not damage people, erase orders, or make soldiers randomly disobey. It blocks new commands and shared sensor reports; existing orders and local defense remain active.
- EXCHANGE is a pre-briefed area jammer in the industrial mission. Capture disables it. This prototype does not simulate frequencies, equipment-specific resistance, relay networks, or directional antennas.

## Evidence
Ten suites pass; 1,064 combat/communications checks, 135,171 geometry/clearance checks, and unchanged-policy victories in all three scenarios. Native screenshot: `artifacts/combat-relationships.png`. Latest 1080p frame p95 is 17.747 ms, above the provisional 16.7 ms target; further performance work remains in todo.
