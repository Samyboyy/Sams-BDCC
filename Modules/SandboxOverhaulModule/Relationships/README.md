# Directed relationships

Per-character feelings stored in `SandboxState.directed_relationships[observerID][targetID]`.
`DirectedRelationships` is the only intended way to read or write them. Get it with `SandboxOverhaulModule.getRelationships()`
(call it each time, do not cache it across games).

| Axis | Key | Range | Meaning |
|---|---|---|---|
| affection | `a` | -100..100 | Negative: resentment or hatred. Positive: fondness and care. |
| trust | `t` | -100..100 | Negative: expects betrayal or harm. Positive: reliable and safe. |
| respect | `r` | -100..100 | Negative: contempt. Positive: admires ability, courage or principles. |
| fear | `f` | 0..100 | How able and willing they think the target is to cause harm. |
| desire | `d` | -100..100 | Negative: sexual aversion. Positive: sexual attraction. |

Defaults are 0. The axes are independent, and A to B is stored separately from B to A.
Pairs whose recognised axes are all at default are not stored. Unknown per-pair keys are preserved.
Characters that no longer exist (`GM.main.getCharacter(id)` is null; `"pc"` is always kept) are pruned just before saving.

Only the sex aftermath (below) writes these values so far. BDCC's own `RelationshipSystem` (shared affection and lust) still drives Friend, Nemesis and AI.

## Sex aftermath (Milestone 1C)

`SexConsent.classify(interactionID, stateID)` decides how an encounter started from the interaction and its state only
(never arousal, satisfaction, fetishes or personality). `SexAftermath` holds the tuning table and applies it:
consensual changes the NPC participants' feelings towards their partner; coerced or forced changes the NPC victim's feelings
towards the responsible character (affection, trust, fear; never desire or respect). The player's own feelings are never stored.
Unlisted interactions are `UNKNOWN` and change nothing. Hook: `PawnInteractionBase.doSexAftermath` (see `CORE_PATCHES.md`).

## Conversations (Milestone 1D)

`ConversationRelationships` maps Talking outcomes to the NPC's feelings towards the player (whichever of starter or reacter the NPC is; conversations without exactly one player are not handled) (see the `RULES` table:
shared interest, positive conversation, respectful disagreement, flirt accepted or rejected, sex request accepted).
Neutral exchanges and refused sex requests change nothing. Fear is never changed. Each outcome also applies a fixed legacy delta (100:1) to BDCC's
RelationshipSystem, temporary while Friend, Nemesis and AI still read it. A rewarding outcome is paid once per in-game day per
NPC, target and outcome in both systems (`SandboxState.cooldowns`, keys starting `conv|`); negative outcomes are never limited.
`hostile_response` exists but no current Talking outcome produces it.

## Combat (Milestone 2)

`CombatConsequences` keeps two prison-wide values in `SandboxState.reputation` (both -100..100, start 0): Combat Reputation (perceived fighting
ability) and Defiance (perceived willingness to resist). Individual NPCs keep their own Fear and Respect towards the player in the directed
store. Outcomes and numbers are in the `RULES` table; the first outcome against an NPC each in-game day is full strength, later ones are
25% personal change and 25% Defiance, with no more Combat Reputation. NPC attack interest is multiplied by the Combat Reputation and Fear multipliers (never below 0.05),
and punishments after a lost fight are weighted 1.25x if the player resisted, 0.65x if they surrendered.

## Injuries (Milestone 3)

See `Injuries/Injuries.gd` (all tuning constants in one place). Three types and three severities (Minor 10%, Moderate 20%, Severe 30%; 24, 72 and 120 hours):

| Type | Penalty |
|---|---|
| Arm Injury | physical damage dealt reduced by the percentage |
| Leg Injury | maximum stamina and final dodge chance each multiplied by 0.9 / 0.8 / 0.7 |
| Body Trauma | physical damage received increased by the percentage |

**Only Body Trauma currently arises from ordinary fights.** A fighter ending a fight with 35% / 60% / 85% of their pain threshold gets a Minor / Moderate / Severe
injury (one level less in the Fight Club arena), but BDCC records no per-body-region damage, so the type is always Body Trauma and nothing is chosen at random.
Arm and Leg injuries are fully implemented and tested; they are for future targeted attacks, scripted events and debugging (`Injuries.applyInjury`, or
`evaluateFight` with a region-damage dictionary). Do not describe them to players as something fights naturally cause.

The Arm and Body Trauma penalties are applied by status effects through BDCC's buff calculations. The Leg Injury is applied by two multipliers in
`BaseCharacter.getMaxStamina` and `getDodgeChance` (see `CORE_PATCHES.md`). All of them read `SandboxState.injuries`, so each is applied exactly once.

No fight is excluded from injuries: the only fights that could be called tutorials (the intake fight against `rishaIntro`) or sparring (Rush's boxing) do not
restore their participants afterwards, and there is no battle name or flag that marks a restorative fight.

## Cells (Milestone 4)

See `Cells/Cells.gd`. BDCC's cell blocks are three colour-coded areas (Orange general, Red high security, Lilac sex deviant) with one personal cell room each; there are
no separate rooms for other inmates, so a cell is a logical home (block plus number, two occupants at most) shown through a directory rather than as separate map rooms.
Eligible inmates (the player and the dynamic inmates, including inmates who are now slaves) get the first free place, the player first, so the next inmate of the player's block is their cellmate.
Assignments never reshuffle; removed characters free their place. Inmates settle in around 21:00 and leave around 07:00 with a fixed per-inmate offset of up to 30 minutes.
Tonight's attendance is recorded as `home` or `away` per inmate (`cell_presence`, valid only for that night): an inmate who settles, or who simply is not spawned, is home; one who is busy, still walking, or kept elsewhere (slavery, SoftSlavery, an enslave quest) is away. An away inmate is tried again every ten minutes; the system only knows home versus away, never where they are. Enslaving or freeing someone never changes their cell. The directory is the "Cell directory" button in each block's hall;
"Cell info" in the player's cell, and "Cells" in the Me screen, show the player's cell, cellmate and the cells they have learned by asking.
