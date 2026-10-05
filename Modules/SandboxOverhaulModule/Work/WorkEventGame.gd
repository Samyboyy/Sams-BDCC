extends Reference
class_name WorkEventGame

# Static glue between WorkEvents (the rules) and the running game: reads real coworkers, feelings, gangs and guards for the facts, and applies the results once. The scene that
# shows the event (WorkShiftScene) only calls the module functions that wrap these.

const EventsScript = preload("res://Modules/SandboxOverhaulModule/Work/WorkEvents.gd")
const EmploymentScript = preload("res://Modules/SandboxOverhaulModule/Work/Employment.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")

const FRIEND_SCORE = 40.0 # trust + affection of a coworker towards the player at which they count as a friend
const HOSTILE_BELOW = -20.0 # affection or trust at or below this is a rival

static func state(module) -> Dictionary:
	return module.getState().workplace

# A supervisor for the workplace: a guard who is really standing there (the same one every time while the guards stay put). "" when no guard is at the workplace.
static func supervisorFor(module, jobID:String) -> String:
	return module.presentSupervisor(jobID)

static func tieOf(module, characterID) -> String:
	if(module.getCells().getCellmate("pc") == characterID):
		return "cellmate"
	var gangs = module.getGangs()
	var own:String = gangs.gangOf("pc")
	if(own != "" && gangs.gangOf(characterID) == own):
		return "gangmate"
	var rel = module.getRelationships()
	if(rel.getFeeling(characterID, "pc", "trust") + rel.getFeeling(characterID, "pc", "affection") >= FRIEND_SCORE):
		return "friend"
	return "stranger"

static func isHostile(module, characterID) -> bool:
	var rel = module.getRelationships()
	if(rel.getFeeling(characterID, "pc", "affection") <= HOSTILE_BELOW || rel.getFeeling(characterID, "pc", "trust") <= HOSTILE_BELOW):
		return true
	var gangs = module.getGangs()
	var theirs:String = gangs.gangOf(characterID)
	return theirs != "" && gangs.getPersonal("pc", theirs) <= -40

static func isMean(characterID) -> bool:
	var theChar = GM.main.getCharacter(characterID)
	if(theChar == null || theChar.getPersonality() == null):
		return false
	return theChar.getPersonality().personalityScore({PersonalityStat.Mean: 1.0}) > 0.15

# Everything WorkEvents.pick needs. The coworkers are the other inmates with this job who can work today.
static func buildFacts(module, jobID:String, day:int) -> Dictionary:
	var coworkers:Array = []
	var rel = module.getRelationships()
	for characterID in module.presentCoworkers(jobID): # only people who are physically at the workplace can be part of what happens there
		if(!module.isAvailableForWork(characterID, day)):
			continue
		coworkers.append({
			"id": characterID, "tie": tieOf(module, characterID), "hostile": isHostile(module, characterID),
			"fear": rel.getFeeling(characterID, "pc", "fear"), "mean": isMean(characterID),
		})
	return {"day": day, "job": jobID, "unsafe": module.getBlockedReason() != "", "boss": supervisorFor(module, jobID), "hostileOk": true, "coworkers": coworkers}

static func names(module, event:Dictionary) -> Dictionary:
	var result:Dictionary = {}
	for key in ["who", "boss"]:
		var characterID:String = str(event.get(key, ""))
		if(characterID != ""):
			result[characterID] = module.characterName(characterID)
	return result

# After a finished shift: counts it, shows the coworkers to the player (they have now seen them work), and maybe starts an event. Returns the pending event or {}.
static func rollAfterShift(module, jobID:String, day:int, rolls:Array = []) -> Dictionary:
	var theState:Dictionary = state(module)
	theState["shifts"] = int(theState["shifts"]) + 1
	for characterID in module.presentCoworkers(jobID):
		var _learned:bool = module.getNpcJobs().learn(characterID)
	if(!theState["pending"].empty()):
		return theState["pending"].duplicate(true)
	var useRolls:Array = rolls
	if(useRolls.empty()):
		useRolls = [randf(), randf(), randf(), randf()]
	var event:Dictionary = EventsScript.pick(theState, buildFacts(module, jobID, day), useRolls)
	if(event.empty()):
		return {}
	EventsScript.markHappened(theState, event, day)
	theState["pending"] = event.duplicate(true)
	return event

static func resolve(module, choiceID:String, rolls:Array = []) -> Dictionary:
	var theState:Dictionary = state(module)
	var event:Dictionary = theState["pending"].duplicate(true)
	if(event.empty()):
		return {"ok": false, "text": "", "fight": ""}
	var valid:bool = false
	for choice in EventsScript.choices(event):
		if(choice["id"] == choiceID):
			valid = true
	if(!valid):
		return {"ok": false, "text": "", "fight": ""}
	theState["pending"] = {} # cleared before anything is applied, so a load in the middle cannot apply it twice
	var rel = module.getRelationships()
	var who:String = str(event.get("who", ""))
	var facts:Dictionary = {
		"fear": rel.getFeeling(who, "pc", "fear") if who != "" else 0.0,
		"respect": rel.getFeeling(who, "pc", "respect") if who != "" else 0.0,
		"combat": module.getCombat().getCombatReputation(), "credits": GM.pc.getCredits(),
	}
	var useRolls:Array = rolls if !rolls.empty() else [randf(), randf()]
	var outcome:Dictionary = EventsScript.resolve(event, choiceID, useRolls, facts, names(module, event))
	var fightWith:String = ""
	var notes:Array = []
	for effect in outcome["effects"]:
		var fightID:String = applyEffect(module, effect, notes)
		if(fightID != ""):
			fightWith = fightID
	var text:String = outcome["text"]
	if(!notes.empty()):
		text += "\n\n" + PoolStringArray(notes).join("\n")
	return {"ok": true, "text": text, "fight": fightWith, "event": event}

# Applies one effect. Returns the enemy's ID for a fight effect, "" otherwise. notes collects the lines to show.
static func applyEffect(module, effect:Dictionary, notes:Array) -> String:
	var day:int = GM.main.getDays()
	match(str(effect.get("type", ""))):
		"feeling":
			var observer:String = str(effect.get("observer", ""))
			if(observer != "" && GM.main.getCharacter(observer) != null):
				var _v:float = module.getRelationships().adjustFeeling(observer, "pc", str(effect["axis"]), float(effect["amount"]))
		"credits":
			var amount:int = int(effect.get("amount", 0))
			if(amount < 0):
				amount = -int(min(-amount, GM.pc.getCredits()))
			if(amount != 0):
				GM.pc.addCredits(amount)
				notes.append(("[color=green]+" if amount > 0 else "[color=red]") + str(amount) + " credits[/color]")
		"attention":
			var change:float = module.getSecurity().addAttention(float(effect.get("amount", 0.0)))
			if(change > 0.0):
				notes.append("[color=orange]The guards take notice of you (Security Attention up).[/color]")
			elif(change < 0.0):
				notes.append("[color=green]The guards think a little better of you (Security Attention down).[/color]")
		"job_warning":
			if(module.getEmployment().addWarning()):
				notes.append("[color=red]Work warning: " + str(module.getEmployment().getWarnings()) + " of " + str(EmploymentScript.WARNINGS_TO_DISMISS) + ".[/color]")
		"stamina":
			GM.pc.addStamina(int(effect.get("amount", 0)))
		"injury":
			var kind:String = InjuriesScript.ARM if effect.get("kind", "arm") == "arm" else InjuriesScript.TRAUMA
			var result:Dictionary = module.getInjuries().applyInjury("pc", kind, InjuriesScript.MINOR)
			module.reportInjury("pc", result)
			module.refreshInjuryEffects("pc")
		"rival":
			applyRival(module, str(effect.get("who", "")), str(effect.get("what", "")), day, notes)
		"fight":
			return str(effect.get("enemy", ""))
	return ""

static func applyRival(module, characterID:String, what:String, day:int, notes:Array) -> void:
	if(characterID == ""):
		return
	var theState:Dictionary = state(module)
	var fear:float = module.getRelationships().getFeeling(characterID, "pc", "fear")
	var gangs = module.getGangs()
	var theirs:String = gangs.gangOf(characterID)
	var outcome:Dictionary = EventsScript.recordRival(theState, characterID, what, day, fear, theirs != "")
	var name:String = module.characterName(characterID)
	if(outcome["transfer"]):
		var jobs = module.getNpcJobs()
		var oldJob:String = jobs.getJob(characterID)
		var newJob:String = jobs.nextOpenJob(oldJob)
		var _moved:bool = jobs.transfer(characterID, newJob, day)
		notes.append(name + " has had enough of you and asks for " + ("another workplace." if newJob != "" else "no job at all."))
	elif(outcome["gang"] && theirs != ""):
		var _p:int = gangs.addPersonal("pc", theirs, -6)
		gangs.addLog(name + " complained to " + gangs.gangName(theirs) + " about you.")
		notes.append(name + " stops coming at you themselves. They go to " + gangs.gangName(theirs) + " instead.")
	elif(outcome["stopped"] && what != "harass"):
		notes.append(name + " will not bother you again for now.")

# The player fought the event's character in a scene. result: [state, how, margin, submitter] as the fight scene reports it.
static func onFightEnded(module, event:Dictionary, enemyID:String, result:Array) -> void:
	var won:bool = result.size() > 0 && result[0] == "win"
	var who:String = str(event.get("who", ""))
	if(enemyID == who && who != ""):
		var notes:Array = []
		applyRival(module, who, "defeat" if won else "harass", GM.main.getDays(), notes)
		for line in notes:
			GM.main.addMessage(line)
