extends SlaveActionBase

# Shared parts of the module's slave actions (they sit in BDCC's own slave menu next to the existing ones and use its Talk / Reward / Activities lists).
# None of them can be resisted the way BDCC's forced actions can: they are conversation and care, and every effect goes through the directed relationships.

const OwnershipGameScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipGame.gd")
const OwnershipScript = preload("res://Modules/SandboxOverhaulModule/Ownership/Ownership.gd")
const TextScript = preload("res://Modules/SandboxOverhaulModule/Ownership/OwnershipText.gd")

func svc():
	return OwnershipGameScript.svc()

func rel():
	return OwnershipGameScript.rel()

func slaveRecord(_slaveID) -> Dictionary:
	return svc().slaveRecord(_slaveID)

func disposition(_slaveID) -> String:
	return OwnershipGameScript.slaveDisposition(_slaveID)

func escaping(_slaveID) -> bool:
	return !slaveRecord(_slaveID).empty() && !slaveRecord(_slaveID).get("escape", {}).empty()

func isActionVisible(_slaveID):
	return OwnershipGameScript.isReady() && svc().hasSlave(_slaveID)

func say(text:String) -> String:
	return "[say=npc]" + text + "[/say]"
