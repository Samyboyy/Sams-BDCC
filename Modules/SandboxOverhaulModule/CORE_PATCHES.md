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
  changed from `(140, 50)` to `(200, 72)` so three lines fit. The Friend, Nemesis and Owner label is untouched.
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
