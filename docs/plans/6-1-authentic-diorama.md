# 6-1: Authentic diorama materials

**Parent:** [6-painted-miniatures](6-painted-miniatures.md)
**Status:** completed
**Goal:** Preserve the miniature presentation while adding weathered, readable materials inspired by the user's reference.

## Tasks
- [x] Layer chipped plaster/masonry, damp, roof variation, metal oxidation and restrained relief.
- [x] Add equipment dust/wear and distance-filtered ground aggregate.
- [x] Inspect native close and gameplay views; check shader errors and frame performance.

## Decisions
Original procedural materials; no reference pixels copied. Keep collision/navigation unchanged. This pass addresses surface quality; damaged buildings with true interiors and bespoke assets remain future work.

## Validation
Native frames inspected without shader errors; 126,928 clearance checks pass. Rainy 1080p/100-entity M4 Pro benchmark: 24.12 ms frame p95, 10.627 ms simulation p95. Above the 16.7 ms target and the previous 22.042 ms run; no performance improvement claimed.
