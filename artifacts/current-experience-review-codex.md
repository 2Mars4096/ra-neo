# Current experience review — Codex

2026-10-14. Independent bounded Codex assessment; no Claude opinion consulted or claimed. Read-only inspection of the current town gameplay/street/yard/overview PNGs (the requested frontage/quay update), effects a4/b1/d2, `docs/art-authenticity-review.md`, HUD/input/production code and relevant environment/effect source. Only this report was written. No tests, native/browser processes, timing or implementation. Acceptance below is proposed, not passed.

The closer frontages, pavement/grates, warehouse stock and new quay are present and useful. The strongest remaining artificial cues are spatial composition and exact repetition, not insufficient polygon count. The recorded AoE screenshot (`browser_1791959099562.png`) uses shared enclosures and spaces framed by buildings; RA2 (`1791959155304`) connects wear, service pads and perimeter walls to activity; Syx (`1791959187564`) makes repetition describe rooms with different uses. All three were inspected under `output/browser/5b135c70b48a1635/`; these are visual lessons, not evidence about their rendering internals.

## 1. P1 — Full production queues silently reject an apparently available purchase

**Evidence:** `hud.gd::draw_sidebar` enables a production tile using funds, recruitment cooldown and existence of a producer. It does not check queue capacity. `Classic.producer` can return a full facility; `Classic.enqueue` rejects queue size >=5. `battle.gd::ui_action` reports only successful recruitment. Therefore, with sufficient funds and all eligible producers full, the tile can remain enabled and a click has no feedback. Existing prerequisite/funds/cooldown hover explanations are present; those are not missing.

**Correction:** Make availability and hover explanation use the same selected producer/capacity rule as enqueue. Show “All factory queues full (5/5)” or the appropriate producer name; report an explicit failure if capacity changes before the click. Keep purchases enabled when another eligible facility has space.

**Acceptance:** With every eligible queue full, the tile is disabled with the exact reason and funds do not change; freeing one slot restores purchase. A second non-full facility permits purchase. Rejection cannot silently fail. This is a source-supported inconvenience, not an observed interactive reproduction.

## 2. P1 — Large street-block interiors still read as leftover display space

**Evidence:** `town-inspection-street.png` shows a large undifferentiated rectangle behind the central paired shops and another around the lower cafe. The overview repeats these isolated parcel islands across an otherwise connected road grid. Roads, frontage links and district ground treatment exist; the problem is that these broad spaces still communicate little use. `environment_detail.gd::land_use_at` supplies district/apron weights, rather than an authored activity layout.

**Correction:** Complete one central block first: define a rear service lane joining existing frontage paths and two shallow garden/working-yard surface zones aligned with the existing buildings. Use restrained earth/gravel transitions and ground-level wear, preserving movement costs; do not paint fast-looking asphalt. Put any substantial boundary or storage geometry wholly inside existing blocked parcels. Preserve the middle route as deliberate open maneuver space instead of filling it with props.

**Acceptance:** At the existing street and overview camera positions, reviewers can distinguish frontage, rear access and garden/service use without annotations. The open maneuver corridor remains visually evident and navigable. No new decorative obstacle extends onto traversable space. This needs composition, not more randomly placed detail.

## 3. P2 — Warehouse duplicates reveal the reusable template

**Evidence:** The two adjacent buildings in `town-inspection-yard.png` repeat the same twin roof, white office annex, window pattern, dock arrangement and pipe rack. `_warehouse` has a single fixed bay/annex composition and is selected for both parcels; the per-parcel seed does not change those major masses. Repetition is credible for industrial sheds, but repeating every distinguishing attachment makes these look copied.

**Correction:** Add one deterministic warehouse variant within the same bounds: keep structural bays and loading-door clearance, but change one roof bay's intact/skylight treatment, office parapet profile and one rear stock grouping. Retain the existing rack clearance check; skip it if a changed assembly no longer fits. Do not merely recolor identical geometry or duplicate more tiny props.

**Acceptance:** The two yards remain recognizable as the same industrial family but can be told apart by roof/annex/stock silhouette at overview zoom. Every vertex still fits its blocker, and dock doors and rack support remain clear. No additional live nodes/lights are needed.

## 4. P2 — Repeated water bands expose the formula beside the new quay

**Evidence:** The yard and b1 effects capture show evenly recurring pale diagonal wave bands across nearly the entire visible channel. The quay now provides a physical edge, but the water pattern reads as repeated chevrons. `visuals.gd` uses two large sine terms and a fixed shoreline exponential for water color.

**Correction:** Keep one water surface; break up the crest strength and phase with low-frequency world-space variation, reduce the broad stripe contrast, and concentrate subtle staining/foam response at the existing quay contact. Preserve the current shoreline and navigation boundary; no extra waves-as-geometry or broad white foam strip.

**Acceptance:** At the same yard and naval camera scales, no long sequence of equally bright, equally spaced chevrons dominates the channel. Boat silhouettes, wakes and discrete impact rings remain easier to read than background water. Native still and motion review will be required; neither was run here.

## 5. P2 — Fireballs have a flat orange middle stage

**Evidence:** In a4 the blast is a nearly uniform saturated-orange cluster; in b1 the boat fireball similarly reads as an orange disc. The d2 immediate white core is localized and plausibly brief, so this is not the former white-sheet failure. `effect_volume.gdshader` computes age-based fire colors with only modest coarse/core modulation; the vehicle blast overlaps four similar fireball cards.

**Correction:** Add restrained lobe-scale dark-orange/soot variation within the existing shader and slightly stagger the existing cards' cooling, without increasing card count or total footprint. Preserve the small initial hot core and readable outer dust/spray. Do not dim every effect globally.

**Acceptance:** In the same staged middle-age capture, each blast shows a readable hot interior and darker cooling edge rather than a solid orange patch. Early flash remains localized, water spray stays distinct, and the isolated projection check still passes. Static evidence does not establish motion quality or performance.

These five items are a bounded implementation shortlist. Items 2–5 are visual judgments tied to inspected images; item 1 is a concrete source-derived input/feedback defect. No claim of reference parity, native performance, or Claude agreement is made.
