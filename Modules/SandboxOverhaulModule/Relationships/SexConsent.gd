extends Object
class_name SexConsent

# How a sex encounter started. Decided only from the interaction and the state it was in when the sex began.
# Arousal, orgasm, satisfaction, fetishes and personality are never used.
# In every non-consensual row the sub is the victim and the dom is the responsible character.

const CONSENSUAL = 0 # Everyone agreed or paid (offer accepted, prostitution)
const COERCED = 1 # Agreed under pressure (sex demanded in exchange for something)
const FORCED = 2 # No agreement: grabbed while restrained, unconscious, or punished after a fight
const UNKNOWN = 3 # The code does not say. Nothing is applied.

# interaction id -> interaction state when the sex starts -> category
const TABLE = {
	"Talking": {
		"offered_sex_agreed": CONSENSUAL, # NPC accepted an offer to be fucked
		"offered_self_agreed": CONSENSUAL, # NPC accepted an offer to fuck
		"grabbed_about_to_fuck": FORCED, # Grab&Fuck on someone too restrained to resist
	},
	"Prostitution": {
		"about_to_sex": CONSENSUAL, # Client paid and the offer was accepted
	},
	"Unconscious": {
		"about_to_fuck": FORCED, # Sub starts unconscious
	},
	"PunishInteraction": {
		# Punishment after a fight: the target was defeated, so free agreement is not established, but the code
		# has no explicit refusal, unconsciousness or grab either, so it is COERCED rather than FORCED.
		"about_to_sex": COERCED,
		# about_to_subsex is deliberately missing: the punisher submits to the loser, intent unclear.
	},
	"AskingForKey": {
		"sex_challenge_start": COERCED, # Key is only given if they submit
	},
	# HelpLayEggs, InSlutwall and InStocks are deliberately missing: the code does not say whether the sub wanted it.
}

static func classify(interactionID, stateID) -> int:
	if(TABLE.has(interactionID) && TABLE[interactionID].has(stateID)):
		return TABLE[interactionID][stateID]
	return UNKNOWN

static func isNonConsensual(consent:int) -> bool:
	return consent == COERCED || consent == FORCED

static func getName(consent:int) -> String:
	if(consent == CONSENSUAL):
		return "consensual"
	if(consent == COERCED):
		return "coerced"
	if(consent == FORCED):
		return "forced"
	return "unknown"
