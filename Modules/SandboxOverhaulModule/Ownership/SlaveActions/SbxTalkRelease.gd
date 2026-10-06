extends "res://Modules/SandboxOverhaulModule/Ownership/SlaveActions/SbxBase.gd"

func _init():
	id = "SbxTalkRelease"
	actionType = Talk
	slaveResistChanceMult = 0.0
	buttonPriority = 20

func getVisibleName():
	return "Discuss release"

func getVisibleDesc():
	return "Talk about letting them go. Releasing someone is something they remember kindly."

func doActionSimple(_slaveID, _extraSlavesIDs = {}):
	var line:String = "..."
	match(disposition(_slaveID)):
		"loyal":
			line = "You would let me go? ...I would not mind staying, to be honest. But thank you for asking."
		"intimidated":
			line = "Is this a test? Please do not do anything to me for answering. Yes. I would like to leave."
		"resentful":
			line = "Yes. Let me go. It is the least you could do."
		"defiant":
			line = "Let me go, or I will find my own way out."
		"recovering":
			line = "I would like to get well first. After that... yes, I would like to go."
		_:
			line = "I do not know. Yes, I think. But it is kind of you to ask."
	return {
		text = "You ask {npc.name} what {npc.he} would do if you let {npc.him} go.\n\n" + say(line),
	}

func getExtraActions(_slaveID, _extraSlavesIDs = {}):
	return [
		{
			name = "Release slave",
			desc = "Free your slave and let them leave your cell. They will remember it kindly.",
			sceneID = "ActionSlaveryFreeSlaveScene",
			args = [],
			buttonChecks = [],
		}
	]
