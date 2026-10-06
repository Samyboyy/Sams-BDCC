extends QuestBase
class_name SandboxOwnerCheckInQuest

# The nightly check-in your owner expects. It is read live from the ownership record, so it appears when the obligation is created, is correct at every moment, and disappears the moment it is settled (nothing is stored here).
# What it says is built by OwnershipGame.journalView.

func _init():
	id = "SandboxOwnerCheckIn"

func view() -> Dictionary:
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module == null || GM.main == null || !is_instance_valid(GM.main)):
		return {"visible": false, "title": "", "lines": []}
	return module.getOwnershipJournal("checkin")

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
	return 8
