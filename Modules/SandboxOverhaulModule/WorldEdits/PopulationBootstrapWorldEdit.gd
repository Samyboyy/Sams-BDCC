extends WorldEditBase

# Runs when a game starts or loads, after the map and the other edits are in place and before the first frame the player sees: every inmate is put where today's plan has them
# (see Prison/PopulationDirector.bootstrap), so the prison is already lived in when control comes back. Applying it again places nobody new: people who have a record keep their place.

func _init():
	id = "SandboxPopulationBootstrapWorldEdit"

func apply(world: GameWorld):
	applyAll(world)

# The edit itself, untyped so tests can pass a stand-in for the world.
func applyAll(world):
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(module != null):
		var _placed:int = module.bootstrapPopulation(world)
