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
