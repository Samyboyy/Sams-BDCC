extends PawnInteractionBase

# Somebody the player is bound to asks for help in a fight that is going on in front of them (see HelpRequests for who asks and what each answer costs). Registered by
# SandboxOverhaulModule.postInit. It involves only the player, so the fight itself is not interrupted while the player decides; the fight is looked up again when the player answers.
# The request counts as delivered only once its text has been shown, and only a delivered request has consequences.

var asker:String = ""
var foe:String = ""
var bond:String = ""
var delivered:bool = false
var resultText:String = ""

func _init():
	id = "SandboxHelpRequest"

func start(_pawns:Dictionary, _args:Dictionary):
	doInvolvePawn("main", _pawns["main"])
	asker = str(_args.get("asker", ""))
	foe = str(_args.get("foe", ""))
	bond = str(_args.get("bond", ""))
	setState("", "main")

func getSandbox():
	return GlobalRegistry.getModule("SandboxOverhaulModule")

func init_text():
	var sandbox = getSandbox()
	if(sandbox == null || HelpRequestsScript.findFight(asker, foe) == null):
		saynn("A fight you were about to be asked to join is over before anyone gets a word out.")
		addAction("leave", "Continue", "Carry on", "default", 1.0, 30, {})
		return
	delivered = true
	saynn(HelpRequestsScript.requestText(sandbox, asker, foe, bond))
	addAction("help", "Help them", "Take " + sandbox.characterName(asker) + "'s side and fight " + sandbox.characterName(foe), "default", 1.0, 30, {})
	addAction("breakup", "Try to break it up", "Step between them. It costs stamina and may not work", "default", 1.0, 30, {})
	addAction("refuse", "Refuse", "Stay out of it, and leave", "default", 1.0, 30, {})

func init_do(_id:String, _args:Dictionary, _context:Dictionary):
	var sandbox = getSandbox()
	if(sandbox != null && _id != "leave"):
		var text:String = HelpRequestsScript.resolve(sandbox, asker, foe, bond, _id, delivered)
		if(text != ""):
			addMessage(text)
	stopMe()

func getAnimData() -> Array:
	return []

func getPreviewLineForRole(_role:String) -> String:
	return "{main.name} is being asked for help in a fight."

func getActivityIconForRole(_role:String):
	return RoomStuff.PawnActivity.Help

func saveData():
	var data = .saveData()
	data["asker"] = asker
	data["foe"] = foe
	data["bond"] = bond
	data["delivered"] = delivered
	return data

func loadData(_data):
	.loadData(_data)
	asker = SAVE.loadVar(_data, "asker", "")
	foe = SAVE.loadVar(_data, "foe", "")
	bond = SAVE.loadVar(_data, "bond", "")
	delivered = SAVE.loadVar(_data, "delivered", false)

const HelpRequestsScript = preload("res://Modules/SandboxOverhaulModule/Interactions/HelpRequests.gd")
