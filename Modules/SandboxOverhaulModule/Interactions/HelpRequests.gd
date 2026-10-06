extends Reference
class_name HelpRequests

# People who count on the player ask for help when they are in a fight in front of them. Static glue between BDCC's GenericAttack (one hook when an NPC fight starts), the
# SandboxHelpRequest interaction that asks the player, and the existing fight intervention (Module.doFightInterruptAction). The rules are here; nothing about ownership beyond a
# record is decided here (Milestone 8 can react to it).
#
# Who asks, strongest bond first: an owner, the leader of the player's gang, a member of the player's gang, a friend or cellmate, anyone who trusts and respects the player highly.
# One request per fight, only when the player is in the same room, free to act, and the fight is still going when they answer. A request that was never shown to the player, or that
# the player could not answer, changes nothing.

const WorkEventGameScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEventGame.gd")

const ALLY_SCORE = 60.0 # trust + respect, both towards the player, at which someone counts as an ally with no other bond
const INTERACTION_ID = "SandboxHelpRequest"

# The bond that makes this character ask: "owner", "leader", "gangmate", "friend", "ally" or "" (they would not ask).
static func bondOf(module, askerID) -> String:
	if(askerID == "" || askerID == "pc"):
		return ""
	var pc = GM.pc
	if(pc != null && pc.isSlaveTo(askerID)):
		return "owner"
	var gangs = module.getGangs()
	var own:String = gangs.playerGang()
	if(own != "" && gangs.gangOf(askerID) == own):
		return "leader" if gangs.isLeader(askerID, own) else "gangmate"
	var tie:String = WorkEventGameScript.tieOf(module, askerID)
	if(tie == "friend" || tie == "cellmate"):
		return "friend"
	var rel = module.getRelationships()
	if(rel.getFeeling(askerID, "pc", "trust") + rel.getFeeling(askerID, "pc", "respect") >= ALLY_SCORE && rel.getFeeling(askerID, "pc", "trust") >= 25.0 && rel.getFeeling(askerID, "pc", "respect") >= 25.0):
		return "ally"
	return ""

static func rank(bond:String) -> int:
	return ["", "ally", "friend", "gangmate", "leader", "owner"].find(bond)

# Whether the player could act on a request right now: a free pawn that can be interrupted and has the strength for it.
static func playerCanAct(module) -> bool:
	if(GM.main == null || GM.pc == null):
		return false
	var pawn = GM.main.IS.getPawn("pc")
	if(pawn == null || (pawn.currentInteraction != null && pawn.currentInteraction.id != "AloneInteraction") || module.isPawnBlocked(pawn)):
		return false
	return playerAble()

# Strong and free enough to take part, whatever else is going on (the request itself is what holds the player when they answer).
static func playerAble() -> bool:
	return GM.pc != null && GM.pc.getStamina() > 0 && !GM.pc.hasBoundArms() && !GM.pc.hasBlockedHands()

# The ongoing GenericAttack between these two (either way round), or null.
static func findFight(askerID, foeID):
	for interaction in GM.main.IS.interactions:
		if(interaction.id == "GenericAttack" && !interaction.wasDeleted):
			var a:String = interaction.getRoleID("starter")
			var b:String = interaction.getRoleID("reacter")
			if((a == askerID && b == foeID) || (a == foeID && b == askerID)):
				return interaction
	return null

# Called when a GenericAttack between two other people starts. Starts a request when one of them is bonded to the player, the player is there to see it and could act.
# Returns the asker's ID, or "".
static func onFightStarted(module, fight) -> String:
	if(GM.main == null || GM.pc == null || fight == null):
		return ""
	var starter:String = fight.getRoleID("starter")
	var reacter:String = fight.getRoleID("reacter")
	if(starter == "" || reacter == "" || starter == "pc" || reacter == "pc"):
		return ""
	var pcPawn = GM.main.IS.getPawn("pc")
	if(pcPawn == null || pcPawn.getLocation() != fight.getLocation() || !playerCanAct(module)):
		return ""
	var askerID:String = ""
	var foeID:String = ""
	var bond:String = ""
	for pair in [[starter, reacter], [reacter, starter]]:
		var candidate:String = bondOf(module, pair[0])
		if(rank(candidate) > rank(bond)):
			bond = candidate
			askerID = pair[0]
			foeID = pair[1]
	if(bond == ""):
		return ""
	var asked:Dictionary = module.getState().cooldowns
	var key:String = "helpasked:" + askerID + ">" + foeID
	if(asked.get(key, -1) == GM.main.getDays() * 86400 + GM.main.getTime()):
		return ""
	asked[key] = GM.main.getDays() * 86400 + GM.main.getTime()
	GM.main.IS.startInteraction(INTERACTION_ID, {"main": "pc"}, {"asker": askerID, "foe": foeID, "bond": bond})
	return askerID

# What the asker says, by their bond.
static func requestText(module, askerID:String, foeID:String, bond:String) -> String:
	var asker:String = module.characterName(askerID)
	var foe:String = module.characterName(foeID)
	match(bond):
		"owner":
			return asker + ", your owner, is in a fight with " + foe + " and looks right at you. [say=" + askerID + "]Do not just stand there. Help me.[/say]"
		"leader":
			return asker + ", who leads your gang, is in a fight with " + foe + ". [say=" + askerID + "]You. Over here. I need you in this.[/say]"
		"gangmate":
			return asker + " of your gang is fighting " + foe + " and spots you. [say=" + askerID + "]Hey! We stick together, remember? A hand, here![/say]"
		"friend":
			return asker + ", your friend, is fighting " + foe + " and catches your eye. [say=" + askerID + "]Please. I could use some help.[/say]"
	return asker + " is fighting " + foe + " and calls out to you. [say=" + askerID + "]You! Give me a hand!?[/say]"

# The fight the player joined for somebody is decided (the player won, lost or the foe gave up): the one shared, exactly-once thank-you. Returns whether anything was said.
# Winning: owner Trust +4, Respect +4, Affection +1 (and a minor warning forgiven, or the next demand a day later); friend Trust +3, Affection +2, Respect +1; gangmate their Trust +2, Respect +2 and gang standing +2;
# gang leader Trust +2, Respect +3 and standing +3; anybody else who asked Trust +1, Respect +1. Losing after trying: Trust +1. One full reward per person per day, and one per incident.
static func acknowledge(module, foeID, playerWon:bool) -> bool:
	if(module == null || !(foeID is String)):
		return false
	var key:String = "helpinc:" + str(foeID)
	var incident:Dictionary = module.getState().cooldowns.get(key, {})
	if(incident.empty()):
		return false
	var _gone:bool = module.getState().cooldowns.erase(key) # once per incident: reopening a scene or reporting twice finds nothing
	if(module.getHelpClock() - int(incident.get("stamp", 0)) > 2 * 3600):
		return false # an old one: the fight it belonged to is long over
	var askerID:String = str(incident.get("asker", ""))
	var bond:String = str(incident.get("bond", ""))
	if(askerID == "" || GM.main.getCharacter(askerID) == null):
		return false
	var rel = module.getRelationships()
	var gangs = module.getGangs()
	var day:int = GM.main.getDays()
	var rewardKey:String = "helpreward:" + askerID
	var full:bool = playerWon && int(module.getState().cooldowns.get(rewardKey, -100)) != day
	var asker:String = module.characterName(askerID)
	if(!playerWon):
		var _small:float = rel.adjustFeeling(askerID, "pc", "trust", 1.0)
		GM.main.addMessage(asker + ": \"You tried. That counts.\"")
		return true
	if(!full):
		GM.main.addMessage(asker + " nods at you. Helping again today earns no more than that.")
		return true
	module.getState().cooldowns[rewardKey] = day
	var line:String = "Thanks."
	var theirs:String = gangs.gangOf(askerID)
	match(bond):
		"owner":
			var _a:float = rel.adjustFeeling(askerID, "pc", "trust", 4.0)
			var _b:float = rel.adjustFeeling(askerID, "pc", "respect", 4.0)
			var _c:float = rel.adjustFeeling(askerID, "pc", "affection", 1.0)
			var ownership = module.getOwnership()
			var _eased:String = ownership.showGratitude(module.getHelpClock(), day)
			match(ownership.style()):
				"harsh":
					line = "Not bad. Remember who you did that for."
				"controlling":
					line = "Good. That is what I keep you for."
				_:
					line = "Thank you. I will not forget that."
		"friend":
			var _d:float = rel.adjustFeeling(askerID, "pc", "trust", 3.0)
			var _e:float = rel.adjustFeeling(askerID, "pc", "affection", 2.0)
			var _f:float = rel.adjustFeeling(askerID, "pc", "respect", 1.0)
			line = "Thanks. I owe you."
		"gangmate", "leader":
			var leader:bool = bond == "leader"
			var _g:float = rel.adjustFeeling(askerID, "pc", "trust", 2.0)
			var _h:float = rel.adjustFeeling(askerID, "pc", "respect", 3.0 if leader else 2.0)
			if(theirs != "" && theirs == gangs.playerGang()):
				var _s:int = gangs.addPersonal("pc", theirs, 3.0 if leader else 2.0)
			line = "Thanks. The gang will hear about it."
		_:
			var _i:float = rel.adjustFeeling(askerID, "pc", "trust", 1.0)
			var _j:float = rel.adjustFeeling(askerID, "pc", "respect", 1.0)
			line = "Thanks. I mean it."
	GM.main.addMessage(asker + ": \"" + line + "\"")
	return true

# Applies the player's answer once. choice: "help", "breakup" or "refuse". delivered: the request was actually shown to the player; without that nothing at all changes.
# Returns the text to show.
static func resolve(module, askerID:String, foeID:String, bond:String, choice:String, delivered:bool) -> String:
	if(!delivered):
		return ""
	var fight = findFight(askerID, foeID)
	if(fight == null):
		return "By the time you move, it is over. Nobody holds it against you."
	var pcPawn = GM.main.IS.getPawn("pc")
	if(pcPawn == null || (!playerAble() && choice != "refuse")):
		return "You are in no state to do anything about it."
	var rel = module.getRelationships()
	var gangs = module.getGangs()
	var theirs:String = gangs.gangOf(askerID)
	var asker:String = module.characterName(askerID)
	if(choice == "help"):
		var role:String = "starter" if fight.getRoleID("starter") == askerID else "reacter"
		module.getState().cooldowns["helpinc:" + foeID] = {"asker": askerID, "bond": bond, "stamp": module.getHelpClock()} # the thanks come when the fight is decided (see acknowledge)
		module.doFightInterruptAction(fight, pcPawn, "join_" + role)
		return "You throw yourself in beside " + asker + "."
	if(choice == "breakup"):
		module.doFightInterruptAction(fight, pcPawn, "break_up")
		if(fight.wasDeleted):
			var _t2:float = rel.adjustFeeling(askerID, "pc", "trust", 3.0)
			return "You step between them and the fight stops. " + asker + " is grateful, if a little irritated you did not simply join in."
		return "You try to part them. It does not work, and " + asker + " noticed that you tried."
	# refuse
	match(bond):
		"owner":
			var _o:int = gangs.addRefusal("owner:" + askerID)
			return "You stay out of it. " + asker + " owns you, and will remember that you did not come when called."
		"leader":
			var count:int = gangs.addRefusal(theirs)
			var _a:float = rel.adjustFeeling(askerID, "pc", "trust", -6.0)
			var _b:float = rel.adjustFeeling(askerID, "pc", "respect", -6.0)
			var lost:int = gangs.addPersonal("pc", theirs, -6.0 - (4.0 if count >= 3 else 0.0))
			return "You walk away from your own leader's fight. [color=red]" + asker + " and the gang will not forget it (standing " + str(lost) + ").[/color]"
		"gangmate":
			var _c:int = gangs.addRefusal(theirs)
			var _d:float = rel.adjustFeeling(askerID, "pc", "trust", -4.0)
			var _e:float = rel.adjustFeeling(askerID, "pc", "respect", -3.0)
			var lostMate:int = gangs.addPersonal("pc", theirs, -3.0)
			return "You turn your back on one of your own. [color=red]" + asker + " saw, and so did the gang (standing " + str(lostMate) + ").[/color]"
		"friend", "ally":
			var _f:float = rel.adjustFeeling(askerID, "pc", "trust", -5.0)
			var _g:float = rel.adjustFeeling(askerID, "pc", "respect", -3.0)
			return "You do not step in. " + asker + " looks hurt, and counts it against you."
	return ""
