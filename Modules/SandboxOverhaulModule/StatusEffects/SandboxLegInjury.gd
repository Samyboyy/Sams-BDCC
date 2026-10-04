extends "res://Modules/SandboxOverhaulModule/StatusEffects/SandboxInjuryEffect.gd"

func _init():
	id = "SandboxLegInjury"
	injuryType = "leg"

func getEffectImage():
	return "res://Images/StatusEffects/dodging.png"
