extends SceneBase

# Somebody else tries to own a player who already has an owner (the game's "Offer to enslave" and "Ask to become slave" talk options lead here instead of adding a second owner). There is never a second owner:
# the current owner may defend their claim (see OwnershipGame.resolveClaim for the rules), the player may back the owner, back the claimant, or stay out of it, and only the winner is the owner afterwards.
#
# args: [claimantID]

const OwnershipGameScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipGame.gd")

var claimantID:String = ""
var result:String = ""
var resultText:String = ""
var claimantWon:bool = false

func _init():
	sceneID = "OwnershipDisputeScene"

func _initScene(_args = []):
	claimantID = str(_args[0]) if (_args is Array && _args.size() > 0) else ""

func svc():
	return OwnershipGameScript.svc()

func nameOf(id) -> String:
	return OwnershipGameScript.nameOf(id)

func resolveCustomCharacterName(_charID):
	if(_charID == "npc"):
		return claimantID

func supportsShowingPawns() -> bool:
	return true

func _run():
	if(!OwnershipGameScript.isReady() || claimantID == ""):
		saynn("Nothing happens.")
		addButton("Continue", "Carry on", "endthescene")
		return
	addCharacter(claimantID)
	if(result != ""):
		saynn(resultText)
		addButton("Continue", "Carry on", "endthescene")
		return
	var s = svc()
	if(!s.hasOwner() || s.ownerID() == claimantID):
		saynn("Nothing needs deciding: " + nameOf(claimantID) + " and your owner are the same person, or you are not owned.")
		addButton("Continue", "Carry on", "endthescene")
		return
	var ownerName:String = nameOf(s.ownerID())
	saynn("[b]" + nameOf(claimantID) + " wants you.[/b]\n" + ownerName + " already owns you. A claim like that is settled between the two of them, and you are not the one who decides it: you can only say whose side you are on.")
	saynn("[color=#c8c8d8]" + OwnershipGameScript.claimAssessment(claimantID) + "[/color]")
	addButton("Back " + ownerName, "Stand with your owner: it helps them if it comes to a fight", "side", ["owner"])
	addButton("Back " + nameOf(claimantID), "Stand with the claimant: it helps them, and your owner will remember", "side", ["claimant"])
	addButton("Stay out of it", "Keep out of it", "side", ["none"])

func _react(_action: String, _args):
	if(_action == "endthescene"):
		endScene()
		return
	if(_action == "side"):
		var resolved:Dictionary = OwnershipGameScript.resolveClaim(claimantID, str(_args[0]))
		result = str(resolved["result"])
		resultText = str(resolved["text"])
		claimantWon = bool(resolved["claimantOwns"])
		if(claimantWon):
			GM.main.RS.startSpecialRelantionship("SoftSlavery", claimantID) # the old owner is already gone, so this is the only owner
		setState("")
		return
	setState(_action)

func saveData():
	var data = .saveData()
	data["claimantID"] = claimantID
	data["result"] = result
	data["resultText"] = resultText
	data["claimantWon"] = claimantWon
	return data

func loadData(_data):
	.loadData(_data)
	claimantID = SAVE.loadVar(_data, "claimantID", "")
	result = SAVE.loadVar(_data, "result", "")
	resultText = SAVE.loadVar(_data, "resultText", "")
	claimantWon = SAVE.loadVar(_data, "claimantWon", false)
