extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxRewardTreat"
	actionType = Reward
	slaveResistChanceMult = 0.0
	buttonPriority = 84
	rewardHint = 2

func getVisibleName():
	return "Treat their injuries"

func getVisibleDesc():
	return "Pay " + str(OwnershipGameScript.TREAT_COST) + " credits to have their injuries seen to. Good for their trust."

func checkCanDo(_slaveID, _extraSlavesIDs = {}):
	if(!OwnershipGameScript.slaveIsHurt(_slaveID)):
		return [false, "They are not hurt."]
	if(GM.pc.getCredits() < OwnershipGameScript.TREAT_COST):
		return [false, "You need " + str(OwnershipGameScript.TREAT_COST) + " credits."]
	return [true]

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	GM.pc.addCredits(-OwnershipGameScript.TREAT_COST)
	var injuries = OwnershipGameScript.module().getInjuries()
	var all:Dictionary = injuries.getAll(_slaveID)
	if(!all.empty()):
		injuries.remove(_slaveID, all.keys()[0])
	var _t:float = rel().adjustFeeling(_slaveID, "pc", "trust", 3.0)
	var _a:float = rel().adjustFeeling(_slaveID, "pc", "affection", 1.0)
	svc().markTreated(_slaveID, OwnershipGameScript.today())
	return {
		text = "You get {npc.name}'s injuries seen to.\n\n" + say("That feels better. Thank you for not just leaving me like this."),
	}
