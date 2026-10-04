extends Module
class_name SandboxOverhaulModule

const ExtenderScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd")

func _init():
	id = "SandboxOverhaulModule"
	author = "Sam"
	
	gameExtenders = [
		"res://Modules/SandboxOverhaulModule/Core/SandboxGameExtender.gd",
	]

# Active state. Resets itself when a different game (MainScene) is running.
static func getState():
	var extender = GlobalRegistry.getGameExtender(ExtenderScript.EXTENDER_ID)
	return extender.getState()
