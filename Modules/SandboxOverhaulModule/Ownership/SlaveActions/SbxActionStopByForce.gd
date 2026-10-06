extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxActionStopByForce"
	actionType = Action
	slaveResistChanceMult = 0.0
	endsTalkScene = true
	buttonPriority = 180

func getVisibleName():
	return "Stop them by force"

func getVisibleDesc():
	return "They are planning to run. Fight them. If you win they will not try again for a while, and fear you more."

func isActionVisible(_slaveID):
	return .isActionVisible(_slaveID) && escaping(_slaveID)

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	GM.main.IS.startInteraction("GenericAttack", {"starter": "pc", "reacter": _slaveID})
	return {
		text = "You grab {npc.name} and square up. {npc.He} fights back.",
	}
