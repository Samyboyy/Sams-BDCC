extends Reference

# How an owner treats the player: one of three styles worked out from the owner's existing personality (and nothing else). No game access, so it can be tested on its own.
# The style never changes for a character: it only depends on their personality values.

const LENIENT = "lenient"
const CONTROLLING = "controlling"
const HARSH = "harsh"
const STYLES = [LENIENT, CONTROLLING, HARSH]

# Everything the style changes, in one place.
#   checkin_every: nights between the check-ins the owner asks for
#   demand_gap: days between two demands (never less than two)
#   escalation: how fast misses climb the three steps (verbal warning, compensation, punishment)
#   first_level: the step the first miss starts at (1 unless the style reacts strongly from the start)
#   willingness: added to the owner's openness to negotiating and forgiving
#   punish: scales what a punishment costs the player
#   protection: how much of the owner's strength shields the player
#   buyout: the credits that buy the player out, before the relationship adjusts it
#   release_wins: separate days the player must beat the owner before they can demand release
const PARAMS = {
	"lenient": {"checkin_every": 3, "demand_gap": 4, "escalation": 0.5, "willingness": 0.25, "punish": 0.6, "protection": 0.7, "buyout": 30, "release_wins": 2},
	"controlling": {"checkin_every": 2, "demand_gap": 3, "escalation": 1.0, "willingness": 0.0, "punish": 1.0, "protection": 0.9, "buyout": 45, "release_wins": 2},
	"harsh": {"checkin_every": 1, "demand_gap": 2, "escalation": 1.5, "first_level": 2, "willingness": -0.25, "punish": 1.4, "protection": 1.0, "buyout": 60, "release_wins": 3},
}

const NAMES = {"lenient": "Lenient", "controlling": "Controlling", "harsh": "Harsh"}

# traits: {"mean", "subby", "naive", "power"} (personality stats from -1 to 1 and BDCC's level-based power, about 0.5 to 1.5).
# Hard, dominant, strong characters are harsh; kind, soft, naive ones are lenient; everybody else is controlling.
static func styleOf(traits:Dictionary) -> String:
	var hardness:float = float(traits.get("mean", 0.0)) * 0.8 + (float(traits.get("power", 0.9)) - 0.9) * 0.4 - float(traits.get("naive", 0.0)) * 0.2 - float(traits.get("subby", 0.0)) * 0.3
	if(hardness < -0.15):
		return LENIENT
	if(hardness > 0.25):
		return HARSH
	return CONTROLLING

static func isStyle(style) -> bool:
	return (style is String) && PARAMS.has(style)

static func params(style) -> Dictionary:
	return PARAMS[style] if isStyle(style) else PARAMS[CONTROLLING]

static func nameOf(style) -> String:
	return str(NAMES.get(style, "Controlling"))

# Plain-language description of what the style means for the player.
static func describe(style) -> String:
	match(style):
		LENIENT:
			return "Lenient: asks little of you (a check-in about every third night), gives you room to negotiate, punishes lightly and protects you only half-heartedly."
		HARSH:
			return "Harsh: expects you every night and issues demands often. Misses are punished fast and hard, there is little room to negotiate, and the protection is real."
	return "Controlling: wants regular proof of obedience (a check-in about every other night), listens only if you have earned it, and protects what is theirs."

static func checkinText(style) -> String:
	var every:int = int(params(style)["checkin_every"])
	if(every <= 1):
		return "every night"
	if(every == 2):
		return "about every other night"
	return "about every third night"

static func demandsText(style) -> String:
	match(style):
		LENIENT:
			return "an occasional small errand"
		HARSH:
			return "frequent demands, sometimes for contraband or a beating"
	return "regular demands for credits, goods and work"
