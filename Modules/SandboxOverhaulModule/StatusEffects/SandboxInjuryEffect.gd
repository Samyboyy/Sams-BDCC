extends StatusEffectBase
class_name SandboxInjuryEffect

# Shows a lasting combat injury from SandboxState.injuries and applies its penalty through BDCC's own buff and modifier
# calculations. Subclasses only set the injury type. The state is the single source of truth, so nothing is saved here.

const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")

var injuryType = ""

func _init():
	isBattleOnly = false
	alwaysCheckedForPlayer = true
	alwaysCheckedForNPCs = true
	priorityDuringChecking = 20

func getInjuries():
	return GlobalRegistry.getGameExtender("SandboxGameExtender").getInjuries()

func shouldApplyTo(_npc):
	return getInjuries().has(_npc.getID(), injuryType)

func getSeverity() -> int:
	if(character == null):
		return 0
	return getInjuries().getSeverity(character.getID(), injuryType)

func getEffectName():
	var severity:int = getSeverity()
	return InjuriesScript.fullName(injuryType, severity) if severity > 0 else InjuriesScript.typeName(injuryType)

func getEffectDesc():
	var severity:int = getSeverity()
	if(severity <= 0):
		return "A lasting injury."
	var text:String = "Lasting damage from a fight. It heals by itself, or the medbay can treat it for credits - about " + InjuriesScript.remainingText(getInjuries().getRemainingHours(character.getID(), injuryType)) + " remaining."
	if(injuryType == InjuriesScript.LEG):
		# Applied as multipliers by BaseCharacter.getMaxStamina and getDodgeChance, so they are not buffs and are listed here.
		text += "\n" + InjuriesScript.penaltyText(injuryType, severity)
	return text

func getIconColor():
	return IconColorRed

func getBuffs():
	var severity:int = getSeverity()
	if(severity <= 0):
		return []
	var pct:int = InjuriesScript.PENALTY_PERCENT[severity]
	if(injuryType == InjuriesScript.ARM):
		return [buff(Buff.PhysicalDamageBuff, [-pct])]
	if(injuryType == InjuriesScript.TRAUMA):
		return [buff(Buff.ReceivedPhysicalDamageBuff, [pct])]
	return []
