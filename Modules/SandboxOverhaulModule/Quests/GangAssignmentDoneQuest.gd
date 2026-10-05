extends QuestBase
class_name SandboxGangAssignmentDoneQuest

# The archive of the latest gang assignment the player reported back (shown under "Completed tasks"). A job that failed, lapsed or was cancelled is simply removed from the list.

func _init():
	id = "SandboxGangAssignmentDone"

func view() -> Dictionary:
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module == null || GM.main == null || !is_instance_valid(GM.main)):
		return {"visible": false, "title": "", "lines": []}
	return module.getGangTaskView(true)

func getVisibleName():
	return str(view()["title"])

func getProgress():
	return view()["lines"]

func isVisible():
	return bool(view()["visible"])

func isCompleted():
	return true

func isMainQuest():
	return false

func getPriority():
	return 5
