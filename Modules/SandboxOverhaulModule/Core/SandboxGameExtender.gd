extends GameExtender
class_name SandboxGameExtender

const EXTENDER_ID = "SandboxGameExtender"
const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd") # no reliance on the editor-written class cache

var state = StateScript.new()
const ConversationScript = preload("res://Modules/SandboxOverhaulModule/Relationships/ConversationRelationships.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")
const RelationshipsScript = preload("res://Modules/SandboxOverhaulModule/Relationships/DirectedRelationships.gd")

var relationships
var combat
var ownerMainId: int = 0 # instance id of the MainScene the state belongs to (ids are never reused, pointers can be)

func _init():
	id = EXTENDER_ID
	relationships = RelationshipsScript.new(state)
	combat = CombatScript.new(state, relationships)

func register(_GES: GameExtenderSystem):
	_GES.register(self, ExtendGame.saveLoadData)

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
	for characterID in CombatScript.getCooldownCharacterIDs(state.cooldowns):
		if(characterID != "pc" && GM.main.getCharacter(characterID) == null):
			CombatScript.removeCooldownsOf(state.cooldowns, characterID)

func saveData():
	var theState = getState()
	pruneMissingCharacters()
	return theState.saveData()

func loadData(_data):
	getState().loadData(_data)
