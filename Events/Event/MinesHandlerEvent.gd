extends EventBase

func _init():
	id = "minesHandlerEvent"

func registerTriggers(es):
	es.addTrigger(self, Trigger.EnteringRoom, "mining_shafts_entering")

func run(_triggerID, _args):
	var sandbox = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(sandbox != null && GM.main.getFlag("Mining_IntroducedToMinning", false)):
		var theButton:Dictionary = sandbox.getMiningWorkButton() # one way to work the mines: the mine worker's shift
		if(theButton["enabled"]):
			addButtonWithChecks(theButton["label"], theButton["tooltip"], "sandbox_shift", [], [ButtonChecks.NotLate, ButtonChecks.NotHandsBlocked])
		else:
			addDisabledButton(theButton["label"], theButton["tooltip"])
		return
	if(GM.pc.getStamina() > 0):
		if(!GM.main.getFlag("Mining_IntroducedToMinning", false)):
			addButtonWithChecks("Work", "See what's it about", "first_time", [], [ButtonChecks.NotLate, ButtonChecks.NotHandsBlocked])
		else:
			addButtonWithChecks("Work", "Go work in the mines", "not_first_time", [], [ButtonChecks.NotLate, ButtonChecks.NotHandsBlocked])
	else:
		addDisabledButton("Work", "You are way too tired to work")
	
func getPriority():
	return 0

func onButton(_method, _args):
	if(_method == "first_time"):
		runScene("FirstTimeInMinesScene")
	if(_method == "not_first_time"):
		runScene("WorkInMinesScene")
	if(_method == "sandbox_shift"):
		runScene("WorkShiftScene")
