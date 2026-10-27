# 18-9: Information, observation and electronic warfare

**Parent:** [18-unit-tactical-autonomy](18-unit-tactical-autonomy.md)
**Status:** not-started
**Goal:** Let units make useful decisions from timely, shared and imperfect observations while keeping concealment, smoke and lost communications consistent.

## Baseline and ownership

At `f5916e8`, [simulation.gd](../../scripts/simulation.gd) refreshes visibility every 0.3 seconds and uses local observation under jamming. Existing orders survive link loss; new remote orders and sensor uploads are blocked. Explicit pursuit retains a last visible destination. [field_ops.gd](../../scripts/field_ops.gd) remembers observed enemy sites. General mobile-contact memory and gameplay smoke are absent. [terrain.gd](../../scripts/terrain.gd) and [elevation.gd](../../scripts/elevation.gd) share physical sight and ridge rules.

This plan owns observation records, information access and smoke's effect on sensing/targeting. [18-3](18-3-infantry-grenades-and-urban-actions.md) owns throwing, impact and payload consumption; [18-4](18-4-coordination-and-support-requests.md) owns support requests. Minimal shared contracts can be implemented before either plan's full catalogue.

## Action catalogue

Starting point describes the primitive; all extensions remain unimplemented.

| ID | Action | Starting point | First delivery | Decision / limit |
|---|---|---|---|---|
| INT-01 | Observe and classify a contact | Existing | Core | Use actual sensors, geometry and range; allow an initially uncertain type. |
| INT-02 | Retain and age a lost contact | Partial | Core | Store the last observation and an expanding uncertainty area; never follow hidden coordinates. |
| INT-03 | Share a contact report | Existing | Core | Attach source, timestamp and confidence; sharing obeys the available link. |
| INT-04 | Watch an assigned sector | Partial | Core | Allocate attention to a bounded arc; ordinary peripheral detection remains explicit. |
| INT-05 | Investigate a sound cue | New | Expansion | Move toward an approximate area only when initiative permits; a sound supplies no exact target. |
| INT-06 | Hold fire to preserve concealment | Partial | Expansion | Requires player policy; define the self-defence exception and exposure after firing. |
| INT-07 | Mark an observed area for support | Partial | Core | Report observation age and uncertainty to the request broker, without promising a responder. |
| INT-08 | Reassess sight and aim through smoke | New | Core | Apply one authoritative optical-occlusion model to acquisition, tracking and UI. |
| INT-09 | Warn nearby partners of danger | Partial | Core | A local warning may work without radio; recipients receive only what the sender perceived. |
| INT-10 | Relay a report between separated groups | New | Expansion | Requires an eligible relay and a bounded delivery model; prevent duplicate reports. |
| INT-11 | Reposition to restore communications | Partial | Expansion | Stay inside the assigned leash and evaluate exposure; do not abandon a hard hold. |
| INT-12 | Execute a lost-link instruction | Existing | Core | Continue the last accepted intent or a preselected safe fallback; keep local defence available. |
| INT-13 | Jam a designated communications area | Partial | Optional | Existing scripted jamming is the baseline; controllable equipment, costs and counterplay are new. |
| INT-14 | Change an emitter's operating mode | New | Optional | Only after emission detection has gameplay meaning; switching has a visible trade-off. |
| INT-15 | Verify a suspected decoy | New | Optional | Requires a decoy mechanic and additional observations; no special access to true entity labels. |

## Decision and data rules

An observation records contact key, observed position, tick, source, uncertainty, classification confidence and sharing scope. Separate local observations from received reports. Confidence decays deterministically; fresh observations replace stale reports. Hidden deaths must not erase remembered contacts or reveal outcomes.

The decision context exposes these records rather than unrestricted enemy dictionaries. Current visible targets can supply exact aiming data. Remembered contacts support watching, investigation or an authorized area action. An area attack may physically affect unseen units inside its simulated effect, but its planner cannot use their hidden positions to choose the area. Sound, last-known markers and hazard warnings must reveal only their declared precision.

Smoke uses bounded authoritative volumes with extent, lifetime, density and owner-independent sensing effects. Begin with optical occlusion and explicit aim/reacquisition rules. Visual particles must agree with blocked sight. This channel does not defeat every guided seeker; additional sensors require definitions and tests. Invalidate relevant sight caches when smoke changes.

Radio policy retains the current usability abstraction of friendly position tracking. Reporting and requesting support still obey link state. Restore a link without replaying expired commands, duplicating requests or granting a complete history of unobserved enemies. Observation quality and combat logic must be independent of camera position and rendering detail.

## Tasks

- [ ] 1. Define observation, report and hazard contracts with [18-1](18-1-action-framework-and-readiness.md); add bounded stores and deterministic expiry.
- [ ] 2. Adapt current visibility, explicit pursuit and enemy-site memory through those contracts; preserve legacy scenario behaviour behind explicit defaults.
- [ ] 3. Deliver contact ageing, sector watching, local warnings and support-area marking using existing sensing geometry.
- [ ] 4. Integrate authoritative optical smoke with the first grenade slice; unify acquisition, known-contact queries, fog and selected-unit explanations.
- [ ] 5. Add hold-fire and uncertain sound investigation with readable intent and information limits.
- [ ] 6. Prototype relay/lost-link policies; evaluate optional mobile jamming, emissions and decoys separately.
- [ ] 7. Pass the information-invariant and load gates in [18-12](18-12-performance-and-validation.md).

## Acceptance scenarios

- A Harbor target disappears behind a wall: the marker ages at its last observed location and a flank uses no hidden movement updates.
- A Limestone ridge blocks a reportable sight line; observing from higher ground changes knowledge through the same elevation rules used by firing.
- Smoke lands between two groups: both lose the appropriate optical access, existing aim responds consistently, and dispersal restores observation normally.
- A jammed section warns a nearby partner, continues its accepted order, and cannot instantly call a distant responder. Reconnection does not duplicate the request.
- A South Inlet drone report reaches the intended ship; moving the camera or reducing visual detail does not change the resulting decisions.

## Decisions

- Proposed priorities are game-design choices; `Core` is a delivery target, not completed work.
- New contact memory is tactical and cleared on a new battlefield. [18-10](18-10-logistics-medical-and-recovery.md) handles persistent roster data; these plans do not add a tactical save.
- Use a small contact marker, optional uncertainty outline and short selected-unit reason via [18-11](18-11-command-interface-and-feedback.md). Placeholder smoke volumes must be visually inspectable before final effects.

## Notes

Implementation touchpoints: `simulation.gd`, `terrain.gd`, `elevation.gd`, `field_ops.gd`, `tactical_director.gd`, `battle.gd`, `hud.gd` and effect presentation. New module boundaries are proposals. No source code, balance values or runtime results are changed by this document.
