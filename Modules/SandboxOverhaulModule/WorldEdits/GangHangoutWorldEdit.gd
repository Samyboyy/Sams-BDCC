extends WorldEditBase

# Puts each gang's hangout room into its own zone group (zone_gang0 to zone_gang3) so the gangs' hangout tasks can send members there. Safe to apply any number of times.

const GangGameScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangGame.gd")

func _init():
	id = "SandboxGangHangoutWorldEdit"

func apply(world: GameWorld):
	applyAll(world)

# The edit itself, untyped so tests can pass a stand-in for the world.
func applyAll(world):
	GangGameScript.refreshHangoutZones(world)
