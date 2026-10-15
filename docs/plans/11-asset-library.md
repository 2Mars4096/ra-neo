# 11: Structured environment asset library

**Status:** completed
**Goal:** Build reusable categorized assets with bounds and placement contracts, inspect them in a native gallery, then use the same data for future map authoring.

## Tasks
- [x] Complete street/town/utility variants (20 models).
- [x] Complete rural/vegetation variants (16 models).
- [x] Complete industry/waterfront variants (18 models).
- [x] Complete field-defence/damage variants (18 models).
- [x] Unify metadata and existing building/prop families in a callable registry.
- [x] Add executable footprint/placement checks and native labelled gallery.
- [x] Independently cross-review actual gallery renders with Codex and Claude; fix supported findings.
- [x] Run integrated checks and record the remaining three-person arrival-timing failure in navigation tracking.

## Decisions
- User explicitly prioritizes assets and rules before further map enlargement; the proposed seventh 512×384 map is not being authored yet.
- Variants change structure and purpose, not only color. Existing material language and cached/batched rendering remain.
- Library readiness is separate from map placement or implemented gameplay cover/collision. Registry metadata must state both.
- Retain accepted authentic miniature direction. RA2/AoE/Syx study concerns meaningful construction/use/context, not lowering resolution.
- Team edits are disjoint in this non-Git repository. Lead owns registry, gallery, placement validation and integration.

## Validation and scope

-100 callable models/10 categories, including72 new variants. All asset/registry/placement/palette suites pass; native captures and source hashes accompany the searchable HTML review.
- Review fixes include meaningful glass, irregular rip-rap, continuous tent roofs, natural damage outlines, neutral palette isolation, drainage geometry and accurate gallery framing. Gallery has inspection rotation and shared-scale comparison; preview render targets cache until resized/rotated.
- The three-member gameplay recovery passes separation/continuous movement/90-second completion, but section1 arrives67.10s rather than the existing60-second expectation. This assertion remains failing and is explicitly unaccepted; no all-suite-pass claim.
- Further map expansion, visual map-editor UI, part-level overhead collision and production-quality reference parity remain separate future work. User asked assets/rules first.
