extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxTalkRole"
	actionType = Talk
	slaveResistChanceMult = 0.0
	buttonPriority = 90

func getVisibleName():
	return "Ask about their role"

func getVisibleDesc():
	return "Find out what they do with their days and whether they are happy to"

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	var rec:Dictionary = slaveRecord(_slaveID)
	var role:String = str(rec.get("role", "free"))
	var willing:bool = OwnershipScript.willDo(role, disposition(_slaveID))
	var text:String = "You ask {npc.name} about {npc.his} role.\n\n" + say(TextScript.roleLine(role, willing)) + "\n\n[color=#c8c8d8]" + str(OwnershipScript.ROLE_NAMES[role]) + ": " + str(OwnershipScript.ROLE_TEXT[role]) + "[/color]"
	if(int(rec.get("uncollected", 0)) > 0):
		text += "\n\n[color=#c8c8d8]" + str(rec["uncollected"]) + " credits are waiting for you to collect.[/color]"
	text += "\n\n[color=#c8c8d8]" + str(OwnershipScript.DISPOSITION_TEXT[disposition(_slaveID)]) + "[/color]"
	return {
		text = text,
	}
