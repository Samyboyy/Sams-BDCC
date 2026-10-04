extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/DirectedRelationshipsTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const RelScript = preload("res://Modules/SandboxOverhaulModule/Relationships/DirectedRelationships.gd")
const AxisScript = preload("res://Modules/SandboxOverhaulModule/Relationships/FeelingAxis.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001

func _init():
	var s = StateScript.new()
	var r = RelScript.new(s)

	# Defaults and ranges
	for axis in AxisScript.ALL:
		check(r.getFeeling("a", "b", axis) == 0.0, "default " + axis)
	check(AxisScript.getMin("fear") == 0.0 && AxisScript.getMax("fear") == 100.0, "fear range")
	for axis in ["affection", "trust", "respect", "desire"]:
		check(AxisScript.getMin(axis) == -100.0 && AxisScript.getMax(axis) == 100.0, "range " + axis)
		check(near(r.setFeeling("a", "b", axis, 500), 100.0) && near(r.getFeeling("a", "b", axis), 100.0), "clamp high " + axis)
		check(near(r.setFeeling("a", "b", axis, -500), -100.0), "clamp low " + axis)
		var _x = r.setFeeling("a", "b", axis, 0)
	check(near(r.setFeeling("a", "b", "fear", -50), 0.0), "fear clamps at 0")
	check(near(r.setFeeling("a", "b", "fear", 500), 100.0), "fear clamps at 100")
	var _fr = r.setFeeling("a", "b", "fear", 0)
	check(!r.hasRelationship("a", "b") && s.directed_relationships.empty(), "all reset to default removes everything")

	# Applied delta after clamping
	check(near(r.adjustFeeling("a", "b", "trust", 30), 30.0), "adjust returns delta")
	check(near(r.adjustFeeling("a", "b", "trust", 90), 70.0), "adjust returns clamped delta, not total")
	check(r.adjustFeeling("a", "b", "trust", 10) == 0.0, "adjust at max returns 0")
	check(near(r.adjustFeeling("a", "b", "trust", -250), -200.0), "adjust down to min")
	check(near(r.adjustFeeling("a", "b", "fear", 20), 20.0) && near(r.adjustFeeling("a", "b", "fear", -50), -20.0), "fear adjust clamps at 0")
	var _y = r.setFeeling("a", "b", "trust", 0)
	check(!s.directed_relationships.has("a"), "observer removed when pair empties")
	check(r.adjustFeeling("a", "b", "fear", 0) == 0.0 && s.directed_relationships.empty(), "zero adjust creates nothing")

	# Directionality and axis independence
	var _z = r.setFeeling("a", "b", "affection", -80)
	_z = r.setFeeling("a", "b", "fear", 70)
	check(near(r.getFeeling("a", "b", "affection"), -80) && near(r.getFeeling("a", "b", "fear"), 70), "hate plus fear")
	check(r.getFeeling("b", "a", "affection") == 0.0 && r.getFeeling("b", "a", "fear") == 0.0 && !r.hasRelationship("b", "a"), "B->A independent of A->B")
	_z = r.setFeeling("b", "a", "affection", 40)
	check(near(r.getFeeling("a", "b", "affection"), -80) && near(r.getFeeling("b", "a", "affection"), 40), "both directions stored separately")
	check(r.getFeeling("a", "b", "trust") == 0.0 && r.getFeeling("a", "b", "respect") == 0.0 && r.getFeeling("a", "b", "desire") == 0.0, "other axes untouched")
	_z = r.setFeeling("a", "c", "respect", 60)
	check(r.getFeeling("a", "c", "affection") == 0.0 && near(r.getFeeling("a", "c", "respect"), 60), "respect without affection")
	_z = r.setFeeling("a", "d", "desire", 70)
	_z = r.setFeeling("a", "d", "trust", -50)
	check(near(r.getFeeling("a", "d", "desire"), 70) && near(r.getFeeling("a", "d", "trust"), -50), "desire with negative trust")
	_z = r.setFeeling("a", "e", "affection", 60)
	_z = r.setFeeling("a", "e", "respect", -40)
	check(near(r.getFeeling("a", "e", "affection"), 60) && near(r.getFeeling("a", "e", "respect"), -40), "affection with negative respect")
	check(r.describe("a", "b").find("affection=-80") != -1 && r.describe("a", "b").find("fear=70") != -1, "describe shows values")
	print("DEV " + r.describe("a", "b"))
	print("DEV " + r.describe("b", "a"))

	# Invalid input
	var before = JSON.print(s.saveData())
	check(r.setFeeling("", "b", "trust", 5) == 0.0 && r.setFeeling("a", "", "trust", 5) == 0.0, "empty ids rejected")
	check(r.setFeeling("a", "a", "trust", 5) == 0.0 && r.adjustFeeling("a", "a", "trust", 5) == 0.0, "self relationship rejected")
	check(r.setFeeling(null, "b", "trust", 5) == 0.0 && r.setFeeling(5, "b", "trust", 5) == 0.0, "non-string ids rejected")
	check(r.setFeeling("a", "b", "bogus", 5) == 0.0 && r.adjustFeeling("a", "b", "bogus", 5) == 0.0 && r.getFeeling("a", "b", "bogus") == 0.0, "unknown axis")
	check(r.getFeeling("a", "b", null) == 0.0, "null axis")
	check(near(r.setFeeling("a", "b", "trust", "high"), 0.0) && r.adjustFeeling("a", "b", "trust", "x") == 0.0, "non-numeric values")
	check(r.adjustFeeling("a", "b", "trust", true) == 0.0 && r.adjustFeeling("a", "b", "trust", null) == 0.0, "bool and null amounts")
	check(r.adjustFeeling("a", "b", "trust", NAN) == 0.0 && r.adjustFeeling("a", "b", "trust", INF) == 0.0, "NaN and INF amounts")
	check(!r.hasRelationship("", "b") && !r.hasRelationship("a", "a"), "hasRelationship invalid ids")
	check(JSON.print(s.saveData()) == before, "invalid calls changed nothing")
	check(r.describe("", "b") == "invalid relationship", "describe invalid")

	# Removal
	r.removeRelationship("a", "b")
	check(!r.hasRelationship("a", "b") && r.hasRelationship("b", "a"), "removeRelationship is directional")
	r.removeCharacter("a")
	check(!r.hasRelationship("a", "c") && !r.hasRelationship("b", "a") && !s.directed_relationships.has("a") && !s.directed_relationships.has("b"), "removeCharacter removes both directions and empty observers")
	r.removeCharacter("")
	r.removeCharacter(null)

	# JSON round trip
	var _w = r.setFeeling("x", "y", "affection", 12.5)
	_w = r.setFeeling("x", "y", "fear", 33)
	_w = r.setFeeling("y", "x", "desire", -20)
	var parsed = JSON.parse(JSON.print(s.saveData())).result
	var t = StateScript.new()
	var r2 = RelScript.new(t)
	t.loadData(parsed)
	check(near(r2.getFeeling("x", "y", "affection"), 12.5) && near(r2.getFeeling("x", "y", "fear"), 33) && near(r2.getFeeling("y", "x", "desire"), -20), "round trip")
	check(r2.getFeeling("y", "x", "affection") == 0.0, "round trip keeps direction")

	# State replacement while retaining the same service
	var rs = RelScript.new(s)
	var _v = rs.setFeeling("p", "q", "trust", 25)
	s.clear()
	check(!rs.hasRelationship("p", "q") && rs.getFeeling("p", "q", "trust") == 0.0, "service sees cleared state")
	_v = rs.setFeeling("p", "q", "trust", 10)
	check(near(rs.getFeeling("p", "q", "trust"), 10) && s.directed_relationships.has("p"), "service writes to the cleared state")
	s.loadData({"directed_relationships": {"m": {"n": {"a": 55}}}})
	check(!rs.hasRelationship("p", "q") && near(rs.getFeeling("m", "n", "affection"), 55), "service sees loaded state")
	_v = rs.adjustFeeling("m", "n", "affection", 10)
	check(near(s.directed_relationships["m"]["n"]["a"], 65), "service writes to the loaded state")

	# Malformed and aliasing
	var bad = {"directed_relationships": {
		"o1": "str", "o2": {"t2": 5, "o2": {"a": 10}, "": {"a": 10}, "t3": {"a": "x", "t": null, "f": -9}},
		"o3": {"t4": {"a": 500, "t": -500, "r": 1.5, "f": 500, "d": true}},
		"o4": {"t5": {"a": 0, "f": 0}},
		"": {"t6": {"a": 5}},
	}}
	s.loadData(bad)
	var dr = s.directed_relationships
	check(dr.keys() == ["o3"], "only the valid observer survives: " + str(dr.keys()))
	check(near(dr["o3"]["t4"]["a"], 100) && near(dr["o3"]["t4"]["t"], -100) && near(dr["o3"]["t4"]["r"], 1.5) && near(dr["o3"]["t4"]["f"], 100) && dr["o3"]["t4"]["d"] == 0.0, "values clamped, bool ignored")
	s.loadData({"directed_relationships": "bad"})
	check(s.directed_relationships.empty(), "non-dictionary field")
	var input = {"directed_relationships": {"u": {"v": {"a": 5, "future": {"deep": [1]}}}}}
	s.loadData(input)
	input["directed_relationships"]["u"]["v"]["a"] = 99
	input["directed_relationships"]["u"]["v"]["future"]["deep"].append(2)
	check(near(s.directed_relationships["u"]["v"]["a"], 5) && s.directed_relationships["u"]["v"]["future"]["deep"].size() == 1, "no aliasing with input")
	var saved = s.saveData()
	saved["directed_relationships"]["u"]["v"]["a"] = 77
	check(near(s.directed_relationships["u"]["v"]["a"], 5), "saveData does not alias state")

	# Unknown fields
	s.loadData({"directed_relationships": {"u": {"v": {"future": 7}}}})
	check(s.directed_relationships["u"]["v"].has("future") && s.directed_relationships["u"]["v"]["future"] == 7, "unknown-only pair preserved")
	check(!s.directed_relationships["u"]["v"].has("a"), "no recognised keys added to unknown-only pair")
	var rf = RelScript.new(s)
	check(!rf.hasRelationship("u", "v"), "unknown-only pair is not a relationship")
	var _u = rf.setFeeling("u", "v", "trust", 5)
	_u = rf.setFeeling("u", "v", "trust", 0)
	check(s.directed_relationships["u"]["v"].has("future") && s.directed_relationships["u"]["v"].size() == 1, "unknown key survives service cleanup")

	print("DirectedRelationshipsTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)
