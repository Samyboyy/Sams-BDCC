extends "res://Scenes/SceneBase.gd"

func _init():
	sceneID = "WorkInMinesScene"

func _run():
	if(state == ""):
		saynn("You grab a pickaxe and go deep into the mines.")

		addButton("Work", "Do the work", "work")
	
	if(state == "work"):
		saynn("You spend a few hours, pushing minecarts around and mining rocks. You feel tired as heck but you earned something at least.")
		
		addButton("Continue", "Finally rest", "endthescene")

		GM.ES.triggerRun(Trigger.WorkingInMines)

func _react(_action: String, _args):
	if(_action == "work"):
		
		var pay = 1
		var sandbox = GlobalRegistry.getModule("SandboxOverhaulModule")
		if(sandbox != null):
			pay = sandbox.getInformalMiningPay()
		GM.pc.addCredits(pay)
		GM.pc.addStamina(-40)
		
		processTime(2*60*60)
		
		if(GM.ES.triggerReact(Trigger.WorkingInMines)):
			endScene()
			return
		
		if(pay > 0):
			addMessage("You earned 1 work credit")
		else:
			addMessage("The foreman already paid you for your ore today, so this earned nothing. A job from the canteen job board pays a proper wage.")

	if(_action == "endthescene"):
		endScene()
		return
	
	setState(_action)
