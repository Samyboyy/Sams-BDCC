extends SceneBase

# "Start shift" at the player's workplace (the workshop, the laundry, and the mines through the mines handler event's button). The wage is paid once, when the shift starts,
# then the shift time passes. Roughly one shift in four ends with something happening at work (see WorkEvents): a choice, with consequences.

const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

var resultText:String = ""
var eventText:String = ""
var fightEnemy:String = ""
var fightEvent:Dictionary = {}

func _init():
	sceneID = "WorkShiftScene"

func _run():
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	var employment = module.getEmployment()
	var jobID:String = EmploymentScript.jobAtRoom(GM.pc.getLocation())
	if(state == ""):
		if(jobID == ""):
			saynn("This is not a workplace.")
		else:
			var job:Dictionary = EmploymentScript.JOBS[jobID]
			saynn("[b]" + job["name"] + "[/b] - " + job["workplace"] + "\n" + job["text"])
			var check:Dictionary = module.explainShift(jobID)
			saynn(module.getCrewText(jobID))
			if(employment.isEmployedAt(GM.pc.getLocation())):
				saynn(module.getWorkScreenText())
			if(check["ok"]):
				addButton("Start shift", "Work about " + str(job["hours"]) + " hours for " + str(job["wage"]) + " credits. It costs " + str(job["stamina"]) + " stamina.", "start")
			else:
				saynn(check["reason"])
				addDisabledButton("Start shift", check["reason"])
		addButton("Back", "Not now", "endthescene")
	if(state == "done"):
		saynn(resultText)
		addButton("Continue", "Shift over", "endthescene")
	if(state == "event"):
		var event:Dictionary = module.getPendingWorkEvent()
		if(event.empty()):
			setState("done")
			return
		var view:Dictionary = module.getWorkEventView(event)
		saynn(resultText)
		saynn("[b]Something happens at work.[/b]")
		saynn(view["text"])
		for choice in view["choices"]:
			addButton(choice["label"], choice["tooltip"], "choose", [choice["id"]])
	if(state == "eventresult"):
		saynn(eventText)
		if(fightEnemy != ""):
			addButton("Fight", "It comes to blows", "fight")
		else:
			addButton("Continue", "Shift over", "endthescene")
	if(state == "afterfight"):
		saynn("The fight is over. The rest of the floor goes back to work, a little more quietly than before.")
		addButton("Continue", "Shift over", "endthescene")

func _react(_action: String, _args):
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(_action == "start"):
		var jobID:String = EmploymentScript.jobAtRoom(GM.pc.getLocation())
		var result:Dictionary = module.startShift(jobID)
		if(!result["ok"]):
			addMessage(result["reason"])
			setState("")
			return
		var job:Dictionary = EmploymentScript.JOBS[jobID]
		resultText = job["text"] + " The shift is over after " + str(job["hours"]) + " hours. You earned [b]" + str(result["wage"]) + " credits[/b] and now have " + str(result["balance"]) + "."
		addMessage("Shift pay: " + str(result["wage"]) + " credits. You now have " + str(result["balance"]) + ".")
		processTime(int(job["hours"]) * 60 * 60)
		# Mining is the existing mining: story modules that react to working in the mines still see a shift.
		if(jobID == "mining" && GM.ES.triggerReact(Trigger.WorkingInMines)):
			endScene()
			return
		var event:Dictionary = module.rollWorkEvent(jobID)
		setState("event" if !event.empty() else "done")
		return
	if(_action == "choose"):
		var outcome:Dictionary = module.resolveWorkEvent(str(_args[0]))
		if(!outcome["ok"]):
			setState("done")
			return
		eventText = outcome["text"]
		fightEnemy = str(outcome["fight"])
		fightEvent = outcome["event"].duplicate(true) if outcome.has("event") else {}
		setState("eventresult")
		return
	if(_action == "fight"):
		var enemy:String = fightEnemy
		fightEnemy = ""
		var theChar = GM.main.getCharacter(enemy)
		if(theChar != null && theChar.getCharacterType() == CharacterType.Guard):
			module.onUnprovokedAttack(enemy) # hitting a guard is an offence whoever started it
		runScene("FightScene", [enemy], "workfight")
		return
	if(_action == "endthescene"):
		endScene()
		return
	setState(_action)

func _react_scene_end(_tag, _result):
	if(_tag == "workfight"):
		var module = GlobalRegistry.getModule("SandboxOverhaulModule")
		var enemyID:String = str(fightEvent.get("who", ""))
		if(str(fightEvent.get("family", "")) == "supervisor"):
			enemyID = str(fightEvent.get("boss", ""))
		module.onWorkFightEnded(fightEvent, enemyID, _result if _result is Array else [])
		fightEvent = {}
		setState("afterfight")

func saveData():
	var data = .saveData()
	data["resultText"] = resultText
	data["eventText"] = eventText
	data["fightEnemy"] = fightEnemy
	data["fightEvent"] = fightEvent
	return data

func loadData(_data):
	.loadData(_data)
	resultText = SAVE.loadVar(_data, "resultText", "")
	eventText = SAVE.loadVar(_data, "eventText", "")
	fightEnemy = SAVE.loadVar(_data, "fightEnemy", "")
	fightEvent = SAVE.loadVar(_data, "fightEvent", {})
