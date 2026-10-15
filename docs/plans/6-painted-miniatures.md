# 6: Painted military miniatures

**Status:** completed
**Goal:** Establish the user-selected painted military miniature direction across equipment and scenery.

## Tasks
- [x] Introduce a shared matte paint shader with broad surface variation, upper-surface highlights, muted dust, and softened lighting bands.
- [x] Apply the same material treatment to batched units and solid scenery without losing geometry batching.
- [x] Establish olive/ochre faction paint and warm light with cool ambient fill; reduce terrain texture noise and crushed dark patches.
- [x] Inspect native equipment and battlefield renders, validate geometry and performance, and relaunch.

## Decisions
- Keep recognizable military silhouettes, independent joints, and existing collision envelopes.
- This is an initial coherent material/lighting pass. Hand-authored textures, bespoke architecture, and finished character art remain future production work.

## Evidence
Native equipment and all three map renders inspected. Post-material geometry suite passes 126,888 checks; the preceding behavior/layout build passed all 11 suites. Latest local 1080p stress p95 is 21.644 ms, above target; style acceptance does not imply performance completion.
