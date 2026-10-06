extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxActionCollect"
	actionType = Action
	slaveResistChanceMult = 0.0
	buttonPriority = 65

func getVisibleName():
	return "Collect earnings"

func getVisibleDesc():
	return "Take what they have brought in"

func isActionVisible(_slaveID):
	return .isActionVisible(_slaveID) && int(slaveRecord(_slaveID).get("uncollected", 0)) > 0

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	var amount:int = svc().collectEarnings(_slaveID)
	if(amount <= 0):
		return {text = "There is nothing to collect."}
	GM.pc.addCredits(amount)
	return {
		text = "{npc.name} hands over " + str(amount) + " credits.\n\n[color=green]+" + str(amount) + " credits[/color]",
	}
