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

## Jobs, money and cell upgrades (Milestone 5)

See `Work/Employment.gd` and `Cells/CellUpgrades.gd`. The loop is: take a job at the canteen job board, go to the workplace during the arrival window, choose "Start shift",
get paid, then spend the credits on treatment (2 / 3 / 6), the cryopod or healing gel, or the cell upgrades. There is one currency (the existing work credits) and one inventory.

- **Jobs:** Mine worker (mining shafts, 08:00-10:00, 3 credits), Workshop hand (workshop, 10:00-12:00, 4) and Laundry hand (laundry, 12:00-14:00, 2). Each shift takes about two hours and
  costs stamina (the existing 40 for mining, 40 and 30 for the others). There is no mail room in BDCC, so there is no mail job. One job at a time, one paid shift per day across all of them
  (a job change keeps the day's result), no stat growth. Nothing is forced: no teleport, no auto-start.
- **Attendance:** a shift is "not started", "completed", "missed" or "excused". A completed shift clears one warning, an unexcused miss adds one and three in a row dismiss the player,
  who can apply again after three days. Leaving a job and being dismissed keep the history. A reminder appears when the window opens; the status is in the Me screen under "Work".
- **Excused absences:** when the window has closed without a shift, the module asks BDCC what keeps the player away *at that moment*: player slavery, owned by an NPC (soft slavery), an
  owner event scene, or the player's own interaction being stocks, slutwall, unconscious, nurse rescue, caught off-limits, recovering from a lost fight, being punished or an ambush.
  Another module can excuse today's shift with `recordExcusedAbsence(reason)`. *Limitation:* BDCC keeps no history of where the player was, so the check is made when the shift is found
  overdue (the next time any time passes after the window closes), not at the exact deadline: a player who is released from the stocks before time next passes is counted as missed.
  Medical confinement and location control by restraints do not exist as detectable states in BDCC, so they are not checked.
- **Mining:** the story intro still pays once and sets its flag. Ordinary "Work" in the mines (no job needed) still works but pays its 1 credit once per day. The mining job is a separate,
  better-paid shift with the same stamina cost, and it still fires `Trigger.WorkingInMines` so story modules see it.
- **Cell stash and upgrades** (player's own cell, "Cell upgrades"): the ordinary cell storage is BDCC's own pillow stash (the `playerstash` inventory, which BDCC already saves);
  the cell screen and `PlayerStashScene` show the same items. With the module it holds 4 stacks for free (a stack that merges into one already there needs no room); the Personal
  locker (9 credits) raises the same stash to 12. Nothing is ever removed: a stash that already holds more than it fits (an old save) keeps everything, allows withdrawals and refuses
  new stacks until it is back under the limit. Without the module the stash is unlimited vanilla. It is ordinary, unsecured storage. The Hidden compartment (12 credits, 3 stacks) is a
  separate module-owned container (`hidden_storage` in the save) meant to be skipped by future guard searches; nothing searches cells yet. Better bedding (12 credits) adds half again as much
  stamina when resting in the player's own cell (the "Rest" option; sleeping already restores everything). Deposits take any item carried loose in the inventory, including loose restraints (useful for contraband in the hidden compartment); they refuse worn or attached items (BDCC keeps worn items in the equipped slots), important items and persistent items, with a reason.
- **Save data:** `SandboxState` schema 4 adds `work`, `upgrades` and `hidden_storage` (no copy of the stash). Older saves are unemployed with nothing bought; a new game resets everything.
- **API on the module:** `getEmploymentState()`, `recordExcusedAbsence(reason)`, `isShiftCompleteToday()`, `getPurchasedUpgrades()`, `getStoredRecords(hidden)` (false: the real stash, true: the hidden compartment), `depositItem(item, hidden)`, `withdrawItem(uniqueID, hidden)`.

## Guards, searches and proportional enforcement (Milestone 6)

See `Security/Security.gd` (rules and cooldowns, no game access), `Security/Searches.gd` (what a search takes), `Interactions/GuardEnforcement.gd` (the scene) and the "Guards, searches and
enforcement" section of `Module.gd`. The aim is tension, not constant policing: most conduct goes unseen or unremarked, and the player can get away with plenty.

- **Security Attention** (0-100, one temporary value, not a reputation): Routine 0-19, Noticed 20-39, Watched 40-59, High alert 60-79, Priority target 80-100. Shown in Me > Security with a one-line
  explanation, whether you were searched recently and any active warning (never any dice). Detected offences add attention: minor +4, contraband +10 (+5 per repeat find in 3 days, twice at most),
  violent +20, severe +30; resisting a guard +15; beating one +25 but never above 85. It decays 4 a day, and 8 more a day after three incident-free days, and not at all while a confrontation is unresolved.
- **Guard attitude** (lax, standard, strict): from the guard's own Mean personality stat plus a stable per-character offset (so it never changes on reload). Average guards are standard.
  Staff Reputation (Respected is lenient, Troublemaker and Prison Menace draw scrutiny), the guard's Trust and Respect towards the player and Fear all move things a little (at most +-10 points of
  chance). A guard whose Fear of the player is 60 or more will not confront them without backup; they do not become blind to it, the report just waits.
- **Who sees what:** a guard sees what happens in their own room if they are not busy with something else (a victim always sees an attack on them). BDCC has no line of sight, so same-room presence is
  the witness rule. Unwitnessed fights, forced encounters and contraband hidden in an inventory are never noticed; consensual, coerced and unknown-consent sex is never a crime. Nothing is ever started
  during a story scene, a fight, sex, stocks, slavery, a dungeon run or any other interaction.
- **Offences:** minor (a nudity warning), contraband (found in a search), violent (the player started a witnessed fight; attacked a guard), severe (a witnessed FORCED encounter, repeated attacks on
  guards, violence at High alert or above). Violent and severe offences leave a report with the witnessing guard, who acts once the player is free (right after the fight, not in the middle of it).
  Comply: a search and a small fine (severe also goes on to PunishInteraction). Resist: a fight. Win: nothing is taken, attention jumps, the guard is exhausted. Give in before the fight: milder than a
  defeat. Surrender in the fight: the same. Beaten in the fight (pain or lust): searched, fined and sent to PunishInteraction. Milestone 2 and 3 consequences come from the normal fight path, once.
- **Nudity:** exposed private parts by BDCC's own check (partial clothing is fine). Exempt: showers, bathrooms, the medical area, your own cell and solitary, the intro, any scene, anyone who cannot dress (bound
  arms, blocked hands, nothing to put on). A guard may warn once (lax 10%, standard 35%, strict 65% at attention 0, a bit more with attention); the warning lasts three hours, a new one waits six, and only a
  player who is still exposed after 20 minutes can be fined (1 credit at most, never below zero). Lax guards let it go.
- **Personal searches:** only a guard in the same room, per encounter about 1% (standard, attention 0), 0.3% lax, 2.5% strict, times 1 + attention/25, at most 25%. At most one routine search a day, two days
  apart (one day at High alert). A search takes loose contraband only (worn items are never touched), never important or persistent items, with a 1-3 credit fine (never more than you have) and one combined red
  message. An empty search is green and costs nothing.
- **Cell searches:** considered once a day for the player's assigned cell, from 2% (attention 0) to 15%, four days apart, whether or not the player is there; you get a report message. The ordinary stash is
  searched; the hidden compartment is never found by a routine search, and a targeted one (High alert or above) finds it 12% of the time.
- **Pacing:** grace of three hours after complying and six after resisting, half an hour between any two confrontations, a nudity cooldown, the daily search cap and the cell cooldown. Cooldowns stored in the
  future (a corrupt save) count as over, and a confrontation flag with no interaction behind it is dropped.
- **Not done:** guards dispersing NPC-versus-NPC fights (so the player keeps the chance to step in), nurses and engineers as enforcers, line of sight, the prison-snitch offer (gangs, later).
- **Save data:** `SandboxState` schema 5 adds `security`. Older saves start at attention 0 with no cooldowns; a new game resets it.
