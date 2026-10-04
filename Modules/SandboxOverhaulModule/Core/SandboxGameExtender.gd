extends GameExtender
class_name SandboxGameExtender

const EXTENDER_ID = "SandboxGameExtender"
const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd") # no reliance on the editor-written class cache

var state = StateScript.new()
const ConversationScript = preload("res://Modules/SandboxOverhaulModule/Relationships/ConversationRelationships.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const UpgradesScript = preload("res://Modules/SandboxOverhaulModule/Cells/CellUpgrades.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")
const RelationshipsScript = preload("res://Modules/SandboxOverhaulModule/Relationships/DirectedRelationships.gd")

var relationships
var combat
var injuries
var cells
var employment
var upgrades
var scheduleBucket:int = -1 # last ten-minute bucket the nightly schedule ran in (not saved, so it runs again after a load)
var ownerMainId: int = 0 # instance id of the MainScene the state belongs to (ids are never reused, pointers can be)

func _init():
	id = EXTENDER_ID
	relationships = RelationshipsScript.new(state)
	combat = CombatScript.new(state, relationships)
	injuries = InjuriesScript.new(state)
	cells = CellsScript.new(state)
	employment = EmploymentScript.new(state)
	upgrades = UpgradesScript.new(state)

func register(_GES: GameExtenderSystem):
	_GES.register(self, ExtendGame.saveLoadData)
	_GES.register(self, ExtendGame.pcHoursPassed)
	_GES.register(self, ExtendGame.pcProcessTime)

# Runs the nightly schedule at most once per ten in-game minutes (the module decides; this is only the trigger), and the work clock.
func pcProcessTime(_pc, _seconds):
	var theModule = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(theModule != null):
		theModule.onScheduleTick()
		theModule.onWorkTick()

# Injuries heal with the player's hour counter, which runs on every time skip, so every character's injuries are processed here
# (the NPC hour hook only reaches characters that are currently being simulated).
func pcHoursPassed(_pc, _hours):
	var theModule = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(theModule != null):
		theModule.processInjuryHours(_hours)

# GameExtenderSystem.loadData skips extenders missing from the save, and this
# object outlives MainScene, so reset whenever a different game is running.
func getState():
	var mainId = GM.main.get_instance_id() if (GM.main != null && is_instance_valid(GM.main)) else 0
	if(ownerMainId != mainId):
		ownerMainId = mainId
		state.clear()
	return state

# Same service instance for the whole run. It reads the state's current dictionaries, so it survives clear/load.
func getRelationships():
	var _state = getState() # applies the new-game reset
	return relationships

# Combat reputation service, same lifetime rules as getRelationships.
func getCombat():
	var _state = getState()
	return combat

# Injury service, same lifetime rules as getRelationships.
func getInjuries():
	var _state = getState()
	return injuries

# Cell service, same lifetime rules as getRelationships.
func getCells():
	var _state = getState()
	return cells

# Employment service, same lifetime rules as getRelationships.
func getEmployment():
	var _state = getState()
	return employment

# Cell upgrade and storage service, same lifetime rules as getRelationships.
func getUpgrades():
	var _state = getState()
	return upgrades

# Drops characters that definitely no longer exist. Does nothing without a live MainScene.
func pruneMissingCharacters():
	if(GM.main == null || !is_instance_valid(GM.main)):
		return
	for characterID in relationships.getCharacterIDs():
		if(characterID != "pc" && GM.main.getCharacter(characterID) == null):
			relationships.removeCharacter(characterID)
	for characterID in ConversationScript.getCooldownCharacterIDs(state.cooldowns):
		if(characterID != "pc" && GM.main.getCharacter(characterID) == null):
			ConversationScript.removeCooldownsOf(state.cooldowns, characterID)
	for characterID in cells.getCharacterIDs():
		if(characterID != "pc" && GM.main.getCharacter(characterID) == null):
			cells.removeCharacter(characterID)
	for characterID in injuries.getCharacterIDs():
		if(characterID != "pc" && GM.main.getCharacter(characterID) == null):
			injuries.removeCharacter(characterID)
	for characterID in CombatScript.getCooldownCharacterIDs(state.cooldowns):
		if(characterID != "pc" && GM.main.getCharacter(characterID) == null):
			CombatScript.removeCooldownsOf(state.cooldowns, characterID)

func saveData():
	var theState = getState()
	pruneMissingCharacters()
	return theState.saveData()

func loadData(_data):
	getState().loadData(_data)
