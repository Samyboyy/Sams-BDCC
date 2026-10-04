extends GameExtender
class_name SandboxGameExtender

const EXTENDER_ID = "SandboxGameExtender"
const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd") # no reliance on the editor-written class cache

var state = StateScript.new()
var ownerMainId: int = 0 # instance id of the MainScene the state belongs to (ids are never reused, pointers can be)

func _init():
	id = EXTENDER_ID

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

func saveData():
	return getState().saveData()

func loadData(_data):
	getState().loadData(_data)
