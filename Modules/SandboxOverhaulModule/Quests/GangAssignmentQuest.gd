extends QuestBase
class_name SandboxGangAssignmentQuest

# The accepted gang assignment in BDCC's own task list (Me > Quest log > Side tasks). It is not stored anywhere: the entry is read from the gang assignment the player really has, so it is
# always up to date, appears when the job is accepted, shows "ready to report" once the objective is done, and disappears when the job is reported, fails, lapses or is cancelled.
# What it says is built by GangGame.taskView (the text is in GangDialogue).

func _init():
	id = "SandboxGangAssignment"

func view() -> Dictionary:
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module == null || GM.main == null || !is_instance_valid(GM.main)):
		return {"visible": false, "title": "", "lines": []}
	return module.getGangTaskView(false)

func getVisibleName():
	return str(view()["title"])

func getProgress():
	return view()["lines"]

func isVisible():
	return bool(view()["visible"])

func isCompleted():
	return false

func isMainQuest():
	return false

func getPriority():
	return 5
