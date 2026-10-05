extends Reference
class_name WorkEvents

# Things that happen at work. No game access, so it can be tested on its own: callers pass facts and dice, and get back plain results to apply.
#
# About one completed shift in four has an event (EVENT_CHANCE), never more than one per shift, and the same coworker is not featured again within
# PAIR_COOLDOWN days. Events involve real coworkers (friends, cellmates, gang mates, rivals) and a real supervisor, and every choice has a consequence in the existing systems:
# feelings, Security Attention, credits, the job's warnings, injuries and real fights. Events never rewrite themselves: a picked event is stored as "pending" until the player
# chooses, and resolving it clears it, so loading cannot pay or punish twice.
#
# SandboxState.workplace = {
#   "last_day": day of the last event (-1 none), "shifts": completed shifts seen, "events": events that happened,
#   "pairs": {coworkerID: day of the last event featuring them},
#   "rivals": {coworkerID: {"wins": int, "defeats": int, "harass": int, "stopped": bool, "last_day": int, "gang_help": bool}},
#   "pending": {} or the open event
# }

const EVENT_CHANCE = 0.25
const MIN_GAP_DAYS = 0 # a second event on the same day is never picked (there is one paid shift a day anyway)
const PAIR_COOLDOWN = 2
const FEAR_STOP = 40.0 # a rival who fears the player this much stops harassing them
const WINS_STOP = 2 # beaten this often, a rival stops
const WINS_TRANSFER = 3 # beaten or humiliated this often, a rival asks for another job
const HARASS_BEFORE_GANG = 3 # a rival who has harassed this often without winning goes to their gang instead
const FAMILIES = ["supervisor", "rival", "request", "opportunity", "hostile"]
const FAMILY_WEIGHTS = {"supervisor": 3, "rival": 3, "request": 3, "opportunity": 3, "hostile": 1}
const CLOSE_TIES = ["friend", "cellmate", "gangmate"]

static func isNumberValue(value) -> bool:
	return (typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) && !is_nan(float(value)) && !is_inf(float(value))

static func defaults() -> Dictionary:
	return {"last_day": -1, "shifts": 0, "events": 0, "pairs": {}, "rivals": {}, "pending": {}}

static func defaultRival() -> Dictionary:
	return {"wins": 0, "defeats": 0, "harass": 0, "stopped": false, "last_day": -1, "gang_help": false}

static func sanitizeCount(value, ceiling:int = 100000) -> int:
	return int(clamp(round(float(value)), 0, ceiling)) if isNumberValue(value) else 0

# Clean copy of a saved workplace dictionary. Unknown entries are dropped, numbers clamped, nothing aliased. A pending event survives only if it is complete.
static func sanitize(raw) -> Dictionary:
	var result:Dictionary = defaults()
	if(!(raw is Dictionary)):
		return result
	if(isNumberValue(raw.get("last_day"))):
		result["last_day"] = int(round(float(raw["last_day"])))
	result["shifts"] = sanitizeCount(raw.get("shifts"))
	result["events"] = sanitizeCount(raw.get("events"))
	var pairs = raw.get("pairs")
	if(pairs is Dictionary):
		for id in pairs:
			if((id is String) && id != "" && isNumberValue(pairs[id])):
				result["pairs"][id] = int(round(float(pairs[id])))
	var rivals = raw.get("rivals")
	if(rivals is Dictionary):
		for id in rivals:
			if(!(id is String) || id == "" || !(rivals[id] is Dictionary)):
				continue
			var entry:Dictionary = defaultRival()
			var source:Dictionary = rivals[id]
			entry["wins"] = sanitizeCount(source.get("wins"), 1000)
			entry["defeats"] = sanitizeCount(source.get("defeats"), 1000)
			entry["harass"] = sanitizeCount(source.get("harass"), 1000)
			entry["stopped"] = typeof(source.get("stopped")) == TYPE_BOOL && source["stopped"]
			entry["gang_help"] = typeof(source.get("gang_help")) == TYPE_BOOL && source["gang_help"]
			if(isNumberValue(source.get("last_day"))):
				entry["last_day"] = int(round(float(source["last_day"])))
			result["rivals"][id] = entry
	var pending = raw.get("pending")
	if(pending is Dictionary && isValidEvent(pending)):
		result["pending"] = cleanEvent(pending)
	return result

static func isValidEvent(event) -> bool:
	if(!(event is Dictionary)):
		return false
	var family = event.get("family")
	if(!(family is String) || !FAMILIES.has(family) || !(event.get("variant") is String) || !isNumberValue(event.get("day")) || !(event.get("id") is String)):
		return false
	return VARIANTS.has(family) && VARIANTS[family].has(event["variant"])

static func cleanEvent(event:Dictionary) -> Dictionary:
	return {
		"id": str(event["id"]), "family": event["family"], "variant": event["variant"], "day": int(round(float(event["day"]))),
		"job": str(event.get("job", "")), "who": str(event.get("who", "")), "boss": str(event.get("boss", "")), "tie": str(event.get("tie", "stranger")),
		"stage": str(event.get("stage", "open")),
	}

# ---- The events ----
# Variants of each family (the story the event tells).
const VARIANTS = {
	"supervisor": ["dressing_down"],
	"rival": ["needling"],
	"request": ["workload", "cover", "loan"],
	"opportunity": ["contraband", "theft", "accident"],
	"hostile": ["cornered"],
}

# Which coworkers fit which families: feasibility is decided from facts.
# facts: {"day", "job", "unsafe", "boss": guard character ID or "", "hostileOk": bool, "coworkers": [{"id", "tie": friend|cellmate|gangmate|stranger, "hostile": bool, "fear": float (their fear of the player), "mean": bool}]}
static func isRivalActive(state:Dictionary, characterID, fear:float) -> bool:
	var entry:Dictionary = state["rivals"].get(characterID, defaultRival())
	return !entry["stopped"] && fear < FEAR_STOP && int(entry["wins"]) < WINS_STOP

static func pairKey(characterID) -> String:
	return str(characterID)

static func pairReady(state:Dictionary, characterID, day:int) -> bool:
	var key:String = pairKey(characterID)
	return !state["pairs"].has(key) || day - int(state["pairs"][key]) >= PAIR_COOLDOWN

static func nextRoll(rolls:Array, cursor:Dictionary) -> float:
	var index:int = int(cursor.get("i", 0))
	cursor["i"] = index + 1
	return float(rolls[index]) if index < rolls.size() else 0.5

static func pickIndex(count:int, roll:float) -> int:
	return int(clamp(int(floor(roll * float(count))), 0, count - 1)) if count > 0 else -1

# Does this shift have an event, and which? Returns {} (nothing happens) or the event to store as pending. rolls are consumed in a fixed order, so tests can steer it.
static func pick(state:Dictionary, facts:Dictionary, rolls:Array) -> Dictionary:
	var cursor:Dictionary = {"i": 0}
	var day:int = int(facts.get("day", 0))
	if(bool(facts.get("unsafe", false)) || !state["pending"].empty()):
		return {}
	if(nextRoll(rolls, cursor) >= EVENT_CHANCE):
		return {}
	if(int(state["last_day"]) >= 0 && day - int(state["last_day"]) < MIN_GAP_DAYS + 1):
		return {}
	var boss:String = str(facts.get("boss", ""))
	var coworkers:Array = []
	for entry in facts.get("coworkers", []):
		if(entry is Dictionary && entry.get("id", "") is String && entry["id"] != "" && pairReady(state, entry["id"], day)):
			coworkers.append(entry)
	var close:Array = []
	var rivals:Array = []
	var friendly:Array = []
	for entry in coworkers:
		if(CLOSE_TIES.has(entry.get("tie", "stranger"))):
			close.append(entry)
		if(bool(entry.get("hostile", false))):
			if(isRivalActive(state, entry["id"], float(entry.get("fear", 0.0)))):
				rivals.append(entry)
		else:
			friendly.append(entry)
	var feasible:Array = []
	if(boss != "" && !coworkers.empty()):
		feasible.append(["supervisor", FAMILY_WEIGHTS["supervisor"]])
	if(!rivals.empty()):
		feasible.append(["rival", FAMILY_WEIGHTS["rival"]])
	if(!friendly.empty()):
		feasible.append(["request", FAMILY_WEIGHTS["request"]])
	feasible.append(["opportunity", FAMILY_WEIGHTS["opportunity"]])
	var hostileOk:bool = bool(facts.get("hostileOk", false))
	if(hostileOk):
		var cornering:Array = []
		for entry in rivals:
			if(bool(entry.get("mean", false)) && float(entry.get("fear", 0.0)) < FEAR_STOP * 0.75):
				cornering.append(entry)
		if(!cornering.empty()):
			feasible.append(["hostile", FAMILY_WEIGHTS["hostile"]])
	var familyRoll:float = nextRoll(rolls, cursor)
	var total:int = 0
	for entry in feasible:
		total += int(entry[1])
	var running:float = 0.0
	var family:String = feasible[0][0]
	for entry in feasible:
		running += float(entry[1]) / float(total)
		if(familyRoll < running):
			family = entry[0]
			break
	var whoRoll:float = nextRoll(rolls, cursor)
	var variantRoll:float = nextRoll(rolls, cursor)
	var who:Dictionary = {}
	var variant:String = VARIANTS[family][pickIndex(VARIANTS[family].size(), variantRoll)]
	if(family == "supervisor"):
		var pool:Array = close if !close.empty() else coworkers
		who = pool[pickIndex(pool.size(), whoRoll)]
	elif(family == "rival"):
		who = rivals[pickIndex(rivals.size(), whoRoll)]
	elif(family == "request"):
		var pool2:Array = close if !close.empty() else friendly
		who = pool2[pickIndex(pool2.size(), whoRoll)]
	elif(family == "hostile"):
		var pool3:Array = []
		for entry in rivals:
			if(bool(entry.get("mean", false)) && float(entry.get("fear", 0.0)) < FEAR_STOP * 0.75):
				pool3.append(entry)
		who = pool3[pickIndex(pool3.size(), whoRoll)]
	else:
		if(variant == "contraband" || coworkers.empty()):
			who = {}
		else:
			who = coworkers[pickIndex(coworkers.size(), whoRoll)]
	if(who.empty() && (variant == "theft" || variant == "accident")):
		variant = "contraband"
	return {
		"id": "w" + str(day) + "_" + str(int(state["events"]) + 1), "family": family, "variant": variant, "day": day, "job": str(facts.get("job", "")),
		"who": str(who.get("id", "")), "boss": boss, "tie": str(who.get("tie", "stranger")), "stage": "open",
	}

# ---- Telling it ----
# The scene text. names: {characterID: display name}.
static func describe(event:Dictionary, names:Dictionary) -> String:
	var who:String = str(names.get(event.get("who", ""), "a coworker"))
	var boss:String = str(names.get(event.get("boss", ""), "the supervisor"))
	var tieText:String = ""
	if(event.get("tie", "") == "friend"):
		tieText = " Your friend"
	elif(event.get("tie", "") == "cellmate"):
		tieText = " Your cellmate"
	elif(event.get("tie", "") == "gangmate"):
		tieText = " Someone from your gang"
	match(str(event["variant"])):
		"dressing_down":
			return "A raised voice cuts across the floor. " + boss + " is dressing down " + who + " over some mistake, loudly, in front of everyone." + (tieText + " is the one being shouted at." if tieText != "" else "") + " Nobody else is moving."
		"needling":
			return who + " has been at it again: bumping your station, muttering when you pass, making sure you hear. It is getting hard to ignore."
		"workload":
			return who + " is badly behind on the quota and the shift is nearly over. They glance your way." + (tieText + " would rather not ask, but they will." if tieText != "" else "")
		"cover":
			return who + " leans close and asks quietly whether you could cover for them for a bit. They want to slip away for a while. " + boss + " is not watching right now." if boss != "" else who + " leans close and asks quietly whether you could cover for them for a bit."
		"loan":
			return who + " asks, a little embarrassed, if you can spare a few credits until payday."
		"contraband":
			return "Wedged behind some crates you notice a small wrapped package that does not belong to the job. Nobody is looking."
		"theft":
			return "You notice " + who + " quietly pocketing something from the stores. They have not seen you notice."
		"accident":
			return "A crate slides loose and slams down right next to " + who + ". They stumble back, shaken, one hand clamped over their arm."
		"cornered":
			return "The shift ends and the work area empties out faster than usual. When you turn to leave, " + who + " is standing in the way, and nobody else is near."
	return ""

# The player's choices: [{"id", "label", "tooltip"}].
static func choices(event:Dictionary) -> Array:
	match(str(event["variant"])):
		"dressing_down":
			return [
				{"id": "intervene", "label": "Step in", "tooltip": "Put yourself between them and the supervisor"},
				{"id": "challenge", "label": "Challenge the supervisor", "tooltip": "Tell the supervisor exactly what you think. This can go badly"},
				{"id": "deescalate", "label": "Calm things down", "tooltip": "Say the right words to the supervisor and let it pass"},
				{"id": "ignore", "label": "Keep working", "tooltip": "It is not your problem"},
			]
		"needling":
			return [
				{"id": "stand_up", "label": "Stand up to them", "tooltip": "Tell them to back off. How it goes depends on how they see you"},
				{"id": "fight", "label": "Fight", "tooltip": "Settle it now. A real fight, with real consequences"},
				{"id": "back_down", "label": "Back down", "tooltip": "Let it go and give them what they want"},
				{"id": "seek_help", "label": "Tell the supervisor", "tooltip": "Ask for help. They will not forget it"},
				{"id": "avoid", "label": "Avoid them", "tooltip": "Stay out of their way for now"},
			]
		"workload":
			return [
				{"id": "help", "label": "Help with the quota", "tooltip": "Stay on your feet a bit longer and pull their share. It costs stamina"},
				{"id": "refuse", "label": "Refuse", "tooltip": "You have your own work"},
			]
		"cover":
			return [
				{"id": "cover", "label": "Cover for them", "tooltip": "Cover their station. If anyone notices, it falls on you too"},
				{"id": "refuse", "label": "Refuse", "tooltip": "Not worth the risk"},
			]
		"loan":
			return [
				{"id": "share", "label": "Lend 4 credits", "tooltip": "It may or may not be paid back, but they will remember it"},
				{"id": "refuse", "label": "Refuse", "tooltip": "Credits are tight"},
			]
		"contraband":
			return [
				{"id": "keep", "label": "Pocket it", "tooltip": "Sell it on later. If it is found on you it will be trouble"},
				{"id": "hand_in", "label": "Hand it in", "tooltip": "A small reward, and the guards remember you were honest"},
				{"id": "leave", "label": "Leave it", "tooltip": "Pretend you never saw it"},
			]
		"theft":
			return [
				{"id": "report", "label": "Report it", "tooltip": "Tell the supervisor. The guards will like it, the thief will not"},
				{"id": "conceal", "label": "Say nothing", "tooltip": "Keep it to yourself. The thief will owe you, if nobody finds out"},
				{"id": "confront", "label": "Confront them", "tooltip": "Let them know you saw. Quietly"},
			]
		"accident":
			return [
				{"id": "help", "label": "Help them", "tooltip": "Lift the crate and check on them. It may hurt"},
				{"id": "report", "label": "Call the supervisor", "tooltip": "Get someone with authority over here"},
				{"id": "ignore", "label": "Keep working", "tooltip": "It is not your problem"},
			]
		"cornered":
			return [
				{"id": "fight", "label": "Fight", "tooltip": "Shove past them. A real fight"},
				{"id": "pay", "label": "Hand over some credits", "tooltip": "Pay your way out (up to 8 credits)"},
				{"id": "talk_down", "label": "Talk them down", "tooltip": "Stay calm. Fear and respect matter here"},
				{"id": "call_help", "label": "Shout for the guards", "tooltip": "Loud and humiliating for them, and the guards will notice"},
			]
	return []

# ---- Resolving ----
# What a choice does. Returns {"text": scene text, "effects": [effect, ...]}. Effects are plain dictionaries the game applies once:
#   {"type": "feeling", "observer": id, "target": id, "axis": "trust"|"respect"|"affection"|"fear", "amount": float}
#   {"type": "credits", "amount": int}   {"type": "attention", "amount": float}   {"type": "job_warning"}   {"type": "stamina", "amount": int}
#   {"type": "fight", "enemy": id}   {"type": "injury", "target": id, "kind": "arm"|"body"}   {"type": "rival", "who": id, "what": "win"|"harass"|"stop"|"gang"}
#   {"type": "gang_standing", "who": id, "amount": int}
# names: {id: display name}. facts: {"fear": their fear of the player, "combat": the player's combat reputation, "credits": the player's credits, "respect": their respect for the player}.
static func resolve(event:Dictionary, choiceID:String, rolls:Array, facts:Dictionary, names:Dictionary) -> Dictionary:
	var cursor:Dictionary = {"i": 0}
	var roll:float = nextRoll(rolls, cursor)
	var who:String = str(event.get("who", ""))
	var boss:String = str(event.get("boss", ""))
	var whoName:String = str(names.get(who, "they"))
	var bossName:String = str(names.get(boss, "the supervisor"))
	var close:bool = CLOSE_TIES.has(event.get("tie", "stranger"))
	var effects:Array = []
	var text:String = ""
	match(str(event["variant"]) + ":" + choiceID):
		"dressing_down:intervene":
			if(roll < 0.6):
				text = "You step between them and walk the supervisor through what went wrong, calmly, until " + bossName + " waves a hand and walks off, glaring. " + whoName + " lets out a breath."
				effects = [feel(who, "trust", 10), feel(who, "respect", 6), feel(who, "affection", 4), attention(2.0)]
			else:
				text = bossName + " turns on you instead. You are told, in front of everyone, exactly what happens to inmates who think they run the floor."
				effects = [feel(who, "trust", 4), attention(4.0), {"type": "job_warning"}, feel(boss, "respect", -3)]
		"dressing_down:challenge":
			if(roll < 0.4):
				text = "You tell " + bossName + " what you think of how they treat people. A hand drops to the baton. There is no time to talk any more."
				effects = [feel(who, "respect", 10), attention(6.0), {"type": "fight", "enemy": boss}]
			else:
				text = "You say it plainly and loudly enough for the whole floor to hear. " + bossName + " goes red, mutters something about paperwork, and leaves. The floor is very quiet afterwards."
				effects = [feel(who, "respect", 12), feel(who, "trust", 8), attention(6.0), feel(boss, "respect", -6)]
		"dressing_down:deescalate":
			if(roll < 0.7):
				text = "You say just the right thing, polite and a little humble, and " + bossName + " lets it drop. " + whoName + " gives you a short nod."
				effects = [feel(who, "trust", 5), feel(boss, "respect", 2)]
			else:
				text = "You try to smooth it over but " + bossName + " is not in the mood to be talked to. It runs its course anyway."
				effects = [feel(who, "trust", 1)]
		"dressing_down:ignore":
			text = "You keep your eyes on the work. " + whoName + " notices exactly who did not look up."
			effects = [feel(who, "trust", -8 if close else -4), feel(who, "affection", -5 if close else -2)]
		"needling:stand_up":
			var chance:float = clamp(0.35 + float(facts.get("fear", 0.0)) / 100.0 * 0.6 + float(facts.get("combat", 0.0)) / 400.0, 0.1, 0.9)
			if(roll < chance):
				text = "You tell " + whoName + " to back off, quietly and without blinking. For a moment they weigh it up, then step away."
				effects = [feel(who, "fear", 10), feel(who, "respect", 6), {"type": "rival", "who": who, "what": "win"}]
			else:
				text = whoName + " laughs in your face and shoulders past you, hard enough to rattle the shelf. It has not worked."
				effects = [feel(who, "respect", -2), {"type": "rival", "who": who, "what": "harass"}]
		"needling:fight":
			text = "You put your tools down. " + whoName + " grins as if this is what they wanted."
			effects = [{"type": "fight", "enemy": who}, {"type": "rival", "who": who, "what": "harass"}]
		"needling:back_down":
			text = "You say nothing and slide a few credits across the bench. " + whoName + " pockets them without looking at you."
			effects = [{"type": "credits", "amount": -3}, feel(who, "respect", -4), {"type": "rival", "who": who, "what": "harass"}]
		"needling:seek_help":
			text = "You tell the supervisor. " + whoName + " is pulled aside and told to behave. They look at you the entire time."
			effects = [feel(who, "affection", -8), feel(who, "trust", -6), attention(-1.0), {"type": "rival", "who": who, "what": "harass"}]
		"needling:avoid":
			text = "You find reasons to be at the other end of the room. It works. For now."
			effects = [{"type": "rival", "who": who, "what": "harass"}]
		"workload:help":
			text = "You stay on your feet and pull their share until the quota is met. " + whoName + " is clearly relieved."
			effects = [{"type": "stamina", "amount": -15}, feel(who, "trust", 8), feel(who, "affection", 4), feel(who, "respect", 2)]
		"workload:refuse":
			text = "You tell " + whoName + " you have your own work. They nod, a little stiffly, and turn back to their station."
			effects = [feel(who, "trust", -4), feel(who, "affection", -2)]
		"cover:cover":
			if(roll < 0.75):
				text = "You cover their station and nobody asks. When " + whoName + " slips back they owe you one and know it."
				effects = [feel(who, "trust", 10), feel(who, "affection", 3)]
			else:
				text = bossName + " notices the empty station and finds you standing at it. The excuse sounds thin even to you."
				effects = [feel(who, "trust", 8), attention(4.0), {"type": "job_warning"}]
		"cover:refuse":
			text = "You shake your head. " + whoName + " shrugs as if they expected it, and does not ask again."
			effects = [feel(who, "trust", -3)]
		"loan:share":
			text = "You count out four credits and press them into " + whoName + "'s hand. They look at them, then at you."
			effects = [{"type": "credits", "amount": -4}, feel(who, "trust", 8), feel(who, "affection", 5)]
		"loan:refuse":
			text = "You tell " + whoName + " credits are tight. They nod and say they understand, and do not quite look at you."
			effects = [feel(who, "trust", -3), feel(who, "respect", -2)]
		"contraband:keep":
			text = "You slip the package into your clothes and carry on. It will sell for something, if nobody checks you first."
			effects = [{"type": "credits", "amount": 6}, attention(4.0)]
		"contraband:hand_in":
			text = "You hand it to the supervisor. They look at it, at you, and say nothing more than 'good'. A few credits find their way to you."
			effects = [{"type": "credits", "amount": 2}, attention(-3.0), feel(boss, "respect", 4)]
		"contraband:leave":
			text = "You leave it where it is. Somebody else will find it, or it will still be here tomorrow."
			effects = []
		"theft:report":
			text = "You quietly tell the supervisor what you saw. " + whoName + " is searched before the shift ends. They will know who talked."
			effects = [feel(who, "affection", -10), feel(who, "trust", -10), attention(-2.0), feel(boss, "respect", 4)]
		"theft:conceal":
			if(roll < 0.7):
				text = "You say nothing. " + whoName + " catches your eye across the room and gives a very small nod."
				effects = [feel(who, "trust", 8), feel(who, "respect", 3)]
			else:
				text = "You say nothing, but a guard saw more than you thought. Your silence is noted."
				effects = [feel(who, "trust", 5), attention(3.0)]
		"theft:confront":
			text = "You drop your voice and let " + whoName + " know you saw. They go very still, then hand over a few credits to keep it quiet."
			effects = [{"type": "credits", "amount": 3}, feel(who, "respect", -4), feel(who, "fear", 4)]
		"accident:help":
			text = "You heave the crate aside and get " + whoName + " sitting down. They are shaken but fine, and they will remember who was there."
			if(roll < 0.2):
				text += " Your own arm took the strain in a way it should not have."
				effects = [{"type": "stamina", "amount": -10}, feel(who, "trust", 8), feel(who, "affection", 5), {"type": "injury", "target": "pc", "kind": "arm"}]
			else:
				effects = [{"type": "stamina", "amount": -10}, feel(who, "trust", 8), feel(who, "affection", 5)]
		"accident:report":
			text = "You shout for the supervisor, who arrives, assesses, and takes over. It is handled."
			effects = [feel(who, "trust", 3), feel(boss, "respect", 2)]
		"accident:ignore":
			text = "You keep working. Someone else helps " + whoName + " up. They saw who did not."
			effects = [feel(who, "trust", -8), feel(who, "affection", -4)]
		"cornered:fight":
			text = "You do not wait for the first push."
			effects = [{"type": "fight", "enemy": who}, {"type": "rival", "who": who, "what": "harass"}]
		"cornered:pay":
			var give:int = int(min(8, int(facts.get("credits", 0))))
			text = "You hand over what they ask for, " + str(give) + " credits, and they step aside with a smile that is not friendly."
			effects = [{"type": "credits", "amount": -give}, feel(who, "respect", -6), {"type": "rival", "who": who, "what": "harass"}]
		"cornered:talk_down":
			var talkChance:float = clamp(0.25 + float(facts.get("fear", 0.0)) / 100.0 * 0.5 + float(facts.get("respect", 0.0)) / 100.0 * 0.4, 0.1, 0.85)
			if(roll < talkChance):
				text = "You keep your voice level and your hands visible. " + whoName + " looks you over, decides it is not worth it, and steps aside."
				effects = [feel(who, "respect", 8), feel(who, "fear", 4)]
			else:
				text = "Your words do nothing. " + whoName + " takes a few credits from you and shoves you out of the way."
				effects = [{"type": "credits", "amount": -int(min(5, int(facts.get("credits", 0))))}, feel(who, "respect", -3), {"type": "rival", "who": who, "what": "harass"}]
		"cornered:call_help":
			text = "You shout. Guards arrive faster than anyone expected and " + whoName + " is escorted away, red-faced, with half the floor watching."
			effects = [feel(who, "affection", -10), feel(who, "respect", -4), attention(1.0), feel(boss, "respect", 2) if boss != "" else attention(0.0)]
	return {"text": text, "effects": effects}

static func feel(observer, axis:String, amount:float) -> Dictionary:
	return {"type": "feeling", "observer": observer, "target": "pc", "axis": axis, "amount": amount}

static func attention(amount:float) -> Dictionary:
	return {"type": "attention", "amount": amount}

# ---- Rivals ----
# Applies a "rival" effect to the stored record and tells what the world should now do: {"transfer": bool, "gang": bool, "stopped": bool}.
static func recordRival(state:Dictionary, characterID, what:String, day:int, fear:float, inGang:bool) -> Dictionary:
	var outcome:Dictionary = {"transfer": false, "gang": false, "stopped": false}
	if(!(characterID is String) || characterID == ""):
		return outcome
	if(!state["rivals"].has(characterID)):
		state["rivals"][characterID] = defaultRival()
	var entry:Dictionary = state["rivals"][characterID]
	entry["last_day"] = day
	if(what == "win"):
		entry["wins"] = int(entry["wins"]) + 1
	elif(what == "defeat"):
		entry["wins"] = int(entry["wins"]) + 1
		entry["defeats"] = int(entry["defeats"]) + 1
	elif(what == "harass"):
		entry["harass"] = int(entry["harass"]) + 1
	elif(what == "stop"):
		entry["stopped"] = true
	if(int(entry["wins"]) >= WINS_TRANSFER):
		outcome["transfer"] = true
		entry["stopped"] = true
	if(int(entry["wins"]) >= WINS_STOP || fear >= FEAR_STOP):
		entry["stopped"] = true
	if(!entry["stopped"] && int(entry["harass"]) >= HARASS_BEFORE_GANG && int(entry["wins"]) == 0 && !entry["gang_help"]):
		entry["gang_help"] = true
		entry["stopped"] = true # they go to their gang instead of coming back themselves
		outcome["gang"] = inGang
	outcome["stopped"] = bool(entry["stopped"])
	return outcome

static func getRival(state:Dictionary, characterID) -> Dictionary:
	return state["rivals"].get(characterID, defaultRival()).duplicate()

# Stores that an event featured this coworker today, and that it happened.
static func markHappened(state:Dictionary, event:Dictionary, day:int) -> void:
	state["last_day"] = day
	state["events"] = int(state["events"]) + 1
	if(str(event.get("who", "")) != ""):
		state["pairs"][pairKey(event["who"])] = day
