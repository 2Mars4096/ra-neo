# 2: Tactical decisions and recovery

**Status:** completed
**Goal:** Give the current battle meaningful preservation, suppression, and opponent-response decisions before expanding its map and economy.

## Tasks
- [x] Add retreat orders with domain-safe rally points, no firing during withdrawal, and recovery at a secure landing zone.
- [x] Make suppression delay anti-tank fire and prevent capture while heavily suppressed.
- [x] Let enemy ground defenders react to observed threats and withdraw when badly damaged; retain fog restrictions.
- [x] Expose retreat, recovery, and suppression clearly in the command interface.
- [x] Test tactical consequences, input, clearance, and the complete mission; inspect rendered feedback.

## Decisions
- Implement the first proposed increment as a playable improvement. Village/ridge/port redesign and forward-base construction remain subsequent increments, not claimed complete here.
- Preserve collision-aware movement and unit definitions. Recovery costs supply and requires a quiet friendly staging area; retreat is not invulnerability.
- Enemy responses use visible contacts and last issued orders, never hidden player positions.

## Evidence
15 tactical behavior checks, 19 input checks, 41 simulation checks, 95,828 geometry/clearance checks, effects tests, and a complete 75.1-second scripted victory pass. Rendered command deck inspected. The baseline policy still wins; this increment does not establish the proposed 10–15 minute match or human enjoyment.
