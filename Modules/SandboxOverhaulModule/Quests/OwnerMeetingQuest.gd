extends QuestBase
class_name SandboxOwnerMeetingQuest

# The meeting your owner asked for. It is read live from the ownership record, so it appears when the owner announces it, is correct at every moment, and disappears the moment the meeting has happened or is cancelled (nothing is stored here).
# What it says is built by OwnershipGame.journalView.

func _init():
	id = "SandboxOwnerMeeting"

func view() -> Dictionary:
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module == null || GM.main == null || !is_instance_valid(GM.main)):
		return {"visible": false, "title": "", "lines": []}
	return module.getOwnershipJournal("meeting")

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
