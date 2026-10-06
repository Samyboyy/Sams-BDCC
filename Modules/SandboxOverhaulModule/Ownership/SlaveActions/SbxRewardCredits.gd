extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxRewardCredits"
	actionType = Reward
	slaveResistChanceMult = 0.0
	buttonPriority = 85
	rewardHint = 2

func getVisibleName():
	return "Give credits"

func getVisibleDesc():
	return "Press " + str(OwnershipGameScript.REWARD_COST) + " credits into their hand for good work. Once a day."

func checkCanDo(_slaveID, _extraSlavesIDs = {}):
	if(GM.pc.getCredits() < OwnershipGameScript.REWARD_COST):
		return [false, "You need " + str(OwnershipGameScript.REWARD_COST) + " credits."]
	if(int(slaveRecord(_slaveID).get("last_treat", -1)) == OwnershipGameScript.today()):
		return [false, "You already looked after them today."]
	return [true]

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	GM.pc.addCredits(-OwnershipGameScript.REWARD_COST)
	var _t:float = rel().adjustFeeling(_slaveID, "pc", "trust", 4.0)
	var _a:float = rel().adjustFeeling(_slaveID, "pc", "affection", 2.0)
	var _f:float = rel().adjustFeeling(_slaveID, "pc", "fear", -5.0)
	svc().markTreated(_slaveID, OwnershipGameScript.today())
	getSlave(_slaveID).handleReward(2)
	return {
		text = "You give {npc.name} " + str(OwnershipGameScript.REWARD_COST) + " credits for {npc.his} trouble.\n\n" + say(RNG.pick(["For me? ...Thank you.", "I did not expect that. Thanks.", "Oh. Well. Thank you."])),
	}
