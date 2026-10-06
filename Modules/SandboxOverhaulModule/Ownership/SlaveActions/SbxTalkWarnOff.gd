extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxTalkWarnOff"
	actionType = Talk
	slaveResistChanceMult = 0.0
	buttonPriority = 190

func getVisibleName():
	return "Warn them off"

func getVisibleDesc():
	return "Scare them out of running. It raises their fear and costs trust. Someone who does not fear you at all will laugh at it."

func isActionVisible(_slaveID):
	return .isActionVisible(_slaveID) && escaping(_slaveID)

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	var f:Dictionary = OwnershipGameScript.slaveFeelings(_slaveID)
	if(disposition(_slaveID) == "defiant" && f["fear"] < 10.0):
		return {
			text = "You warn {npc.name} what will happen if {npc.he} runs.\n\n" + say("Is that supposed to scare me?") + "\n\n[color=#c8c8d8]They do not take it seriously. They are still planning to run.[/color]",
		}
	svc().stopEscape(_slaveID, OwnershipGameScript.today())
	var _fear:float = rel().adjustFeeling(_slaveID, "pc", "fear", 15.0)
	var _trust:float = rel().adjustFeeling(_slaveID, "pc", "trust", -5.0)
	var _aff:float = rel().adjustFeeling(_slaveID, "pc", "affection", -3.0)
	return {
		text = "You make it clear what happens to a slave who runs.\n\n" + say("...I understand. I will not.") + "\n\n[color=#c8c8d8]They stay, out of fear and not loyalty.[/color]",
	}
