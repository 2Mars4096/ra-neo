# 13: Black Sea Harbor

**Status:** in-progress
**Goal:** One large fictional Sevastopol-inspired combined-arms battlefield built from the shared asset and placement system.

## Tasks
- [ ] Author deterministic blueprint/compiler for1024×768, with connected bays, headlands, dense town core, freight waterfront and rural approaches.
- [ ] Support polygonal water, configurable navigation/fog cells and fast spatial queries while preserving legacy tests.
- [ ] Render shared coastline masks, rotated parcel groups and contextually placed library assets efficiently.
- [ ] Parameterize field operations, reinforcements, objectives, camera and map UI for the new theatre.
- [ ] Validate real land/sea/air routes, engine construction, visibility, native composition and performance before opening the map.

## Decisions
- This explicitly supersedes the earlier asset-first deferral: the user now requests one huge map, combining the trial maps' strengths.
-1024×768 is roughly50.6× Riverside's area. Physical-scale interpretation remains approximate because RTS ranges are compressed; no claim of an exact geographic reconstruction.
- Public broad bay/headland and historic urban/rural geography inspires a fictional map. No real military deployment or defence data is used.
- One active theatre; older maps remain regression fixtures and are hidden from normal selection.
- Single-supply purchases and engineer tactical works remain. Macro economy stays deferred.
- Dense districts follow different street/plot patterns; avoid uniform one-building-per-cell scattering or merely scaling old coordinates.
- Initial large-map parameters: navigation4world units and fog8; continuous footprint tests remain authoritative. Validate route access and visual/coast consistency rather than assuming coarse grids are adequate.

## References
- [UNESCO: Tauric Chersonese and Chora](https://whc.unesco.org/en/list/1411/) — historic urban/agricultural landscape context.
- [UNESCO city-map document](https://whc.unesco.org/document/123803) — broad geography reference, not a game map or operational plan.
