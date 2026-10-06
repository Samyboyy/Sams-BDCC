extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxActionReport"
	actionType = Action
	slaveResistChanceMult = 0.0
	buttonPriority = 60

func getVisibleName():
	return "Ask them to report to your cell"

func getVisibleDesc():
	return "They are to come to your cell this evening (19:30 to 21:30), then go back to their own day. A slave who does not come is noticed."

func checkCanDo(_slaveID, _extraSlavesIDs = {}):
	var rec:Dictionary = slaveRecord(_slaveID)
	if(!rec.get("report", {}).empty() && int(rec["report"].get("day", -1)) == OwnershipGameScript.today() && rec["report"].get("state", "") == "pending"):
		return [false, "You already asked them today."]
	var problem:String = OwnershipGameScript.reportProblem(_slaveID)
	if(problem != ""):
		return [false, problem]
	return [true]

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	var d:String = disposition(_slaveID)
	if(!OwnershipScript.willDo("report", d)):
		svc().askReport(_slaveID, OwnershipGameScript.today())
		svc().data()["slaves"][_slaveID]["report"]["refused"] = true
		return {
			text = "You tell {npc.name} to come to your cell this evening.\n\n" + say(TextScript.refuseDuty("report", d)) + "\n\n[color=#c8c8d8]They will not come. You will notice.[/color]",
		}
	var _ok:bool = svc().askReport(_slaveID, OwnershipGameScript.today())
	return {
		text = "You tell {npc.name} to come to your cell this evening.\n\n" + say("I will be there.") + "\n\n[color=#c8c8d8]They will walk to your cell this evening, then go back to their own day.[/color]",
	}
