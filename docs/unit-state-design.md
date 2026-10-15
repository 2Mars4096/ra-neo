# Unit state and feedback design

Presentation must communicate action, capability, and interruption without extra micromanagement. Current cues are procedural, intentionally readable at RTS zoom, and driven by simulation state/time.

| State or transition | Current cue / behavior | Remaining depth |
|---|---|---|
| March / advance | Displacement-driven legs and wheel spokes; lowered infantry weapons while moving without a target; aircraft lean, ship wakes | Foot planting, tracked belt deformation, acceleration/turning physics |
| Halt / hold | Stride amplitude settles, ready weapon pose; neutral aircraft attitude | Individual formation settling and scanning gestures |
| Observe / acquire | UAV rotors/hover; infantry raise weapons; tank/AA/deck turrets track independently; acquisition delay before damage | Sensor gimbals, target-specific aim constraints |
| Fire / cycle | Barrel/upper-body recoil, muzzle flash, moving shot or missile trail; cooldown shown as CYCLING | Real reload clips and magazine/ammunition system; current cooldown must not imply either |
| Incoming fire / pinned | Individual torso flinch and lean; lowered torso, braced legs, suppression indicator | Contextual cover selection; no automatic bullet-dodging or damage immunity |
| Withdraw | Existing faster retreat, no firing, moving pose and state label | Individual backward movement/bounding behavior |
| Yield / blocked | Movement settles and YIELDING remains visible | Better alternate-route selection and UI route explanation |
| Recover | Existing repair eligibility/cost and recovery label | Dedicated repair crew/medical animation |
| Damaged / destroyed | HP/survivor indicators, damage smoke; vehicle fire destruction and individual infantry casualties | Persistent wrecks/corpses, damaged mobility, disabled systems; no collision-free wreck claim |

Priority: destroyed, recovering, withdrawing, pinned, immediate hit reaction, firing, acquiring, cycling, yielding, movement, holding/observing. Body locomotion, weapon action, and hit reaction are layered so a moving unit can still aim or react. No presentation-only gesture grants a gameplay benefit.

## Landscape references

Three fictional scenarios: Coastal Spear (estuary/port), Harvest Line (agricultural frontier), Iron District (industrial fringe). They share the engine and coastal boundary but change obstruction/cover/soft-ground layouts, objective names and hold time; Harvest Line changes one defender to anti-tank. They are not reconstructions of real engagements.

Broad environmental inspiration: [FAO's Ukraine agricultural-enterprise assessment](https://www.fao.org/family-farming/detail/en/c/1743890/) describes damage to agricultural assets and land; [ICRC's urban-warfare overview](https://www.icrc.org/en/law-and-policy/urban-warfare-and-violence) describes urban infrastructure damage. These support the choice of landscape themes, not claims about weapon accuracy or a comprehensive simulation of current conflicts.

## Individual entities

Infantry soldiers now own their position, facing, HP, target, aim time, firing cooldown, suppression and hit/fire timestamps. Their formation slots and locomotion phases differ. Hits affect one soldier; casualties hide that actor and reduce section firepower. Repair cannot resurrect them. Squad routing provides a conservative shared envelope, while individual movement checks terrain and peer separation inside it. This is intentionally a first individual-actor implementation; free-form cover seeking and independent long-range navigation remain future work.
