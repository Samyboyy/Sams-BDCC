extends SceneBase

# The canteen job board: see the open jobs, take one or leave yours, each with a confirmation.

const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")

var pendingJob:String = ""
var resultText:String = ""

func _init():
	sceneID = "JobBoardScene"

func _run():
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	var employment = module.getEmployment()
	var day:int = GM.main.getDays()
	module.onJobBoardSeen()
	if(state == ""):
		saynn("[b]Job board[/b]\nA scratched notice board by the canteen counter lists the jobs open to inmates. Pay is in work credits, one paid shift a day, and you can only hold one job.")
		saynn(module.getWorkScreenText())
		for jobID in EmploymentScript.JOB_ORDER:
			var job:Dictionary = EmploymentScript.JOBS[jobID]
			sayn(job["name"] + ": " + job["workplace"] + ", shifts start " + EmploymentScript.windowText(jobID) + ", about " + str(job["hours"]) + " hours, pay " + str(job["wage"]) + " credits.")
		sayn("")
		for jobID in EmploymentScript.JOB_ORDER:
			var check:Dictionary = employment.canApply(jobID, day)
			if(check["ok"]):
				addButton("Take: " + EmploymentScript.jobName(jobID), "Apply for this job", "confirmaccept", [jobID])
			else:
				addDisabledButton("Take: " + EmploymentScript.jobName(jobID), check["reason"])
		if(employment.isEmployed()):
			addButton("Leave job", "Quit your job. Your record stays.", "confirmleave")
		addButton("Back", "Walk away from the board", "endthescene")
	if(state == "confirmaccept"):
		var job:Dictionary = EmploymentScript.JOBS[pendingJob]
		saynn("Take the job of [b]" + job["name"] + "[/b]? You report to the " + job["workplace"] + " between " + EmploymentScript.windowText(pendingJob) + ", work about " + str(job["hours"]) + " hours and get " + str(job["wage"]) + " credits. Missing shifts without a good reason earns warnings, and " + str(EmploymentScript.WARNINGS_TO_DISMISS) + " in a row means dismissal.")
		addButton("Take the job", "Confirm", "doaccept")
		addButton("Cancel", "Not now", "")
	if(state == "confirmleave"):
		saynn("Leave your job as " + EmploymentScript.jobName(employment.getJobID()) + "? Your record stays, and there is no penalty. Today's shift will not count if you have not done it.")
		addButton("Leave the job", "Confirm", "doleave")
		addButton("Cancel", "Keep it", "")
	if(state == "result"):
		saynn(resultText)
		addButton("Continue", "Back to the board", "")

func _react(_action: String, _args):
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(_action == "endthescene"):
		endScene()
		return
	if(_action == "confirmaccept"):
		pendingJob = str(_args[0])
	if(_action == "doaccept"):
		var result:Dictionary = module.acceptJob(pendingJob)
		if(result["ok"]):
			var job:Dictionary = EmploymentScript.JOBS[pendingJob]
			resultText = "You are now a [b]" + job["name"] + "[/b]. Report to the " + job["workplace"] + " between " + EmploymentScript.windowText(pendingJob) + " and choose [b]Start shift[/b]."
			if(!module.getEmployment().hasOpenShift(GM.main.getDays())):
				resultText += " Today's window is over, so your first shift is tomorrow."
		else:
			resultText = result["reason"]
		setState("result")
		return
	if(_action == "doleave"):
		resultText = "You gave up your job." if module.leaveJob() else "You have no job to leave."
		setState("result")
		return
	setState(_action)

func saveData():
	var data = .saveData()
	data["pendingJob"] = pendingJob
	data["resultText"] = resultText
	return data

func loadData(_data):
	.loadData(_data)
	pendingJob = SAVE.loadVar(_data, "pendingJob", "")
	resultText = SAVE.loadVar(_data, "resultText", "")
