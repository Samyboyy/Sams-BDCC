extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/SandboxStateTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func _init():
	var s = StateScript.new()
	check(s.schema_version == 1 && s.npc_profiles.empty() && s.directed_relationships.empty() && s.major_memories.empty() && s.knowledge.empty() && s.cell_assignments.empty() && s.gang_state.empty() && s.obligations.empty() && s.cooldowns.empty(), "fresh defaults")
	check(s.getNpcProfile("x").empty() && s.getMajorMemories("x").empty() && s.getCellAssignment("x") == "", "safe getters")
	
	s.cell_assignments["bob"] = "A1"
	s.obligations.append({"source_id": "job"})
	s.cooldowns["chat"] = 5
	var json = JSON.print(s.saveData())
	check(json != "", "saveData serialisable")
	var parsed = JSON.parse(json).result # round-trip like a real save: ints become floats
	
	var t = StateScript.new()
	t.loadData(parsed)
	check(t.getCellAssignment("bob") == "A1" && t.obligations.size() == 1 && t.getCooldown("chat") == 5, "round trip restores entries")
	check(t.schema_version == 1 && typeof(t.schema_version) == TYPE_INT, "schema version preserved as int")
	
	t.loadData({})
	check(t.cell_assignments.empty() && t.schema_version == 1, "empty dict")
	t.loadData(null)
	check(t.cell_assignments.empty(), "null data")
	t.loadData({"cooldowns": null, "obligations": "bad", "knowledge": {"a": {}}})
	check(t.cooldowns.empty() && t.obligations.empty() && t.knowledge.has("a"), "missing/null/wrong-type fields")
	t.loadData({"schema_version": 1, "future_field": 123, "cooldowns": {"k": 1}})
	check(t.getCooldown("k") == 1, "unknown future field ignored")
	t.loadData({"schema_version": 99})
	check(t.schema_version == 99, "newer schema version kept")
	
	t.loadData({"schema_version": 0, "cooldowns": {"old": 1}})
	check(t.schema_version == 1 && t.getCooldown("old") == 1, "older schema migrated to current, data kept")
	t.loadData({"schema_version": "garbage"})
	check(t.schema_version == 1, "non-numeric schema version falls back")
	var snap = t.saveData()
	snap["cooldowns"]["mut"] = 1
	check(!t.cooldowns.has("mut"), "saveData returns a copy")
	
	print("SandboxStateTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)
