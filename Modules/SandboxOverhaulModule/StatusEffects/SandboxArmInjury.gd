extends "res://Modules/SandboxOverhaulModule/StatusEffects/SandboxInjuryEffect.gd"

func _init():
	id = "SandboxArmInjury"
	injuryType = "arm"

func getEffectImage():
	return "res://Images/StatusEffects/biceps.png"
