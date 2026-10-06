extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxTalkHoldingUp"
	actionType = Talk
	slaveResistChanceMult = 0.0
	buttonPriority = 95

func getVisibleName():
	return "How are you holding up?"

func getVisibleDesc():
	return "Ask how they are really doing. Their answer depends on how they feel about you, their role and their health."

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	var rec:Dictionary = slaveRecord(_slaveID)
	var tired:bool = getSlave(_slaveID).getWorkEfficiency() < 0.3
	return {
		text = "You ask {npc.name} how {npc.he} is holding up.\n\n" + say(TextScript.holdingUp(disposition(_slaveID), str(rec.get("role", "free")), OwnershipGameScript.slaveIsHurt(_slaveID), tired)),
	}
