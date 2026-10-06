extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxTalkRoundEscape"
	actionType = Talk
	slaveResistChanceMult = 0.0
	buttonPriority = 200

func getVisibleName():
	return "Talk them out of leaving"

func getVisibleDesc():
	return "They are planning to run. Try to talk them round. It works if they still trust and like you a little."

func isActionVisible(_slaveID):
	return .isActionVisible(_slaveID) && escaping(_slaveID)

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	var f:Dictionary = OwnershipGameScript.slaveFeelings(_slaveID)
	var score:float = f["trust"] * 0.4 + f["affection"] * 0.3 + f["respect"] * 0.2
	if(score >= -5.0):
		svc().stopEscape(_slaveID, OwnershipGameScript.today())
		svc().markTreated(_slaveID, OwnershipGameScript.today())
		var _t:float = rel().adjustFeeling(_slaveID, "pc", "trust", 3.0)
		return {
			text = "You sit {npc.name} down and talk.\n\n" + say("...All right. I will stay. For now. Do not make me regret it.") + "\n\n[color=#c8c8d8]They give up the idea of running, for now.[/color]",
		}
	return {
		text = "You try to talk {npc.name} round.\n\n" + say("Save it. Talking will not change anything.") + "\n\n[color=#c8c8d8]It did not work. They are still planning to run. Better treatment, a firm warning, or force might.[/color]",
	}
