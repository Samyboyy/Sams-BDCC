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

See `Cells/Cells.gd` (who lives where) and `Prison/CellLayout.gd` + `CellRooms.gd` (where the rooms are; see "The living prison" below). BDCC's cell blocks are three colour-coded areas (Orange general, Red high security,
Lilac sex deviant). A cell is block plus number, two occupants at most; cell 1 of each block is BDCC's own cell room and every other cell is a real map room, so cells are places you can walk into.
Eligible inmates (the player and the dynamic inmates, including inmates who are now slaves) get the first free place, the player first, so the next inmate of the player's block is their cellmate.
Assignments never reshuffle; removed characters free their place. Inmates settle in around 21:00 and leave around 07:00 with a fixed per-inmate offset of up to 30 minutes.
Tonight's attendance is recorded as `home` or `away` per inmate (`cell_presence`, valid only for that night): an inmate who settles, or who simply is not spawned, is home; one who is busy, still walking, or kept elsewhere (slavery, SoftSlavery, an enslave quest) is away. An away inmate is tried again every ten minutes; the system only knows home versus away, never where they are. Enslaving or freeing someone never changes their cell. The directory is the "Cell directory" button in each block's hall;
The "Cells" button in the Me screen shows the player's cell, cellmate and the cells they have learned by asking. (The text cell directory and "Cell info" buttons of the first version were removed.)

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

## Gangs (Milestone 7)

See `Gangs/Gangs.gd` (data and rules: GangService), `Gangs/GangAffairs.gd` (assignments, orders, incidents, churn, protection), `Gangs/GangGame.gd` (reads the real game and applies results) and
`Scenes/GangScene.gd` (the screens). There is no territory: gangs have a hangout room.

- **The gangs:** Ironhand (combat and status, meets in the gym weights room, no slaves), The Hush Market (trade and contraband, the laundry, no slaves) and The Collar Circle (control, the workshop, two slaves).
  Ironhand and the Hush Market are enemies (-55), the Hush Market and the Collar Circle are friendly (+45), Ironhand and the Collar Circle are neutral (-10). They form once eight eligible inmates exist; below that nothing forms.
- **Who joins:** at formation each gang gets exactly one member, its leader, chosen by fit to the gang's preferences plus leader score (never guards or staff, never the player). The control gang also takes two slaves
  when ten or more inmates exist. Then the affiliated share grows towards `ceil(0.40 x eligible)` (never more than the eligible), at most two recruits a day, each to the smallest gang (within one member) whose
  preferences fit best. Nobody is moved or removed to reach the share. Examples: 8 inmates -> 4, 9 -> 4, 15 -> 6, 23 -> 10, 30 -> 12. Nothing is reshuffled.
- **Two relation layers:** gang to gang is symmetric (-100..100: enemies at -40 or less, friendly at +40 or more); personal is directed (how a gang regards a character, -100..100) and separate from
  Affection, Trust, Respect and Fear. `effectiveStatus(character, gang)` gives both parts plus a combined score (personal + half the official relation) for AI; hostile is -40 or less.
- **Joining and leaving:** joining inherits the gang's enemies (just the table) and adds +5 personal with the new gang and -8 with each of its enemies. Leaving: -6 with the old gang, +4 with its enemies.
  Expulsion: -15 and -10 per severity step with the old gang, +3 with its enemies. Harm history (attacks -6, defeats -4, kidnapping -15, enslaving -25, ordered harm -8) is never reset. A leader decides by the
  player's personal relation plus Trust, Respect and Combat Reputation (weighted by the gang's emphasis), minus 6 per recorded harm: 15 or more joins, between -10 and 15 needs an introductory job, below that
  is refused with the reason. Switching to an enemy gang is refused for five days after leaving.
- **Standing, warning, expulsion, retaliation:** standing is the personal relation with your own gang. At -30 a warning (not more than every three days), at -60 expulsion with the reason. An expelled
  player gets two days of grace, then at most two attempts by a member in the same room (never with a guard present), and it stops for good once the player has beaten that gang twice, has Combat
  Reputation 40 or the members' Fear is 60.
- **Your own gang:** needs Combat Reputation 5 or one inmate's Respect of 40, two inmates willing to follow you (Trust and Respect), 15 credits, no gang and no unfinished retaliation. Pick a free name
  (3-24 letters, numbers, spaces, apostrophes, hyphens), a hangout, and members. Leader actions: invite, remove, change hangout (two-day cooldown), contribute to the treasury, order actions, disband. It
  never dissolves while you lead it.
- **Assignments:** one at a time, offered once every two days by the leader of your NPC gang, accepted explicitly, never forced. Defeat (a rival, 48 h, 6 credits, standing +8), deliver (a payment or an
  Illegal item, 72 h, 5 credits for an item), capture (beat the target, then hand them over, 72 h, 10 credits, standing +12; the gang holds them 36 h) and rescue (free a held member or beat the captor, 48 h,
  8 credits and standing +10, from `RESCUE_REWARD` and `RESCUE_STANDING` in `Gangs/Gangs.gd`). Failing costs 8 standing once; a target that vanishes cancels the job without blame; declining costs nothing.
- **Strength and protection:** strength is the sum over free members of 0.5 + level/20 (Weak under 2.5, Established, Strong from 5, Dominant from 8). In a gang, independent attackers are deterred by 10-55%
  by strength, gangmates barely attack, rivals are 25% more dangerous, a gang that hates you is 20% keener, each of its defeats by you makes it 15% less keen. Bounded 0.2 to 1.6; never immunity, and
  personal Fear still works as before.
- **Pacing:** one major gang incident a day, three days per gang, none with a guard in the room, fewer under high Security Attention or with a feared player. Rival gangs clash abstractly (20% a day per
  enemy pair, relation -2), the stronger may take a free non-leader member (3 days per gang, never the same victim within 3 days). A captive is held 36 hours, stays in their gang, is absent from their cell
  and never spawns, then escapes. One membership change every three days at most: a member leaves (Trust plus Respect towards the leader -60 or worse), defects to a stronger gang whose leader they admire, or
  is expelled by a leader who no longer trusts them.
- **Treasury:** NPC gangs start with 20 credits, the player's gang with 5 (of the 15 founding cost). Once a day each gang earns floor(active members / 3) (capped at 3) plus 2 per slave. Assignment rewards are paid
  from the offering gang's treasury: accepting reserves the credits, completing pays exactly that once, failing, expiring or cancelling releases it, declining reserves nothing. A paid job is not offered if the gang
  cannot fund it; an unfunded rescue is offered with a stated 0 credit reward. Orders spend only unreserved funds. The player may contribute to their own treasury but not withdraw, and cannot touch an NPC gang's.
- **Orders:** 5 credits, one a day, success 10-90% by strength, followers and the target's Fear. A failed order never deletes anyone: one of your free members is held 36 hours by the target's gang (if it has one) or comes
  back hurt, and your standing drops. Three failures against one target and they stop trying. Gang slaves are module state (BDCC's slaves are only ever the player's), away at night but not detained.
- **Not done:** gangmates joining a fight or helping after one (protection is deterrence only), assignments scaled by strength, a prison-snitch offer (a later milestone), and nurses and engineers in gangs.
- **Save data:** `SandboxState` schema 6 adds `gangs`. Older saves have none and the established gangs are created on first use; a new game resets it.

### The gang screens (Living Prison Repair Pass)

The gang logic is unchanged; only what the player sees changed (`Gangs/GangViews.gd` writes the pages, `Scenes/GangScene.gd` shows them).
- **Landing page:** who you are ("You are independent" / "You are in X"), then one short entry per gang (name, one line about it, where it meets, how it regards you) with a "View" button each, and "Found a gang"
  while independent. No member lists, treasury, raw numbers, slaves, jobs or logs.
- **A gang's page:** name, description, leader, meeting place, strength, a concise member count (with held and enslaved counts), your personal standing and, separately, how it sees you through your own gang.
  Buttons: Members, Relations, Join (when independent), and for your own gang Assignment, Contribute, Leave, or the leader's Orders, Roster, Hangout and Disband. Back everywhere.
- **Members:** one line each, marked (leader), (you), (held by X) or enslaved. **Relations:** each other gang on its own line with the word first and the number after, then "With you": personal standing,
  and what your own gang brings, kept apart.
- **Money:** the treasury and what is set aside for a job are only shown on the page of a gang you belong to.

## The living prison (Living Prison Repair Pass)

A real playtest showed that cells were a text directory, "in their cell" inmates were invisible, a 25-inmate prison showed one inmate and ten guards, and work existed only for the player. The repair makes the
simulation visible. Nothing here runs per frame: the director works in ten-minute buckets and when the player changes room.

- **Physical cells** (`Prison/CellLayout.gd`, `CellRooms.gd`): capacity is `max(8, ceil(inmates / 2))` (and never less than each block needs for its own inmates and for the highest cell anyone is assigned to).
  The cells are split among Orange, Red and Lilac by how many inmates each block has, deterministically. Cell 1 of each block is the vanilla player-cell room; the others are new rooms `sbx_cell_<block>_<n>` on
  the Cellblock floor, in a grid at most six columns wide that grows away from cell 1 (orange west, red east, lilac south), each with a number on the map, a bed icon and the block's colour, joined to its neighbours
  only. Cells are only ever added, never removed or renumbered. For 25 inmates (11 general, 8 high security, 6 sex deviants) that is 13 cells: 6 Orange, 4 Red, 3 Lilac. Entering a cell names its residents in the
  room header ("Cell 3 - Alec and Jeffery"). Only the player's own cell has Rest, stash and upgrades.
- **Schedule** (`Prison/PrisonSchedule.gd`): night (own cell, from each person's bedtime to waking, 21:00 and 07:00 give or take 30 minutes), morning (cell block halls, showers, canteen, halls), work (the workplace during
  your own shift, otherwise halls, canteen, yard, gym), leisure (gym, canteen, showers, yard, the underground, your gang's hangout) and evening (halls and cell block halls). Every person has stable offsets and the
  choice changes every two hours. Priority when reasons clash: scripted scene, captivity/punishment/slavery, active interaction, medical or unconscious, work shift, bedtime, gang hangout, leisure. Higher always wins;
  anything busy is never moved.
- **Population director** (`Prison/PopulationDirector.gd`): the "ring" is the player's room and everything within two steps on the map. Inmates whose scheduled room is in the ring get real pawns (at the edge of the ring so
  they walk in, or inside their cell if they were asleep or just woke); a pawn in the ring whose plan changed is sent there with BDCC's own HangoutAt goal, so bedtime, waking and the day's moves are walked room by room;
  a free pawn outside the ring that the schedule does not bring back is removed (the character is untouched and simply not shown). Share of the pawn limit: inmates 60%, guards 20%, nurses 10%, engineers 10% (guards
  are only trimmed, never added). A room holds at most 2 in a cell, 3-7 in a hub, 6 at a workplace. Observed with 25-30 inmates: 3-8 inmates and 0-2 guards in the visible area at every time of day.
- **NPC jobs** (`Work/NpcJobs.gd`): about two in five inmates have one of the three jobs (mine 6, workshop 5, laundry 4 places), stable across saves, and the same people turn up at the same workplace during their own
  shift window. A worker who is held, enslaved, moderately or severely injured, or on a rare sick day (about 6%) misses work. The player learns a job by seeing the person work, being coworkers, or asking
  ("Their work?" in conversation); only then does the conversation show it.
- **One way to mine and work:** the vanilla informal mining credit and the second Work path are gone. Paid work needs the job from the canteen job board; the mines show "Start mining shift" (disabled with the reason
  otherwise) and the workshop and laundry show their shift button always (disabled with the reason: no job / different job / today's shift done / outside the arrival window). `Me > Work` says "You are unemployed. Visit the
  Job board in the canteen." The canteen is marked on the map until the board is first opened, and a one-time message tells you where jobs are.
- **Workplace events** (`Work/WorkEvents.gd`): after a completed shift there is a 25% chance of one event, never two on one day, and the same coworker is not featured again within two days. Five families: a supervisor
  mistreats a coworker (step in, challenge, calm it down, ignore), a rival harasses you (stand up, fight, back down, tell the supervisor, avoid), a coworker request (workload, cover, loan), an opportunity or hazard
  (contraband, theft, accident) and, only with a mean rival, being cornered alone (fight, pay, talk down, shout for the guards). Consequences are real: feelings, Security Attention, credits, work warnings (never
  dismissal on their own), injuries and real fights. A rival beaten twice stops, a fearful rival (Fear 40+) stops, beaten or humiliated three times they ask for another job, and after three failed attempts one with a gang
  complains to it instead. A waiting event survives save and load and resolves exactly once.
- **Visible incidents:** two inmates in view who cannot stand each other (enemy gangs, or affection -0.3 or worse) may start BDCC's own fight; at most one every three hours. In Look around the player can help either
  side or try to break it up (chance from Fear, Respect and Combat Reputation, 10 stamina). Taking a side ends their fight and starts one between you and the other person: BDCC has no three-way fights.
  Helping a restrained inmate uses the existing Talking "Help with restraints".
- **Reputation bars** (`UI/SignedBar.gd`): Combat Reputation and Defiance as -100..+100 bars from BDCC's own ProgressBar, zero in the middle, red/orange to the left, green/cyan to the right, with the number, the band,
  one sentence and a tooltip. Defiance's wording is neutral.
- **Saves:** schema 7 adds `npc_jobs` and `workplace`. Older saves load with defaults; cell rooms are rebuilt from the stored assignments; nothing else changed shape.

## Persistent NPC lives

- **Presence:** every persistent inmate is a real `CharacterPawn` that always exists (45 is the cap; measured with 60 inmates, 82 pawns in all, the whole prison costs about 100 ms per ten simulated minutes, the
  director about 6 ms, the map markers about 12 ms, and the saved state about 92 KB). No pawn is created or removed because of where the player is, how far the map is zoomed or what the player visited recently.
  If another system deletes a pawn, the director brings it back in the room its presence record had, doing the same thing. Staff are never added or removed by the director.
- **Daily routine:** one seeded plan per inmate per day (`DailyRoutine.planFor`): fixed obligations (sleep in the exact cell, work shift, held or enslaved, gang leader hangout window) and variable ones
  (meals, shower, gym, yard, underground, common hall, cell, social, gang hangout, leisure) with varying lengths. The plan is stored for the day, so entering a room never rerolls it. The director moves people
  through the real map graph; after a long time skip people are moved along their paths toward where the plan has them.
- **Activity text:** sleeping in their cell, heading back to Cell N, relaxing, working, heading to a place, talking with someone, at a gang hangout. Only an inmate who has arrived in the exact cell counts as asleep or home.
- **Cells:** the layout is compact (turns and branches, at most three or four rooms in a straight line). Cell labels read "Orange Cell 2" as the title and "Residents: A and B." in the description. The three player
  cells of the original six rooms are cell 1 of each block; the three halls stay halls because they are the spawn, quest and Leave rooms (the one documented exception).
- **Gangs in person:** joining, intro jobs, reports, handovers, leaving and leader instructions happen in conversation with the leader; the Me > Gangs screen is informational. The leader has a hangout window
  (about 15:00 to 17:30) and is normally there with a member. Intro jobs are themed: Ironhand defeat a named rival, Hush Market carry a package to a member of a friendly gang, Collar Circle capture or defeat
  a target. Finished jobs are paid only when the player reports back. Leaders adjust Trust and Respect for requests, joining, finishing and failing.
- **Map badges:** G green is the player's gang, blue friendly, yellow neutral, red enemy, shown beside the O, F, N letters once the gang is known, with a tooltip and a legend in words.
- **Help in fights:** a friend, owner, gang mate, leader or trusted ally who fights asks once per fight if the player can notice and act. Options: Help, Break it up, Refuse; consequences depend on the bond. Refusing an
  owner is only recorded.
- **Reputation bar:** value text such as "+6 - Unproven" is centred above the bar, the metric name sits to the left, with more space below.
- **Saves:** schema 8 adds `routines` and `presence`. Schema 7 saves load with fresh state and the first director run builds the plans and records from current positions without moving anyone; loading never
  rerolls today's plan. Newer schemas are not downgraded.

## Playtest correction pass

- **Cell doors:** a cell opens towards every spot that belongs to its block (the hall, cell 1 and every place a later cell can take), not only the cells that existed when it was built. The old count-dependent doors left each newly grown
  cell without a way in from the cell it was built next to (the older room had no matching door), which is the isolated cell seen in play. `CellRoutesBootTest` builds every cell count on the real world, both as the game starts and as it grows,
  and checks real routes, drawn connections, no overlaps and no unreachable room.
- **Loading:** the world edit `SandboxPopulationBootstrapWorldEdit` runs when a game starts or loads, after the map and before the first frame. It assigns cells, builds the cell rooms, makes today's plans and puts every inmate where their plan has
  them now (or at the point on the real route their activity's start time allows). People with a presence record keep their place; the same save always gives the same places. If the transitions are already built, late cell rooms are wired.
- **Work crews:** NPC coworkers work the same configured window as the player's job (mine 08:00-10:00, workshop 10:00-12:00, laundry 12:00-14:00). They set off early enough, by the real route length, to be at the workplace about four to ten minutes
  before the shift (measured: one room takes about a minute), so at the exact start they are there and described as working in the mine, workshop or laundry. After the shift they "finish their shift" for ten minutes and then go on to their next
  activity. When the player starts a shift the coworkers who are there stay and work it with the player; the shift screen names them, work events only involve people standing in the workplace, and when control returns they are still in the room,
  finishing up, before they leave.
- **Gang talk:** a leader answers "Who leads it?" in the first person. The introductory assignment is a short speech by the leader (no reward data in their mouth) and one panel (Objective, Reward, Failure, Time limit). Accepting gets a short answer
  and one system line. Accepted assignments are in the quest log. Beating the target counts in every way a fight can end for the player's benefit, including the NPC giving up before the fight; the player surrendering, walking away, an unrelated
  NPC winning, or an unfinished fight do not count. Reporting a finished introductory job pays once and makes the player eligible; the leader then explains the gang's three commitments and the player agrees or says "Not yet" (the job is never
  repeated). Joining gets the leader's welcome, then the facts.


## Ownership and slavery (Milestone 8)

### What BDCC already had, and what was reused

- **The player owned by an NPC** is `SoftSlavery` (a special relationship stored by the relationship system, keyed by the owner's character ID, holding an `NpcOwnerBase` with level, influence, tasks, punishment points, the keyholder
  lock and BDCC's own approach days). It starts from the "Ask to become slave" and "Offer to enslave" talks, nemesis ambushes and debug scenes, and ends through "Ask freedom" (a price of 500 to 2000 credits scaled by influence),
  attacking the owner (each win lowers influence, zero ends it) or reaching the top level. Owners approach the player with their own goal and run owner events (approach, punishments, sex, talk). This was kept as it is.
- **The player owning NPCs** is `NpcSlave` on the character, the `Slaves` character pool, `NpcSlaveryModule` (enslave, free, slave space), the slave menu (`SlavesCheckScene`, `SlaveTalkScene`), `SlaveActionBase` actions, slave activities (prostitution,
  walkies, stocks, slutwall, milking), random slave events (including a silent escape), and obedience, broken spirit, love, despair, trust, fear and unhappiness values on the slave. This was kept and used.
- **What was weak:** a slave left the world when enslaved (the pawn was deleted and the character moved to an abstract pool, back only inside an activity); an owner was treated by the module as "kept elsewhere" and was never directed; an owned
  player was blocked from jobs; BDCC's freedom price was out of reach; a slave could vanish on a silent random roll; nothing physically tied an owner to a cell or a time. Those are what changed. The slave stat system, the owner events,
  the punishment events and the NPC slavery activities were not touched.

### The player owned by an NPC

- **Style:** from the owner's personality (mean, dominant/submissive, naive, level-based power): Lenient (a check-in about every third night, a demand about every four days, slow escalation, room to negotiate, light punishment, weak
  protection), Controlling (every other night, every three days) or Harsh (every night, every two days, fast escalation, no room, heavy punishment, real protection). It never changes for a character and is shown with an explanation.
- **Check-in:** the owner expects the player in the owner's own cell between 21:00 and 23:00 on the nights their style asks for (reminded once at 20:30; early from 20:30, late counts until 00:30). The owner walks to their cell from 20:15 as part of
  their routine. In the cell the owner's talk menu offers "Report in", and the owner answers for early, on time or late. The obligation is a Side Tasks entry with the owner's cell, block and time, and learning it comes with it.
  Excused with no warning: stocks, slutwall, unconsciousness, treatment, guard enforcement, recovering from a lost fight, an owner event, a hard slavery scene, the owner unavailable (captive, busy, absent, no cell), or no route to the cell.
- **Demands:** one at a time, never closer than the style's gap (two days at the least), only in the daytime and only when possible right now: credits (3 to 6, never more than the player has), a plain item the player carries, contraband the
  player carries (harsh owners only), a work shift (only with a job and an open shift), being at the owner's cell at a time, or beating a valid inmate (not lenient owners). They are told in person (the owner walks up, or the player
  talks to them), can be agreed to, eased (halved payment, a day more, or an unsuitable task swapped for a small payment: depends on trust, respect, affection, style and recent compliance, no dice) or refused. Done once, rewarded once.
- **Compliance and escalation:** no obedience number: recent fulfilled and missed days, warnings, the last consequence, grace, the demand. A miss is a warning first; piling up (style decides how fast) gives a demand for compensation,
  then the game's own punishment event or a fight. All of it is delivered only when the owner meets the player. Answers: apologise, submit, pay, ask for easier terms, resist (fight or back down at the last moment, which is milder than
  losing). Winning ends the consequence, makes the owner keep away for two days and fear the player, and counts towards release; ownership stays.
- **Protection:** an owner's credibility (their power against the attacker, the attacker's fear of them, their gang's strength, having hit back before) shields the player, scaled by style, halved when they are not around, weakened by recent
  fight losses. The multiplier is never below 0.35, and with gang protection, fear and reputation the whole attack interest is never below 0.1. The screen says Weak, Moderate or Strong with plain reasons. An owner standing in the room steps in
  and fights the attacker; the owner remembers aggressors and may hunt one (once every four days, walking there, giving up after two failures or two recent losses).
- **Volunteering:** "Ask for protection" appears for ordinary inmates only. Their answer comes from submissiveness, respect, affection, desire, ability to protect, fear and gang status. The terms (style, check-in frequency, demands,
  protection, the minimum three days) are shown first and nothing happens until the player confirms twice.
- **Ways out:** negotiated (after the term, with trust and respect or high affection; a last payment of 0, 5 or 10 credits by style), buyout (30 to 60 credits by style, relationship and protector; not within the term, not from an owner who
  loathes the player), defiance (beat the owner on 2 separate days, 3 for a harsh one), a gang's help (standing 25 or more, a strong enough gang; costs standing, treasury and the owner's trust), or the owner letting go (afraid and beaten, or fond
  after a long time). BDCC's own influence route still works.

### The player owning NPCs

- Slaves stay in their own cells as ordinary persistent inmates with a daily plan. Roles (one at a time, changed in person once a day): Free routine (trust slowly recovers), Earner (an afternoon post at the prostitution spots; 2 to 4
  credits for a day really worked, credited once a day, collected in person, nothing when hurt, held or kept from the post; it wears trust down), Attendant (waits in the cell block's common hall in the morning and evening; helps if you are
  attacked in the same room), Rest (stays in their cell by day; injuries and trust recover). "Ask them to report to your cell" is a one-evening duty given in person (see below).
- How they feel is described from directed Trust, Respect, Fear and Affection (loyal, intimidated, resentful, defiant, recovering, uncertain) and nothing is stored. Defiant slaves refuse the hard duties, resentful ones refuse earning and reporting.
- Escape is always telegraphed: neglected, unhappy slaves first get a warning (a message and a Side Tasks entry), the next day make a visible attempt for the exit, and only if nothing is done a day later get away, as ordinary inmates who remember it.
  Answers in the slave menu: talk them round, warn them off, treat them better, stop them by force, or let them go. Releasing someone raises their trust and affection a lot.
- Nothing is spent or earned twice: income is once per slave per day and survives save and load.

### Saves

Schema 9 adds `ownership` ({owner, slaves, last_release, tick_day}). A schema-8 save loads with an empty record; BDCC's own owner and slaves are picked up the next time the game runs with fresh schedules and no warnings, in their own cells.
Malformed data is repaired on load, and characters that no longer exist are dropped.

### Continuity and economy rules (correction pass)

- Enslaving keeps the very same pawn, in its room, with its cell and routine. Escaping does the same in reverse: ownership is cleared and the inmate carries on from where they stood.
- Nothing teleports a slave. Commands are given in person; "Ask them to report to your cell" is checked at once (held, badly hurt or no route: refused with the reason) and is a real walk in the evening (19:30 to 21:30). It ends exactly once: arrival, or a clean cancel with a message if they are held, badly hurt or cut off. Being busy only delays it.
- Earners share customers. Per day: the first earner 2 to 4 credits, the second 1 to 3, every further one 1, 8 credits a day for all together. The day's count and total are saved (`earn_pool`), so loading never pays twice or resets the cap. Slave space is not capped by the game (it costs 30, then 10 per slave owned, per extra space), so the daily cap is what bounds income: at most 56 credits a week.
- Loyal defenders help only when physically in the room, never while held, badly hurt or busy; attendants help unless defiant or resentful; exactly one helper steps in per attack.

### Owner visits and the report order (final correction)

- The owner walks to the player through real rooms, one step at a time, using BDCC's own approach goal. The event starts once, when they stand in the same room. If the player moves, the owner keeps following on foot.
- If the owner is held by a gang, badly hurt, busy (being knocked out counts as busy) or cut off (no route), the visit is postponed without penalty and not weighed again for half an hour. A missing owner pawn is restored by the population system at its saved place (else where its routine has it), never beside the player.
- Saving and loading mid-approach keeps the owner walking (pawns and their goals are saved); nothing starts twice. The retry delay is not saved, so a load just weighs the visit once more.
- "Ask them to report to your cell": the player speaks to the slave in person (Slave, then the order). The order is for that evening, and the slave carries on with their ordinary day. From 19:30 to 21:30 they walk from wherever they are to the player's cell and the order ends on arrival. If they are held or badly hurt, it is cancelled with a message and no blame; if they are busy or knocked out it is only delayed and resumes if they are free inside the window, otherwise it lapses at the end of the day without blame.
- Slave menus opened for a slave who is not in front of the player are informational (where they are, what they are doing) and offer no commands.

### New slaves, nights, roles and how enslaving feels (manual-playtest correction)

**The soft-lock.** An owner event scene that could not start (the owner is not in the room) had no buttons. The owner relationship could begin with the owner far away (console and debug conversions, which then run the owner's intro). Now: the scene says
who they are and shows the terms with one Continue; a talk that was open ends with one Continue; the module records the owner at once and gives a day of grace before the first visit (never on the same frame); agreeing to "Ask for protection" ends on a
screen with the terms and Continue. Friend or Nemesis ends with its own message and the Owner replaces it (one special relationship per character).

**A new slave.** The same pawn, in the same room, with the same cell, marked *Awaiting instructions*. They do not take a free routine, wander off or choose a distant activity, and nobody starts planning to run in the first two days or while waiting. If the game's
own kidnap scene brought them ("bring to your cell"), they walk to the player's cell on their own through real rooms and wait there. The player talks to them and chooses **Give instructions** (always available while they are here and able to answer: it does not depend
on their mood for chat or flirting, on liking the player, or on any dice; only unconsciousness, being held, being busy elsewhere, or not being in the room blocks it):

- Role, with what is expected: Free routine ("You may follow your ordinary prison routine. Report only when summoned."), Earner ("Work the afternoon prostitution locations and keep the agreed earnings for collection."), Attendant ("Stay around my cellblock
  during your free periods and help me if trouble starts."), Rest ("Avoid duties and recover.").
- Night arrangement: "Sleep in your own cell.", "Sleep in my cell each night." or "Keep your own cell and report only when ordered."
- Confirmation: "Those are your instructions." or "I'll decide later." (they keep waiting; the Ownership screen says *Awaiting instructions*; it is never reopened on its own).

They answer in character from Trust, Fear, Respect and Affection: a defiant slave refuses what they would not do. Later changes use the same screens, in person, once a day for the role, and start about half an hour later (no instant change of room).

**Sleeping in the player's cell.** From 20:30 they walk over, through real rooms, and are there before ordinary bedtime where the walk allows. The activity reads "heading to your cell" and then "sleeping in your cell". They stay overnight and leave when their own plan has
them wake. Their own cell stays theirs and reports them away. Held, knocked out, busy or cut-off slaves are excused and are never moved. It is separate from the one-off "Report to my cell".

**How enslaving leaves them feeling** (applied once, recorded on the slave so a load never repeats it; one coloured message):

| How | Trust | Affection | Respect | Fear | Desire |
|---|---|---|---|---|---|
| Forced (breaking quest) after a fight win | -25 | -12 | +4 | +22 | 0 |
| Forced, no recent defeat | -25 | -12 | -6 | +22 | 0 |
| Forced, they had surrendered (submission) | -12 | -4 | +1 | +12 | 0 |
| Submission (the "Enslave!" talk option, not already warm) | -12 | -4 | +2 | +12 | 0 |
| Voluntary (the talk option, already warm: affection 20+ and trust 15+) | +3 | +3 | +2 | 0 | 0 |
| Unknown or debug conversion, every axis exactly neutral | -10 | -5 | -2 | +8 | 0 |
| Unknown or debug conversion, existing feelings | unchanged | unchanged | unchanged | unchanged | 0 |

BDCC offers no purchase or transfer of a slave to the player and no scripted slave story. If one is ever added it counts as unknown.

**The map badge.** A purple "S" for somebody the player owns, after the relationship tag and the gang badge ("F S", "N G S", "G S"), tooltip "Your slave.". A gang's own slaves do not get it. It appears and goes the moment somebody is enslaved, freed or escapes.

### Who would look after the player

Before: a single score (30% dominance, 25% respect, 15% affection, 15% desire, 15% personal "ability", 10% trust) had to reach 0.25. "Ability" was fighting strength measured against a typical attacker plus the gang's strength, which almost nobody reached, so nearly
everybody was "not able to protect anyone"; any submissive streak (over 0.2) printed "would rather be looked after"; strangers scored about 0.02 and always said no; gang leaders were judged by personal stats only; all the reasons were joined together.

Now: capability and willingness are separate, and both must hold (`Ownership.protectorDecision`).

- *Capability* (at least 0.35): how they rank among the inmates in strength (0 to 1), blended with their gang's strength (the leader leans on the gang more, 0.7 against 0.4), times 0.7 with a moderate injury and 0.3 with a severe one. Held people cannot.
- *Willingness* (at least 0.40): 0.36, less 0.2 for each point of submissiveness, plus 0.30 respect, 0.20 trust, 0.15 affection and 0.10 desire (as fractions of 100), minus 0.4 if they fear the player and do not trust them, minus 0.6 for a hostile history, plus 0.30 for the
  leader of the player's own gang (0.12 for a member), minus 0.5 if their gang is hostile to the player (0.3 if it is an enemy of the player's gang), minus 0.2 if the player's own gang is already strong. Only somebody strongly submissive (0.55 or more) refuses on temperament alone.
- A refusal is one primary reason in their own words, at most one more, and a direction (build trust, earn respect, let them recover, improve gang standing, settle things). The terms (style, check-ins, demands, protection band, minimum term) are still shown before acceptance.

**How to get a slave in BDCC** (shown on the Ownership screen while the player has none): buy room from Socket (the cell expansion, 30 credits, then 10 per slave you can already keep for each extra space); beat an inmate in a fight; press **Enslave!** (needs a collar, free
arms and room) and choose the kind of slave; complete the breaking quest (tasks in the personality status effect; choking rerolls them); press **Kidnap!** after a defeat and take them to your cell; or, with high Alpha reputation, use the **Enslave!** talk option on a submissive inmate.
Afterwards talk to them and choose Give instructions.

### Coherence pass: bugs, rules and limits

**Root causes**

- *"!Error: npc character is not found to say text".* The protection refusal printed the candidate's reason inside `[say=npc]`. BDCC resolves the speaker of a `[say=...]` line through the scene on top of the stack (`resolveCustomCharacterName`), and the Ownership scene
  did not define it. It now does (and shows the candidate). The test helper draws every screen with the scene on top of the stack and fails on any "!Error" text.
- *Two owners.* Nothing checked for an existing owner: BDCC's own relationship system keys special relationships by character, so a second `SoftSlavery` for another character simply got added, while the module's single owner record only knew one.
  Every route (the talk offers, the Nemesis ambush, debug and console conversions, old events) ends in `startSpecialRelantionship`, so the check is there.
- *Duplicated terms.* The owner relationship notification repeated the whole terms paragraph that the acceptance panel shows. The notification is now the game's own one line; the terms are on the panel and on the Ownership page.
- *Defeat tasks.* Gang jobs and owner demands each had their own entry points for "the player beat this person". They now share `Module.onPlayerBeatNpc`, called once per encounter by the fight aftermath (pain, lust, the target submitting) and by an NPC's surrender before the fight.
  An encounter counts once however many times it is reported. It never counts when the player loses, submits or leaves, or when somebody else beats the target. The old tests reached the helper through `onNpcSurrender` and `onFightAftermath` directly; the new test drives
  a real `GenericAttack` interaction (the same `doFightAftermath` the fight scene calls, and the real "surrender" action).
- *Population.* BDCC's morning wave and spawner create a new character whenever nobody is free to pick one, and with a persistent prison nobody ever is: everything grew to the cap (45 inmates; staff at the pawn-limit shares, 18 guards, 11 nurses and 8 engineers at a limit of 90).
  Sources: `InteractionSystem.spawnMorningWave` and `trySpawnPawn` (through `PawnTypeBase.generateCharacterID`), and events and scenes that call `NpcFinder.grabNpcIDFromPoolOrGenerate` (these only create below a pool of about 25).
  Stored characters live in pools; every inmate and every staff member in a pool is a persistent pawn; static story characters are not in these pools and are never touched; generated characters are the ones above.

**One owner, and rival claims.** There is one authoritative owner: the one in the module's record if it is valid, otherwise (an old save with several) the owner with the lowest character id; the others lose the status only, with one message. A claim on a player who is already owned is a dispute:
the owner may contest it only if they are free, awake, not badly hurt, not held and able to get there (otherwise it is postponed with no cooldown used); the claimant must be able too; a claimant who is much weaker or timid backs down; a lenient owner gives way to somebody stronger;
otherwise it is decided with BDCC's own quick-fight rule (strength score squared, with the gang behind each, injuries, a bonus for a harsh or controlling owner defending their claim and for the side the player backs). The loser is hurt (a minor injury) and the fight is recorded once for gangs and the owner's record.
Only the winner is the owner afterwards. At most one dispute every two days, and the same claimant not again for three. The talk offers open a scene where the player can back the owner, back the claimant or stay out of it; debug and ambush routes resolve it without a side.

**The owner coming to help.** When the player is attacked and nobody who is there helps, a free, awake, not badly hurt, not held owner who is within six rooms and can walk to the player may come running: at most once every two days, with a chance from how credible they are
(strength, fear of them, their gang) and their style (harsh most, controlling a little less, lenient least). They are put in the room for the incident (one message; never duplicated), the original attack is replaced by their fight (so combat, injuries and reputation count once), and their own routine walks them
back afterwards. If they cannot come, the retaliation they may plan later still applies. The Ownership page says whether this is ready, recovering (and until when) or unavailable (and why), never a number.

**The yellow Q.** Derived from live task state, never stored: the target of an accepted gang job (defeat, capture, rescue and the rival to beat), the recipient of a courier job, the gang leader to hand somebody to, deliver to or report back to, the owner to hand a demand to, report back to or check in with,
the target of an owner's defeat demand, and a slave who is about to run. Tooltip: "Task target: Defeat Alfred" or "Task contact: Report to Simone". Tracked module quests are exactly these (their Side Tasks entries read the same state). The base game's own quests have no generic target API, so they get no Q.

**Population.** Inmates arrive on a schedule (`PrisonSchedule.inmateLimit`): 10 on the first day, 12 on day 1, 21 on day 14, 25 by day 30, never above the soft target of 26 and never above the hard cap of 30; a prison that already has more admits nobody and loses nobody.
Dynamic staff are capped at 10 guards, 5 nurses and 5 engineers (the share of the pawn limit still applies below that: 6, 3 and 3 at the default limit of 30). Events that ask for a new character get an existing one once the pools are full.

**What Milestone 9 can use (nothing added here).** Prison-wide Combat Reputation and Defiance are two numbers on `state.reputation`, changed through `CombatConsequences.addRep` and displayed by the Me screen and the conversation summary; they would become per-character in a `npc_profiles` entry (already saved,
already reserved for per-NPC data). Every fight that involves the player reaches `Module.onFightAftermath(interaction, wonID, lostID, result)` and every fight between two others reaches `OwnershipGame.onNpcFightResult`: both are the places to record results for any NPC.
Talking shows the feelings line from `Module.getFeelingsSummary` and the Look around screen's fight actions come from `Module.getFightInterruptActions`: both are where a public reputation line would go. For "easy target" the inputs already exist: `Injuries.highestSeverity` and `attackInterestMultiplier`,
the directed Fear axis, `GangGame.power` and the quick-fight strength score (`calculatePowerScore`), and recent victimisation can come from the same aftermath hook. `getAttackMultiplier` is where the player-as-target version already combines combat reputation, fear, injuries, the gang's protection and the owner's.

**Nudity audit.** The guards' nudity warning and fine (Milestone 6) is still connected: `onSecurityTick` runs every ten in-game minutes, evaluates every free guard standing in the player's room (`evaluateGuardEncounter`), and starts `GuardEnforcement`. The measured frequency is in the test output.

### Ownership coherence pass

- **Reporting a completed demand** works at any time of day ("Report completed demand" in the owner's talk menu; the owner also carries a Q while it is ready). It is separate from the nightly check-in. Reward, once: Trust +3, Respect +2, Affection +1 (+1 Respect for beating somebody or carrying contraband). No Combat Reputation or Defiance change: that belongs to Milestone 9.
- **Protection:** once per in-game day, from anywhere in the prison, with no roll. Only hard blockers stop it (held, unconscious, severely injured, not around, in a fight or scene of their own); then nothing is used up and the Ownership screen says why. The owner arrives (announced, in the same room, never a second pawn), fights through the existing fight flow and may lose. Deterrence (`Module.getAttackMultiplier`) scales with the owner's credibility, but a strong gang behind the attacker or somebody who hates the owner is much less put off: it is never immunity. The screen says "Protection ready", "Protection used today" or "Protection unavailable: reason".
- **Help acknowledgement** (`HelpRequests.acknowledge`) is one shared, exactly-once thank-you after a joined fight is decided: owner Trust +4, Respect +4, Affection +1 and a minor warning forgiven (or the next demand a day later); friend Trust +3, Affection +2, Respect +1; gangmate Trust +2, Respect +2, standing +2; leader Trust +2, Respect +3, standing +3; anybody else Trust +1, Respect +1; lost after trying Trust +1. One full reward per person per day.
- **Meetings:** "My owner wants to meet today" is a pending meeting record on the owner (`meeting`: day, purpose, told). A hard blocker postpones it to the next day with one notice; the owner has until 20:00 to walk to the player, after which they find the player directly (a deliberate abstraction, once); it ends when the owner event starts; saved and loaded.
- **Evening at the owner's:** a valid evening check-in leads to the owner requiring, inviting or allowing a stay (by style; deterministic from day and owner). Staying uses the game's own sleep (`startNewDay` and `afterSleepingInBed`), once. On a stay the night may turn intimate, at most once in two nights, with a chance from style, lust, affection and trust: the owner asks (declining costs nothing), demands (can be talked out of it; refusing costs a little affection, never a Nemesis) or forces. The scene is the existing sex engine and the aftermath is the existing CONSENSUAL / COERCED / FORCED path (`Module.applySexConsent`).
- **Rescue:** after the player loses a fight to somebody who is not staff and is left restrained, the owner (same rules as protection, consuming the day's protection only when they actually come) arrives once and takes the restraints off with the game's own inventory calls. A harsh owner asks for something first (the player can say "not now" and is freed anyway). Guards' restraints are the prison's business and are never removed.
- **Milestone 9 hooks (nothing built):** `Module.onFightAftermath` and `HelpRequests.acknowledge` (one place where public standing, witnesses and gossip can read a result); `OwnershipGame.protectionFacts` (attacker gang and hostility, where a reputation read would add "who dislikes this owner"); `Ownership.pc_defeat` (a recent hostile defeat, where opportunistic targeting of a weakened player would start). Inmates do not pick on a restrained player yet.

### Owner actions, meetings and check-in outcomes

- **One ownership action at a time.** The two "Report in" entries came from the nightly check-in and from a "be at my cell" task (`type "report"`), both added by `Module.getOwnerTalkActions` (the Q marks had the same pair). Now the menu shows one, in this order: 1. "Report completed demand" (or "Hand it over" for credits, items and contraband), 2. "Meet with owner" (a scheduled meeting), 3. "Report in for the night" (a check-in; the report task is settled by the same report; "Report as ordered" only when there is no check-in), 4. the ordinary options ("Hear their demand"). When one is done the conversation returns to the owner menu and the next one appears.
- **Meeting purpose** is chosen once when the meeting is created (`Ownership.choosePurpose`) and saved: something owed (warning, compensation, punishment, by the level of the waiting warning); a finished demand to discuss (review); a new demand; a reward for notable compliance (a hard demand or three good days, at most once in three days); intimacy (style, lust and relationship, deterministic); otherwise ordinary possessive attention. The notices say only "wants to speak with you", "expects you for a warning", "has promised you a reward" and so on. The meeting is held when the owner's event opens (never by a different owner event) and ends in real dialogue: a demand to answer, the finished demand's report, the existing confrontation, a few credits with praise, an asked, demanded or forced night, or a conversation with a small style-shaped change.
- **A check-in's outcome** is chosen once when the report is accepted and stored in the check-in record: 1. an outstanding warning (the existing confrontation, then the evening carries on); 2. praise for notable compliance (Respect +1, Affection +1, a minor warning forgiven or the next demand a day later; never the task's own reward again); 3. intimacy (ask, demand or force, as before); 4. otherwise the stay, which the owner requires, invites or allows by style.
- **The stay** runs the game's own sleep (`startNewDay`, `afterSleepingInBed`, one autosave inside `startNewDay`) and then the vanilla `NpcOwnerSleepTogetherScene`: the Sleeping animation with the owner. It is only reached through the check-in (or a meeting that leads to it), never from reporting a task.

### Job offers, missed nights, rewards, pregnancy and Desire (manual-test correction)

- **A job offer is a real pending offer.** An owner's offered demand (and the gang leader's offered job) is saved, announced once in natural wording ("X has something they want you to do"), a Side Task ("X has a task for you"), a yellow Q on the owner ("Hear about the job from X") and the one action "Hear about the job" in the talk menu, whatever the owner's mood. The owner is already in the room: they start the conversation on the next tick. Elsewhere they walk to the player (BDCC's approach goal); after 20:00 the existing "finds you directly" fallback applies; a hard blocker postpones it once with one message; a lapsed offer takes its promise with it. The conversation explains objective, reward, time limit and the consequence, and only agreeing makes an active demand (refusing is a refusal: a warning is noted). The gang leader's offer has no walk (leaders stay at their hangout) but has the Side Task, the Q, the natural wording and opens straight away when you talk to them about gangs.
- **Missed nights.** Root cause: the check-in of the day that had just ended was replaced by tonight's new record (`startCheckin`) before it was judged (`closeCheckin`), so sleeping through a night cleared it unseen. The tick now judges the old record first, then counts required nights the clock jumped over (each once; the latest three are held against the player), then starts tonight's. One concise message; the existing escalation follows (harsh now starts at compensation, controlling and lenient at a warning).
- **Completion rewards.** The reward was stored owner -> player all along (Talking and the Encounters list read the same pair). What the player saw was nothing: no message was shown, and the report screen applied the reward inside the state's draw function, so drawing the screen a second time showed "nothing to hand over" instead of the owner's answer. The report is now applied once, remembered by the event (saved), and shown as one combined coloured message ("X's feelings changed: Trust +3, Respect +2, Affection +1"); Fear and Desire do not change.
- **Pregnancy.** Reused: `isPregnant`, `isVisiblyPregnant`, `isReadyToGiveBirth` and the eggs' `getFatherID` for the player, and the vanilla `NurseryTalkScene` (the nurse; birth is `GM.pc.giveBirth()` there). The owner reacts once to a visible pregnancy ("Wait... is that mine?" if recorded as father; questions, concern or jealousy by style, affection and desire for another father; uncertain wording when the parentage is unknown), in a conversation, a check-in or a meeting. An imminent birth takes the check-in before anything else (no intimacy, no bed): the player can go alone or let the owner take them to the nursery (they are put there once and 15 minutes pass once). The owner's record is cleared when the pregnancy ends.
- **Desire after sex** (directed, observer -> target, capped at 100): satisfying consensual sex raises each NPC participant's Desire for the partner (the player included: NPC -> player), a poor one lowers it (existing scaling); an NPC coercing (+3) or forcing (+5) raises the aggressor's Desire for the victim (the player or another NPC); a victim's Desire never rises, and the existing negative Affection, Trust and Fear stay; the player forcing an NPC changes nothing for the NPC's Desire. Owner nights go through the same aftermath exactly once (asked: consensual, demanded: coerced, forced: forced).
- **For Milestone 9 (documented, not built).** Desire is the NPC's wish; Respect and Fear decide how it is acted on: high Desire with low Respect and low Fear makes a coercive or forced approach more likely; high Desire with ordinary or high Respect makes them ask; high Desire with high Fear makes a cautious or submissive approach, or avoidance, by personality; low Desire means little sexual interest whatever the vulnerability. Nudity, bondage, body writing, injuries and recent defeats (`pc_defeat`) raise the perceived opportunity; owner and gang protection (`protectionFacts`), guards and witnesses lower it. The inputs are all in place (`getFeeling`, `Ownership.pc_defeat`, `Module.getAttackMultiplier`); nothing uses them for targeting yet.

### Punishment and the owner's evening

- **Where it went wrong.** A punishment is the game's own `Punish` event, started by this module's owner event as a child; its result comes back through `reactEnded` with the tag `punishment`. Two things lost the parent: the child chain defaults to `SUB_END` (ending this event too), and the base class ends the event for the action id "endEvent" before any state code runs (so "settled" could never carry on to the night; it now uses its own id).
- **Continuation.** `SandboxOwnerOps` now handles `reactEnded` itself and keeps a saved continuation (started, which punishment, done, whether it decided the night). Punishments that put the player somewhere (stocks, slutwall, being sold on, the test subject room) replace the night: the check-in is covered (never a miss), no bed is offered, the owner says so. A punishment the player fought off (the owner's hold on the player fell) does not force the player back to bed. Everything else (a reprimand, compensation, rough sex, clothes ripped, restraints, apologising, backing down, losing) returns to the stay and the real sleep scene.
- **Active delivery.** A waiting warning, compensation or punishment is one saved meeting (a lighter pending meeting becomes it), shown on the Ownership screen, in Side Tasks (without the details) and as a Q on the owner; it comes before an offered job in the talk menu; the owner walks to the player, starts shortly when already in the room, finds the player after 20:00, postpones once when blocked, and is held once: inside the check-in if the player reports first, or in the daytime (the player still owes that night's check-in unless the punishment covers it).
