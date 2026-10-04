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
  - `endbattle` action calls the new `sandboxFightEnded()`: it measures how hurt the winner is into `battleMargin` (larger of pain and lust as a fraction of the threshold) and, once per scene (`sandboxReported`), calls `onFightSceneEnded`, which acts only on Fight Club `"arenafight"` fights. This is the real Fight Club hook: every arena scene (`AvyTalkScene`, `AvyFirstArenaBattleScene`, `AvyFinalArenaBattleScene`) runs `FightScene` with the battle name `"arenafight"` and ends through `endbattle`.
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
