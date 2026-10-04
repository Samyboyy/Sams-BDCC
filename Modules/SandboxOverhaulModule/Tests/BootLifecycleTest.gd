extends Node

# Run (full boot, needs autoloads): godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/BootLifecycleTest.tscn
# Exits with code 1 on failure.

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func _ready():
	GlobalRegistry.registerEverything()
	yield(GlobalRegistry, "loadingFinished")
	
	check(GlobalRegistry.getModule("SandboxOverhaulModule") != null, "module registered")
	var ext = GlobalRegistry.getGameExtender("SandboxGameExtender")
	check(ext != null, "extender registered")
	check(GM.GES.registeredExtenders[ExtendGame.saveLoadData].has(ext), "extender hooked to saveLoadData")
	
	var mainA = load("res://Game/MainScene.gd").new()
	var mainB = load("res://Game/MainScene.gd").new()
	GM.main = mainA
	
	# Through the real GameExtenderSystem, as a save/load does.
	ext.getState().cooldowns["k"] = 7
	var saved = JSON.parse(JSON.print(GM.GES.saveData())).result
	check(saved["extendersData"].has("SandboxGameExtender"), "saved under extender id")
	ext.getState().cooldowns.clear()
	GM.GES.loadData(saved)
	check(ext.getState().getCooldown("k") == 7, "GES round trip")
	GM.GES.loadData(saved)
	check(ext.getState().getCooldown("k") == 7, "reload in same main (rollback)")
	
	# Load into a new MainScene (new game / other save).
	GM.main = mainB
	check(ext.getState().getCooldown("k") == 0, "new main: state reset")
	# Old save without extender entry: GES.loadData skips us, state stays default.
	GM.GES.loadData({})
	GM.GES.loadData({"extendersData": {}})
	check(ext.getState().getCooldown("k") == 0, "old save without entry: defaults")
	# Leak check: A's state, then B without entry.
	ext.getState().cooldowns["leak"] = 1
	GM.main = mainA
	check(!ext.getState().cooldowns.has("leak"), "no leak between mains")
	# Null main (main menu) then fresh main.
	ext.getState().cooldowns["leak"] = 1
	GM.main = null
	check(!ext.getState().cooldowns.has("leak"), "null main resets")
	# get_instance_id handling: int, exactly one reset per switch, freed main -> 0.
	var mainC = load("res://Game/MainScene.gd").new()
	GM.main = mainC
	ext.getState()
	check(typeof(ext.ownerMainId) == TYPE_INT && ext.ownerMainId == mainC.get_instance_id(), "ownerMainId is the int instance id")
	ext.getState().cooldowns["once"] = 1
	ext.getState()
	check(ext.getState().cooldowns.has("once"), "same main: no repeated reset")
	var mainD = load("res://Game/MainScene.gd").new()
	GM.main = mainD
	check(!ext.getState().cooldowns.has("once") && ext.ownerMainId == mainD.get_instance_id(), "C->D resets")
	ext.getState().cooldowns["once"] = 1
	check(ext.getState().cooldowns.has("once"), "C->D resets only once")
	mainD.free() # GM.main now points at a freed object
	check(!is_instance_valid(GM.main), "GM.main is freed")
	check(!ext.getState().cooldowns.has("once") && ext.ownerMainId == 0, "freed main resolves to id 0 and resets")
	GM.main = null
	mainC.free()
	# Relationships through the real extender / GameExtenderSystem.
	GM.main = mainA
	var rel = SandboxOverhaulModule.getRelationships()
	check(rel == ext.getRelationships() && rel == SandboxOverhaulModule.getRelationships(), "same service instance")
	var _f = rel.setFeeling("pc", "dynamicnpc1", "affection", -60)
	_f = rel.setFeeling("dynamicnpc1", "pc", "fear", 40)
	_f = rel.setFeeling("pc", "bob", "trust", 20)
	_f = rel.setFeeling("bob", "ghost", "respect", 10)
	mainA.dynamicCharacters["bob"] = Reference.new() # resolvable by getCharacter
	mainA.dynamicCharacters["dynamicnpc1"] = Reference.new()
	var savedRel = JSON.parse(JSON.print(GM.GES.saveData())).result
	check(rel.hasRelationship("pc", "bob") && rel.hasRelationship("pc", "dynamicnpc1"), "known characters and pc kept by pruning")
	check(!rel.hasRelationship("bob", "ghost") && !rel.getCharacterIDs().has("ghost"), "unknown character pruned before save")
	var savedState = savedRel["extendersData"]["SandboxGameExtender"]["directed_relationships"]
	check(savedState.has("pc") && savedState.has("dynamicnpc1") && savedState["pc"].has("bob") && !savedState.has("bob") && !savedState.has("ghost"), "saved copy has pruned data: " + str(savedState.keys()))
	GM.GES.loadData(JSON.parse(JSON.print(savedRel)).result)
	check(rel.getFeeling("pc", "dynamicnpc1", "affection") == -60.0 && rel.getFeeling("dynamicnpc1", "pc", "fear") == 40.0 and rel.getFeeling("dynamicnpc1", "pc", "affection") == 0.0, "relationships round trip through GES, same service")
	GM.main = mainB
	check(!SandboxOverhaulModule.getRelationships().hasRelationship("pc", "dynamicnpc1") && SandboxOverhaulModule.getRelationships() == rel, "reset between mains, same service")
	var _g = rel.setFeeling("pc", "zed", "trust", 5)
	GM.main = null
	check(SandboxOverhaulModule.getRelationships().getCharacterIDs().size() == 0, "null main resets relationships")
	_g = SandboxOverhaulModule.getRelationships().setFeeling("pc", "zed", "trust", 5)
	var _saved = ext.saveData()
	check(rel.hasRelationship("pc", "zed"), "no pruning without a live main")
	mainA.dynamicCharacters.clear()

	check(SandboxOverhaulModule.getState() != null, "Module.getState works")
	
	GM.main = null
	mainA.free()
	mainB.free()
	print("BootLifecycleTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)
