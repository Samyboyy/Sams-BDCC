extends SceneBase

# "Start shift" at the player's workplace. The wage is paid once, when the shift starts, then the shift time passes.

const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

var resultText:String = ""

func _init():
	sceneID = "WorkShiftScene"

func _run():
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	var employment = module.getEmployment()
	var jobID:String = EmploymentScript.jobAtRoom(GM.pc.getLocation())
	if(state == ""):
		if(jobID == "" || !employment.isEmployedAt(GM.pc.getLocation())):
			saynn("This is not your workplace.")
		else:
			var job:Dictionary = EmploymentScript.JOBS[jobID]
			saynn("[b]" + job["name"] + "[/b] - " + job["workplace"] + "\n" + job["text"])
			saynn(module.getWorkScreenText())
			var check:Dictionary = employment.canStartShift(jobID, GM.main.getDays(), GM.main.getTime())
			if(check["ok"]):
				addButton("Start shift", "Work about " + str(job["hours"]) + " hours for " + str(job["wage"]) + " credits. It costs " + str(job["stamina"]) + " stamina.", "start")
			else:
				addDisabledButton("Start shift", check["reason"])
		addButton("Back", "Not now", "endthescene")
	if(state == "done"):
		saynn(resultText)
		addButton("Continue", "Shift over", "endthescene")

func _react(_action: String, _args):
	if(_action == "start"):
		var module = GlobalRegistry.getModule("SandboxOverhaulModule")
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
		setState("done")
		return
	if(_action == "endthescene"):
		endScene()
		return
	setState(_action)

func saveData():
	var data = .saveData()
	data["resultText"] = resultText
	return data

func loadData(_data):
	.loadData(_data)
	resultText = SAVE.loadVar(_data, "resultText", "")
