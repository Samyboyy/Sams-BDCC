# Core patches

Log of every edit to base-game (non-module) files. Avoid core edits when an extension point
exists (Module registration, GameExtender hooks, InteractionGoal, etc.).

## Entry template

- **File:**
- **Reason:**
- **Functions changed:**
- **Compatibility risk:**
- **Reapply after upstream update:**

## Current patches

### 1. Consent-aware sex aftermath

- **File:** `Game/InteractionSystem/PawnInteractionBase.gd`
- **Reason:** `doSexAftermath` turned satisfaction into affection and lust (`(min(domSatisfaction, subSatisfaction) - 0.5) * 0.4`
  and `(averageSatisfaction - 0.5) * 0.5`) regardless of consent. Because the legacy entry is shared by both characters,
  forcing an NPC, or being forced by one, could raise their affection and start a Friend relationship.
- **Functions changed:** `doSexAftermath` only. It calls
  `GlobalRegistry.getModule("SandboxOverhaulModule").applySexAftermathAndShouldRunVanilla(self, _sexData, theSexResult)`.
  Both the legacy `affectAffection` and `affectLust` lines now run only when `runVanillaRelationshipAftermath` is true.
  The module is fail-closed: it returns true only for an explicit CONSENSUAL classification.
  COERCED, FORCED, UNKNOWN and any missing or malformed input (no result, roles, interaction ID or state) return false. Everything after those lines is unchanged.
- **Compatibility risk:** Low. If the module is missing, both formulas run as before.
- **Reapply after upstream update:** Re-wrap the two `affect*` calls in `doSexAftermath` with the added lines.

### 2. NPC list shows the five directed feelings

- **Files:** `UI/NpcList/NPCRow.gd`, `UI/NpcList/NPCRow.tscn`
- **Reason:** Show Affection, Trust, Respect, Fear and Desire (NPC towards the player) instead of the legacy shared
  affection and lust, with a tooltip explaining each.
- **Functions changed:** `NPCRow.setRelationShipData` returns early with module text when the module is present.
  The legacy text is still produced when it is not. In the scene, the `Relationship` label's `rect_min_size`
  changed from `(140, 50)` to `(250, 72)` so three lines fit. The Friend, Nemesis and Owner label is untouched.
- **Compatibility risk:** Low. Legacy values are hidden here (patch 3 does the same for the Talking screen) but still drive AI and Friend/Nemesis.
- **Reapply after upstream update:** Re-add the early-return block at the top of `setRelationShipData`
  and the label size.

### 3. Talking screen shows the five directed feelings

- **File:** `Game/InteractionSystem/Interactions/Talking.gd`
- **Reason:** `init_text` showed "{reacter} affection with {starter} is X%. Lust is Y%." from the legacy shared values, which
  contradicted the NPC list. This is display only: the legacy values still drive AI scoring and Friend/Nemesis.
- **Functions changed:** `init_text`, one line. With the module present it prints
  "{npc}'s feelings about {other}: Affection .., Trust .., Respect .., Fear .., Desire ..". The NPC is the reacter, or the
  starter when the player is the reacter. Without the module the original line is printed.
- **Compatibility risk:** Low. `getAffectionString` and `getLustString` are now unused by the module path but remain.
- **Reapply after upstream update:** Re-add the `if(sandboxModule != null):` branch around the `saynn` call.

### 4. Talking reports its outcomes to the module (Milestone 1D)

- **Files:** `Game/InteractionSystem/Interactions/Talking.gd`, `Game/InteractionSystem/PawnInteractionBase.gd`
- **Reason:** Conversation outcomes changed only the legacy values, and the legacy percentage messages contradicted the directed axes.
  The module now applies a small fixed legacy delta (100:1 with the axes, through `RelationshipSystem` so AffectionChange and LustChange
  events still fire, with the legacy message suppressed) plus the directed change, once per outcome, with one combined message.
- **Functions changed:**
  - `Talking.gd`: added `getSandboxNpcID`, `sandboxActive`, `sandboxConversationOutcome` (returns true when the module applied the outcome)
    and `sandboxChatOutcome`. With exactly one `"pc"` participant the NPC is whichever role is not the player and the module records
    `directed_relationships[npc]["pc"]`; with no or two players the module does nothing and the old behaviour stays.
    `chat_asked_do`, `flirt_pickupline_do`, `flirt_flirted_do`, `offered_sex_do` and `offered_self_do` ask the module first and run the old
    `affectAffection` / `affectLust` formula and the `GotRefused` event only when the module did not handle the outcome.
    Chat disagreement or "whatever", flirt rejection and sex refusal are ordinary social boundaries, so they send no `GotRefused`
    (it can start a Nemesis, up to about 36% for a very mean, hostile NPC). Bad social events are reserved for future hostile responses.
  - `PawnInteractionBase.doReactToChat` gained `applyLegacyAffection:bool = true` and `reactToLustFocus` gained `applyLegacy:bool = true`.
    The defaults keep every other caller identical; `Talking` passes `false` when the module handled the outcome.
- **Compatibility risk:** Low. Without the module nothing changes. `CharacterPawn.affectAffection` and `affectLust` are untouched, so every
  other caller keeps its legacy messages.
- **Reapply after upstream update:** Re-add the helpers and the guarded calls in `Talking.gd`, and the two optional parameters.


### 5. Combat outcomes, surrender and combat reputation (Milestone 2)

All hooks call `GlobalRegistry.getModule("SandboxOverhaulModule")` and do nothing when it is absent, so vanilla behaviour is unchanged.

- **`Scenes/FightScene.gd`**
  - `submit` action: sets `battleEndedHow = "submit"` (it used to stay empty and became `"pain"` at the end) and the new `battleSubmitter = "pc"`. When the enemy surrenders, `checkEnd` sets `battleSubmitter = "enemy"`. Existing readers only compare `"lust"` on a win.
  - `endbattle` action calls the new `sandboxFightEnded()`: it measures how hurt the winner is into `battleMargin` (larger of pain and lust as a fraction of the threshold) and, once per scene (`sandboxReported`), first calls `onFightInjuries` (Milestone 3: both fighters' pain as a fraction of their threshold, before `onFightEnd`) and then calls `onFightSceneEnded`, which acts only on Fight Club `"arenafight"` fights. This is the real Fight Club hook: every arena scene (`AvyTalkScene`, `AvyFirstArenaBattleScene`, `AvyFinalArenaBattleScene`) runs `FightScene` with the battle name `"arenafight"` and ends through `endbattle`.
  - The three `endScene([battleState, battleEndedHow])` calls now also pass `battleMargin` and `battleSubmitter`.
- **`Scenes/WorldScene.gd` `_react_scene_end`:** the fight results sent to the interaction also carry `how`, `margin` and `submitter`.
- **`Game/InteractionSystem/PawnInteractionBase.gd`**
  - New var `sandboxDefeatKind` (saved as `"sdk"`): how the player lost, `""`, `"resisted"` or `"surrendered"`.
  - `doFightAftermath`: calls `onFightAftermath` (only fights with the player count).
  - `getScoreTypeValueGenericInternal`, `"attack"` score: multiplied once by the module's attack multiplier when the target is the player.
  - `calcFinalActionScore`: `"punish"` and `"punishMean"` scores are multiplied by 1.25 after a resisted loss or 0.65 after a surrender.
- **`Game/InteractionSystem/Interactions/GenericAttack.gd` and `CaughtOffLimits.gd`:** the player's own "Surrender" choice calls `onPlayerSurrender`. An NPC surrendering changes nothing.
- **`Game/InteractionSystem/Interactions/Talking.gd` `init_do`:** the player starting an attack calls `onUnprovokedAttack`.
- **`Scenes/MeScene.gd` reputation menu:** shows the Combat Reputation and Defiance values, their bands and a one-line definition each.
- **Not changed:** BDCC inmate reputation, Fight Club's own systems, `LostFight` social events, Nemesis, scripted and quest fights.

### 6. Lasting combat injuries and medbay treatment (Milestone 3)

Almost everything is module-contained: the injury status effects (`StatusEffects/`), the hourly healing (the existing `pcHoursPassed` game-extender hook,
registered by `SandboxGameExtender`) and the penalties (BDCC's own buff and damage-modifier calculations). Base-game edits:

- **`Scenes/FightScene.gd` `sandboxFightEnded()`:** calls `onFightInjuries(enemyID, enemyPainFraction, playerPainFraction, battleName)` once per scene,
  before `onFightEnd` can change pain. If `SandboxOverhaulModule` is absent nothing happens.
- **`Modules/MedicalModule/ElizaTalkScene.gd`:** a "Treat injuries" button in the main menu (only when the module exists), the `injuryMenu`, `injuryConfirm` and
  `injuryResult` states, and the `injuryAsk` and `injuryPay` actions in `_react`, with two scene variables (`sandboxInjuryPick`, `sandboxInjuryResult`).
  The existing "I'm hurt" cryopod and healing-gel options are untouched. Without the module the button does not appear.
- **`Game/BaseCharacter.gd` `getMaxStamina()` and `getDodgeChance()`:** the Leg Injury is a percentage, which BDCC's flat-point stamina buff and additive dodge
  modifier cannot express, so each function multiplies its final result once by `getLegInjuryScale(getID())` (0.9, 0.8 or 0.7; 1.0 when healthy).
  `getMaxStamina` scales the character's own injury-free maximum (base + skills + buffs); `getDodgeChance` scales the final positive chance (the
  deliberate `isDodging()` result of 1 is untouched). The scale is read straight from the stored injury, so there is no recursion. Both checks are skipped
  when `SandboxOverhaulModule` is absent or its extender is not yet registered.

### 7. Cells, cellmates and the nightly routine (Milestone 4)

Everything else is module-contained: the cell data, the schedule (the existing `pcProcessTime` game-extender hook, run at most once per ten in-game minutes),
the cell directory scene, and the directory buttons, which a world edit (`WorldEdits/CellsWorldEdit.gd`) adds to the existing cell block rooms as `RoomAction`
nodes, so the map scene is not edited. Base-game edits, all no-ops without `SandboxOverhaulModule`:

- **`Game/InteractionSystem/InteractionSystem.gd` `trySpawnPawn()`:** after a random existing inmate is picked, `canSpawnPawn(id)` can veto the spawn while that
  inmate is still asleep in their cell (before their wake time). A module-only solution was not enough: nothing else sits between "pick an existing character"
  and `spawnPawn`, and filtering earlier (`characterIDCanBePicked`) would make BDCC generate brand-new inmates instead whenever everyone is asleep.
  Without the hook the morning wave would spawn inmates who the schedule then sends straight back.
- **`Game/InteractionSystem/Interactions/Talking.gd`:** a "Which cell?" action in `init_text` (player talking to an NPC, score 0 so NPCs never pick it), the `ask_cell` branch
  in `init_do` (stores the knowledge through the module, nothing else) and the `asked_cell` state.
- **`Scenes/MeScene.gd`:** a "Cells" button in the main menu and a `cellsMenu` state that prints the module's text (your cell, cellmate, learned cells).

### 8. Jobs, wages and cell upgrades (Milestone 5)

Everything else is module-contained: the employment and upgrade services, the work clock (the existing `pcProcessTime` game-extender hook), three module scenes
(job board, shift, cell upgrades), and the buttons, which a world edit (`WorldEdits/WorkWorldEdit.gd`) adds to the existing rooms (the canteen, the three workplaces and
the player's cell) as `RoomAction` nodes, so no map scene is edited. Base-game edits, all no-ops without `SandboxOverhaulModule`:

- **`Scenes/Mineshaft/WorkInMinesScene.gd`:** the vanilla 1 credit per "Work" click was unlimited wage farming (only stamina limited it). With the module, the credit is paid
  once per day (`getInformalMiningPay()`); later sessions still mine, take the same stamina and time and still fire `Trigger.WorkingInMines`, they just pay nothing, and a message
  says so. Without the module the credit is paid every time as before. `FirstTimeInMinesScene` (the story intro and its flag) is untouched. A module-only solution is not possible:
  the credit is granted inside the scene.
- **`Scenes/MeScene.gd`:** a "Work" button in the main menu and a `workMenu` state that prints the module's job status text (the same place as the "Cells" button).
- **`Scenes/RestingInCellScene.gd`:** after `afterRestingInBed()` in the `restuntil` branch, `afterRestInOwnCell(timePassed)` adds the better-bedding stamina bonus. This scene is only
  reachable from the player's own cell, and the module checks the location again.
- **`Scenes/PlayerStashScene.gd`:** with the module the free pillow stash has a capacity (4 stacks, 12 with the personal locker). A small `getStashRefusal(item)` helper asks the module
  and is checked before each of the three deposit paths (`stashx`, `hideallitems` and the inventory-screen click); the stash screen also prints the module's capacity line. It returns ""
  without the module, so vanilla stays unlimited. A module-only solution is not possible: the scene moves items straight into the `playerstash` inventory. Withdrawals are never restricted.

### 9. Guards, searches and enforcement (Milestone 6)

Almost everything is module-contained, with no map or story-scene edits:

- **The guard confrontation is a module interaction** (`Interactions/GuardEnforcement.gd`). Modules cannot list interactions, so `SandboxOverhaulModule.postInit()` registers it with the existing
  `GlobalRegistry.registerInteraction`. BDCC's own `shouldRunOnMeet` is the "a guard and the player meet" hook; the module's ten-minute check (the existing `pcProcessTime` game-extender hook)
  covers a guard standing next to a player who stays put.
- **Witnessed violence** uses the existing Milestone 2 hook `onUnprovokedAttack` (the player starting a fight in `Talking`); **witnessed forced sex** uses the existing Milestone 1 hook
  `applySexAftermathAndShouldRunVanilla`, only for the `FORCED` classification and only when the player is the one who forced it.
- **Fights and punishment are not duplicated:** the confrontation starts the normal fight through `start_fight` (so `FightScene`, Milestone 2's `doFightAftermath` and Milestone 3's injuries run once,
  exactly as in `CaughtOffLimits`) and hands over to the existing `PunishInteraction`.
- **Contraband is BDCC's own** `ItemTag.Illegal` classification.

One base-game edit, a no-op without `SandboxOverhaulModule`:

- **`Scenes/MeScene.gd`:** a "Security" button in the main menu and a `securityMenu` state that prints the module's text (attention, label, recent search, active warning), next to the "Work" and
  "Cells" buttons. A module-only solution is not possible: the Me screen has no extension point.

Deliberately **not** changed: `CaughtOffLimits` (the off-limits frisk, 5-credit fine and removal of worn illegal items stays as it was), `MainCheckpointScene` (the elevator checkpoint frisk), and every story scene.
