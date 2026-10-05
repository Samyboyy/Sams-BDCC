extends GlobalTask

# Sends free daytime members of one gang to stand at their hangout (BDCC's own HangoutAt goal, with the room put in the zone "gang<slot>" by GangHangoutWorldEdit).
# Registered four times (three established gangs and the player's), see GangHangoutTask0 to 3. Members are only sent when the pawn is free, so bedtime, work,
# interactions, slavery and punishment always win, and only a few at a time.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")

var slot:int = 0

func _init():
	goalID = InteractionGoal.HangoutAt
	maxAssignedUnscaled = 3

func canDoTask(_pawn:CharacterPawn) -> bool:
	return GangGameScript.canHangOut(_pawn.charID, slot)

func configureGoal(_pawn:CharacterPawn, _goal):
	_goal.zone = "gang" + str(slot)
