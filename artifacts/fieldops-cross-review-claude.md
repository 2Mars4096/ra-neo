# Field operations: cross-review of simulation and performance integration (Claude)

Date: 2026-10-14. Read-only review. Reviewer owns only this file.

## Method and limits

- Read the current `scripts/field_ops.gd`, the relevant parts of `scripts/simulation.gd` and `scripts/terrain.gd`, `scripts/tactical_director.gd` (`update` gate), `scripts/infantry.gd` (`recover`), `resources/field_units.json` and `resources/scenarios.json` (Riverside keys), and main's `battle.gd` field-model sync and `hud.gd` badge/minimap edits.
- Viewed the native captures `artifacts/field-engineer-menu.png`, `field-construction.png` and `field-completed-cover.png`, and read `field-benchmark-before.json` and `field-benchmark-after.json`.
- **No Godot, test, native, windowed or benchmark process was run.** I used only read-only shell commands (`grep`, `sed`, `ls`, `cat`, and one `python3` JSON key listing).
- Everything below is static evidence. Nothing is measured unless the text says so.
- I wrote the HUD/battle field UI earlier, so the HUD findings are not independent.

## Serious issues (3)

### 1. A routine group order permanently halts a site, and the site cannot be resumed or handed to another engineer

**Evidence**

- `simulation.gd:178-179`: `issue()` calls `FieldOps.pause_builder(self,u.id)` for *every* accepted non-queued order. `stop()` does the same (`:218`).
- `field_ops.gd:117-122`: `pause_builder` sets `build_paused=true` and erases `building_id`. Nothing anywhere sets it back to false.
- `field_ops.gd:161`: a paused site never progresses again, and `engineer_id` is fixed at placement (`:101`).
  - A site whose builder died therefore cannot be adopted by another engineer either.
- `field_ops.gd:62-63`: the engineer cannot start another project while the paused site exists ("Engineer assigned; cancel unfinished site first").
- `field_ops.gd:128`: cancelling refunds only the *unspent* fraction. The cost of work already done is lost, and rebuilding charges full price again.

**Player-facing failure**

- Tab or select-all followed by a right-click advance permanently halts every unfinished site. The engineers are included in that selection (`battle.all_sections()`).
- Sending the engineer *back* to its own work point also halts the site, because that is also an accepted non-queued order. `formation_slot` also shifts the destination (`simulation.gd:172-173`).
- The `field_ops.gd:115` comment shows this is intentional. Even so, it contradicts "require a living engineer near the work point over time": absence should stall progress, not end it.

**Bounded fix**

- Keep `tick`'s presence test as the only gate on progress (it already requires the anchor within 0.8 and a living, unsuppressed member within 3.0).
- Add `FieldOps.resume(sim, structure_id, engineer_id) -> bool`. It would:
  - accept a site that is paused or whose builder is dead, with a living engineer that has no other unfinished assignment;
  - re-run the work-point route search from `proposal`;
  - set `engineer_id`, `building_id` and `build_paused=false`;
  - charge nothing.
- Expose it as a RESUME action next to CANCEL. If minimal sim change is preferred, at least skip `pause_builder` in `issue()` when an order's destination is within 1 m of that engineer's site work point.

### 2. Placement validation leaks hidden enemy positions, and the 5 Hz preview turns that into a scanner

**Evidence**

- `field_ops.gd:65` calls `sim.location_clear(pos,kind)`. That function (`simulation.gd:795-803`) rejects any unit on the land layer within `def.radius + other.radius + 0.12`, which is about 4.5 m for tactical cover against a 2.65-radius squad. It does not check `seen_by`.
- `field_ops.gd:67-70` (footprint against members) and `:79-83` (work-point occupancy) likewise iterate *all* teams' members, with no `seen_by[0]` filter.
- `:64` only requires the site's *cell* to be in `visible_cells`. Units in woods inside a visible cell are routinely unseen, because `update_visibility` shrinks detection radius by 0.7 in cover (`simulation.gd:327-328`) while the fog field uses full sight.
- Result: hovering a placement preview over visible woods returns "Site obstructed" or "No clear engineer work route" exactly where a hidden enemy stands. The HUD re-polls `build_reason` up to five times a second while the cursor moves, so that check works as a scanner.
- This breaks the existing rule that orders never use hidden live positions (`simulation.gd`, attack-order comment).

**Bounded fix**

- In `proposal`, skip units with `team!=0 and not seen_by[0]` in all three occupancy checks. Use a team-aware variant of `location_clear` there.
- Keep the physical full check only inside `build()`, just before `spawn`. If an unseen enemy occupies the site at commit, refuse with the same generic reason and charge nothing (`build` already returns before spending). That limits the leak to deliberate clicks, at the same granularity as a failed move order.

### 3. Every structure state change wipes all navigation, weight and visibility caches (performance risk, unmeasured)

**Evidence**

- `field_ops.gd:138-151`: `sync_obstacles` runs whenever any structure is placed, completes, is cancelled or is destroyed. Each time it calls `terrain.navigation.clear()`, `navigation_weights.clear()` and `visibility_cache.clear()`.
- Every later `path()` per domain/radius/profile key then rebuilds a whole AStarGrid2D inside a sim tick (`terrain.gd:217-230`). For Riverside's 144×108 grid that means 15,552 `traversable()` calls, each looping blocks, dynamic blocks, roadside blocks and trees, plus a weight layer of 15,552 `ground_speed` → `cover()` calls.
- The fog fields are rebuilt too, with `line_clear` per tile, on the next sensor tick.
- `battle.gd:92` prewarms these grids at startup precisely because building them is expensive.
- Placement also triggers this mid-play, and a destroyed site triggers it during combat.

**Measured context (not attribution)**

- The two benchmark JSONs are not like-for-like: groups 10→14, visible members 8→11.
- In `-after`: `engine_process_ms_p95` rose from 15.709 to 26.254 ms, while `frame_ms_p95` moved only from 18.153 to 18.474 and `simulation_ms_p95` from 1.532 to 1.448.
- I cannot tell whether a sync event happened inside the sampled window. This needs one timed run that places and completes a site inside the window, logging `sync_obstacles` plus the first rebuilt `path()` cost.

**Bounded fix**

- Update the caches locally instead of clearing them.
  - **Add:** for each cached grid, mark cells in `rect.grow(radius+0.27)` solid.
  - **Remove:** recompute only those cells with `traversable`.
- Weights depend only on `field_cover` through `cover()`. Recompute weight cells only inside `rect.grow(1.4)`, and only when tactical cover completes or is destroyed.
- Drop only the `visibility_cache` entries whose origin cell is within sight range of the rect.

## Checked and passing (bounded)

- **Atomic spending.**
  - `build`: validation runs, then `spawn`, then the charge (`field_ops.gd:97-111`). `spawn_position` returns the exact validated origin because `proposal` already required `location_clear(pos,kind)` (`simulation.gd:806`). A failed spawn returns before spending.
  - `purchase` charges only after a successful `spawn` (`:41-44`).
  - `cancel` refunds once. Setting hp to 0 makes any later cancel fail the `alive` check.
  - The single-assignment check prevents two sites per engineer within one tick.
- **Support effects.**
  - **Aid post:** heals only living members (`infantry.gd:207-216` skips `hp<=0`), so there is no revival.
  - **Repair point:** heals only land units with no members, i.e. vehicles.
  - Both need the ally within 10 m of the structure centre, 6 s since the last hit, and suppression ≤0.6. Both heal 6 HP/s with `line_clear` LOS.
  - `line_clear` ignores dynamic rects that contain either endpoint (`terrain.gd:357-358`), so a structure's own footprint does not block its LOS. Woods do not block support LOS; buildings do.
  - An observation post's 24 m sight counts only after completion (`simulation.gd:319`).
  - Tactical cover becomes `field_cover` only on completion (`field_ops.gd:148`) and then feeds `cover()` (`terrain.gd:94-95`).
- **No factory or macro economy in this mode.**
  - Kill bounty and capture bonus are zeroed for field ops (`simulation.gd:429`, `:781`).
  - Waves and classic income are skipped (`:535`, `:543`).
  - `Classic.tick` is not called (`:527-533`).
  - The only income is `income_rate` 2/s in `FieldOps.tick`.
- **Path and cache restoration.**
  - `terrain.path` temporarily sets only cells that were not already solid (`:288`). It restores them on both later return paths (`:303-306` and `:308-309`); earlier returns happen before any mutation.
  - There is no `await` or re-entrancy.
  - `proposal` no longer swaps `terrain.navigation`.
  - The conservative avoid circle (`:73`) encloses the future footprint, so the published route stays valid after `sync_obstacles` adds the block.
- **Director.** It skips units with `building_id` and `move` intents (`tactical_director.gd:42-44`). Riverside has `autonomy: true`, so this guard matters and is present.

## Lower-severity observations (not counted above)

- Destroyed field structures increment `losses` (`simulation.gd:430`), which inflates "sections lost" on the result screen.
- All three captures show the first objective badge as "TOWN CROSSING%", with the progress text colliding with the name.
  - Current `hud.gd:213-217` already widens the badge and right-aligns the state.
  - The captures (16:20) may predate that change. Not re-rendered.
- `field-completed-cover.png` shows a light bar above the finished cover. It is either a leftover 3D `ConstructionProgress` bar or the HUD health bar, if float accumulation in `field_ops.gd:167` leaves hp a hair below `max_hp`. Unverified; a final `hp=max_hp` on completion would remove the second possibility.
- A friendly unit parked on a work point after placement can block the engineer short of the 0.8 m arrival test, so the site stalls with no specific message.

## Unresolved

- Issues 1–3 are open and need owner decisions or changes in `field_ops.gd`/`simulation.gd`/`terrain.gd`, which this reviewer did not edit.
- The performance impact of issue 3 is unmeasured.
- No native re-capture was made after main's HUD and portrait fixes.
