extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

const ROLE = "earner"

func _init():
	id = "SbxActionRoleEarner"
	actionType = Action
	slaveResistChanceMult = 0.0
	buttonPriority = 70

func getVisibleName():
	return "Role: Earner"

func getVisibleDesc():
	return "They spend part of the afternoon earning 2 to 4 credits a day. It costs their trust."

func checkCanDo(_slaveID, _extraSlavesIDs = {}):
	var rec:Dictionary = slaveRecord(_slaveID)
	if(str(rec.get("role", "free")) == ROLE):
		return [false, "They already have this role."]
	if(!svc().canChangeRole(_slaveID, OwnershipGameScript.today())):
		return [false, "Their role was already changed today."]
	return [true]

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	var d:String = disposition(_slaveID)
	if(!OwnershipScript.willDo(ROLE, d)):
		return {
			text = "You tell {npc.name} what you want from {npc.him}.\n\n" + say(TextScript.refuseDuty(ROLE, d)) + "\n\n[color=#c8c8d8]They refuse. Treat them better, or look after their trust, and ask again.[/color]",
		}
	var _ok:bool = svc().setRole(_slaveID, ROLE, OwnershipGameScript.today(), OwnershipGameScript.clockNow())
	return {
		text = "You give {npc.name} a new role: " + str(OwnershipScript.ROLE_NAMES[ROLE]) + ".\n\n[color=#c8c8d8]" + str(OwnershipScript.ROLE_TEXT[ROLE]) + " It starts in about half an hour.[/color]",
	}
