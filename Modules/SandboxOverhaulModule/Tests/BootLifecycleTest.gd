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
	check(SandboxOverhaulModule.getState() != null, "Module.getState works")
	
	GM.main = null
	mainA.free()
	mainB.free()
	print("BootLifecycleTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)
