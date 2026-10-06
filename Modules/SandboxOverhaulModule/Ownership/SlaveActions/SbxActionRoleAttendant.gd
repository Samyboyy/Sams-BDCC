extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

const ROLE = "attendant"

func _init():
	id = "SbxActionRoleAttendant"
	actionType = Action
	slaveResistChanceMult = 0.0
	buttonPriority = 70

func getVisibleName():
	return "Role: Attendant"

func getVisibleDesc():
	return "They spend some of the day near your cell block and may help if you are attacked while they are there."

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
