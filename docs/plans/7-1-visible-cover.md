# 7-1: Visible individual shelter movement

**Parent:** [7-combined-arms-showcase](7-combined-arms-showcase.md)
**Status:** completed
**Goal:** Replace almost invisible local slot adjustments with individual routes to shelter in the autonomy scenarios.

## Tasks
- [x] Diagnose short search radius and unreachable shelter slots.
- [x] Reserve separate destinations, route around scenery, stagger movers and settle before firing.
- [x] Respect explicit orders and known contacts; bound blocked attempts and retain occupied shelter.
- [x] Test movement, separation, arrival, overrides and unseen contacts; inspect native frames.
- [x] Record remaining behavior and whole-project gaps.

## Decisions
- Fictional bounded 10-unit search, at most half a section seeking at once; this is an RTS approximation.
- Existing Canal Watch/Frontier autonomy scope retained. Original three maps are unchanged.
- Walls must screen the observed threat at destination; foliage/rubble retain abstract partial cover.
- Current cover damage remains abstract, and soldiers cannot peek around walls yet.

## Notes
- Initial full run caught repeated shelter expiration and a classic-policy defeat. Retaining valid shelter restored the unchanged policy's victory at 538.1 simulated seconds.
- Cover fixture: 9.51-unit maximum travel, arrival verified, no scenery/peer overlap in checked frames.
- Native review uses a controlled contact with enemy firing disabled; it is a presentation fixture, not a normal-play difficulty claim.
