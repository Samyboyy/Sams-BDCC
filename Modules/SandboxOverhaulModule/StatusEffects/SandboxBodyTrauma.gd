extends "res://Modules/SandboxOverhaulModule/StatusEffects/SandboxInjuryEffect.gd"

func _init():
	id = "SandboxBodyTrauma"
	injuryType = "trauma"

func getEffectImage():
	return "res://Images/StatusEffects/armor-punch.png"
