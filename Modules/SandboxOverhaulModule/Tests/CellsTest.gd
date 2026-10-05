extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/CellsTest.gd
# Exits with code 1 on failure.

const StateScript = preload("res://Modules/SandboxOverhaulModule/Core/SandboxState.gd")
const RelScript = preload("res://Modules/SandboxOverhaulModule/Relationships/DirectedRelationships.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")
const InjuriesScript = preload("res://Modules/SandboxOverhaulModule/Injuries/Injuries.gd")
const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func make():
	var s = StateScript.new()
	return [s, CellsScript.new(s)]

func entries(ids, block = "orange"):
	var result = []
	for id in ids:
		result.append([id, block])
	return result

func _init():
	# ---- Schedule ----
	var ids = []
	for i in range(40):
		ids.append("dynamicnpc" + str(i))
	var beds = {}
	var wakes = {}
	for id in ids:
		var bed = CellsScript.bedtimeSeconds(id)
		var wake = CellsScript.wakeSeconds(id)
		check(bed >= 21 * 3600 - 1800 and bed <= 21 * 3600 + 1800, "bedtime within 30 minutes of 21:00 for " + id)
		check(wake >= 7 * 3600 - 1800 and wake <= 7 * 3600 + 1800, "wake time within 30 minutes of 07:00 for " + id)
		check(bed == CellsScript.bedtimeSeconds(id) and wake == CellsScript.wakeSeconds(id), "offsets are stable for " + id)
		beds[bed] = true
		wakes[wake] = true
	check(beds.size() >= 20 and wakes.size() >= 20, "different inmates have different offsets: " + str(beds.size()) + " and " + str(wakes.size()))
	check(CellsScript.offsetSeconds("a", "bed") != CellsScript.offsetSeconds("a", "wake") or CellsScript.offsetSeconds("b", "bed") != CellsScript.offsetSeconds("b", "wake"), "bedtime and wake offsets are independent")
	var id0 = ids[0]
	var bed0 = CellsScript.bedtimeSeconds(id0)
	var wake0 = CellsScript.wakeSeconds(id0)
	check(!CellsScript.isNight(id0, 12 * 3600) and !CellsScript.isNight(id0, 20 * 3600), "daytime is not night")
	check(!CellsScript.isNight(id0, bed0 - 1) and CellsScript.isNight(id0, bed0), "night starts exactly at the inmate's bedtime")
	check(CellsScript.isNight(id0, 23 * 3600) and CellsScript.isNight(id0, 0) and CellsScript.isNight(id0, 3 * 3600) and CellsScript.isNight(id0, 6 * 3600), "night continues across midnight to 06:00")
	check(CellsScript.isNight(id0, wake0 - 1) and !CellsScript.isNight(id0, wake0), "night ends exactly at the wake time")
	check(CellsScript.isNight(id0, 86400 + 23 * 3600) == CellsScript.isNight(id0, 23 * 3600) and CellsScript.isNight(id0, 86400 + 12 * 3600) == false, "times past 24 hours wrap")
	var asleepAt2200 = 0
	var awakeAt2000 = 0
	var asleepAt0630 = 0
	for id in ids:
		asleepAt2200 += 1 if CellsScript.isNight(id, 22 * 3600) else 0
		awakeAt2000 += 1 if !CellsScript.isNight(id, 20 * 3600) else 0
		asleepAt0630 += 1 if CellsScript.isNight(id, 6 * 3600 + 29 * 60) else 0
	check(asleepAt2200 == 40 and awakeAt2000 == 40, "everyone is in bed by 22:00 and still up at 20:00")
	check(asleepAt0630 >= 1 and asleepAt0630 < 40 or asleepAt0630 == 40, "the prison wakes gradually around 07:00")
	var gradual = 0
	var morning = 0
	for id in ids:
		morning += 1 if !CellsScript.isNight(id, 7 * 3600) else 0
	gradual = morning
	check(gradual > 0 and gradual < 40, "at exactly 07:00 some inmates are up and some are not: " + str(gradual))
	var settled2100 = 0
	for id in ids:
		settled2100 += 1 if CellsScript.isNight(id, 21 * 3600) else 0
	check(settled2100 > 0 and settled2100 < 40, "at exactly 21:00 some have settled and some have not: " + str(settled2100))

	# ---- Labels ----
	check(CellsScript.cellLabel("orange", 3) == "Orange 3" and CellsScript.cellLabel("red", 12) == "Red 12" and CellsScript.cellLabel("lilac", 1) == "Lilac 1", "cell labels")
	check(CellsScript.coloredCellLabel("orange", 3) == "[color=cyan]Orange 3[/color]", "coloured label")

	# ---- Assignment ----
	var m = make()
	var s = m[0]
	var c = m[1]
	check(c.getCell("pc").empty() and !c.isAssigned("pc") and c.getOccupants("orange", 1).empty() and c.getCellmate("pc") == "" and c.getOccupiedCells().empty(), "defaults are empty and safe")
	var placed = c.ensureAssigned([["pc", "orange"], ["b", "orange"], ["a", "orange"], ["c", "orange"]])
	check(placed == 4, "four placed")
	check(c.getCell("pc")["cell"] == 1 and c.getCell("pc")["block"] == "orange", "the player gets cell 1")
	check(c.getCell("a")["cell"] == 1 and c.getCellmate("pc") == "a" and c.getCellmate("a") == "pc", "the first inmate (by id) becomes the player's cellmate")
	check(c.getCell("b")["cell"] == 2 and c.getCell("c")["cell"] == 2 and c.getCellmate("b") == "c", "the next two share cell 2")
	check(c.getOccupants("orange", 1) == ["pc", "a"] and c.getOccupants("orange", 2) == ["b", "c"], "occupants listed player first, then by id")
	check(c.getOccupiedCells().size() == 2 and c.getOccupiedCells()[0]["cell"] == 1 and c.getOccupiedCells()[1]["occupants"] == ["b", "c"], "occupied cells")
	var snapshot = JSON.print(s.saveData()["cell_assignments"])
	check(c.ensureAssigned([["pc", "orange"], ["a", "orange"], ["b", "orange"], ["c", "orange"]]) == 0 and JSON.print(s.saveData()["cell_assignments"]) == snapshot, "running it again changes nothing")
	var m2 = make()
	m2[1].ensureAssigned([["c", "orange"], ["pc", "orange"], ["a", "orange"], ["b", "orange"]])
	check(JSON.print(m2[0].saveData()["cell_assignments"]) == snapshot, "the result does not depend on the order they are listed")

	# Capacity and growth
	m = make()
	c = m[1]
	var many = ["pc"]
	for i in range(11):
		many.append("n" + str(i).pad_zeros(2))
	c.ensureAssigned(entries(many))
	var maxOccupants = 0
	for cell in c.getOccupiedCells():
		maxOccupants = max(maxOccupants, cell["occupants"].size())
	check(maxOccupants == 2 and c.getOccupiedCells().size() == 6, "12 people use 6 cells with two each, no huge empty prison: " + str(c.getOccupiedCells().size()))
	check(c.getCell("n10")["cell"] == 6, "cells are numbered by population")

	# New inmates fill free capacity without reshuffling; removal frees a place
	m = make()
	c = m[1]
	c.ensureAssigned(entries(["pc", "a", "b", "c", "d"]))
	var before = JSON.print(m[0].cell_assignments)
	c.ensureAssigned(entries(["pc", "a", "b", "c", "d", "e"]))
	check(c.getCell("e")["cell"] == 3 and c.getCellmate("e") == "d", "a new inmate gets the first free place, beside the inmate who lives alone")
	var after = m[0].cell_assignments
	for id in ["pc", "a", "b", "c", "d"]:
		check(JSON.print(after[id]) == JSON.print(JSON.parse(before).result[id]), "existing assignment kept for " + id)
	c.removeCharacter("a")
	check(!c.isAssigned("a") and c.getCellmate("pc") == "", "removing a character frees their place")
	c.ensureAssigned(entries(["pc", "b", "c", "d", "e", "f"]))
	check(c.getCell("f")["cell"] == 1 and c.getCellmate("pc") == "f", "a newcomer takes the freed place beside the player")
	check(c.getCell("b")["cell"] == 2 and c.getCell("e")["cell"] == 3, "and nobody else moved")

	# Blocks
	m = make()
	c = m[1]
	c.ensureAssigned([["pc", "red"], ["x", "orange"], ["y", "red"], ["z", "lilac"], ["w", "lilac"]])
	check(c.getCell("pc")["block"] == "red" and c.getCellmate("pc") == "y", "the player's block follows their inmate type")
	check(c.getCell("x")["block"] == "orange" and c.getCell("x")["cell"] == 1 and c.getCell("z")["block"] == "lilac" and c.getCellmate("z") == "w", "other blocks start at cell 1")
	check(c.getOccupiedCellsInBlock("lilac").size() == 1 and c.getOccupiedCells()[0]["block"] == "orange", "blocks are ordered orange, red, lilac")
	c.ensureAssigned([["pc", "orange"], ["x", "orange"]])
	check(c.getCell("pc")["block"] == "orange" and c.getCellmate("pc") == "x", "if the player's inmate type changes only the player is moved")
	check(c.getCell("y")["block"] == "red" and c.getCell("y")["cell"] == 1, "everyone else stays")

	# Invalid input
	m = make()
	c = m[1]
	check(c.assign("", "orange").empty() and c.assign("a", "green").empty() and c.assign(null, "orange").empty(), "invalid assignments ignored")
	check(c.ensureAssigned([["", "orange"], [null, "orange"], ["a", "pink"], "x", ["only"]]) == 0 and m[0].cell_assignments.empty(), "invalid entries ignored")

	# ---- Learned cells ----
	m = make()
	c = m[1]
	c.ensureAssigned(entries(["pc", "a", "b"]))
	check(!c.knowsCell("pc", "a") and c.getKnownTargets("pc").empty(), "nothing known at first")
	check(c.learnCell("pc", "a") and c.knowsCell("pc", "a") and !c.knowsCell("a", "pc"), "learning is directional")
	check(!c.learnCell("pc", "ghost") and !c.learnCell("pc", "pc") and !c.learnCell("", "a") and !c.learnCell("pc", ""), "cannot learn a cell that does not exist")
	c.learnCell("pc", "b")
	c.learnCell("a", "b")
	check(c.getKnownTargets("pc") == ["a", "b"], "known targets sorted")
	c.removeCharacter("b")
	check(c.getKnownTargets("pc") == ["a"] and !c.knowsCell("a", "b") and !m[0].known_cells.has("a"), "removing a character removes what others knew about them")
	c.removeCharacter("pc")
	check(!m[0].known_cells.has("pc"), "and what they knew")
	check(c.getCharacterIDs().has("a") and !c.getCharacterIDs().has("pc"), "ids listed for pruning")

	# ---- Save and load ----
	m = make()
	s = m[0]
	c = m[1]
	c.ensureAssigned([["pc", "orange"], ["a", "orange"], ["b", "red"], ["c", "lilac"]])
	c.learnCell("pc", "a")
	c.learnCell("pc", "c")
	var rel = RelScript.new(s)
	var combat = CombatScript.new(s, rel)
	var inj = InjuriesScript.new(s)
	var _x = rel.setFeeling("a", "pc", "trust", 20)
	combat.addRep("combat", 15)
	inj.applyInjury("pc", "trauma", 2)
	var saved = JSON.parse(JSON.print(s.saveData())).result
	var t = StateScript.new()
	var ct = CellsScript.new(t)
	t.loadData(saved)
	check(t.schema_version == 8, "saved at schema 8")
	check(JSON.print(t.cell_assignments) == JSON.print(s.cell_assignments) and JSON.print(t.known_cells) == JSON.print(s.known_cells), "exact round trip of assignments and known cells")
	check(ct.getCellmate("pc") == "a" and ct.knowsCell("pc", "a") and ct.knowsCell("pc", "c") and !ct.knowsCell("pc", "b"), "and the API reads them")
	var tr = RelScript.new(t)
	var tc = CombatScript.new(t, tr)
	var ti = InjuriesScript.new(t)
	check(tr.getFeeling("a", "pc", "trust") == 20.0 and tc.getCombatReputation() == 15.0 and ti.getSeverity("pc", "trauma") == 2, "relationships, reputation and injuries still survive")
	saved["cell_assignments"]["a"]["cell"] = 99
	saved["known_cells"]["pc"]["b"] = true
	check(ct.getCell("a")["cell"] == 1 and !ct.knowsCell("pc", "b"), "no aliasing with the save input")
	var out = t.saveData()
	out["cell_assignments"]["a"]["cell"] = 77
	out["known_cells"]["pc"].erase("a")
	check(ct.getCell("a")["cell"] == 1 and ct.knowsCell("pc", "a"), "saveData does not alias the state")
	t.clear()
	check(t.cell_assignments.empty() and t.known_cells.empty(), "new game: reset")

	# ---- Migration ----
	t.loadData({"schema_version": 2, "cell_assignments": {"pc": {"block": "orange", "cell": 1}}, "known_cells": {"pc": {"a": true}}, "injuries": {"pc": {"arm": {"severity": 2, "remainingHours": 10}}}, "reputation": {"combat": 9, "defiance": 1}})
	check(t.schema_version == 8 and t.cell_assignments.empty() and t.known_cells.empty() and t.injuries.has("pc") and near(t.reputation["combat"], 9.0), "version 2 loads with no cells (created on first use); injuries and reputation kept")
	t.loadData({"schema_version": 1, "cell_assignments": {"bob": "A1"}})
	check(t.schema_version == 8 and t.cell_assignments.empty(), "version 1 with the old unused cell field loads clean")
	t.loadData({})
	check(t.schema_version == 8 and t.cell_assignments.empty(), "an empty save loads clean")
	t.loadData({"schema_version": 99, "cell_assignments": {"pc": {"block": "red", "cell": 2}}, "known_cells": {"pc": {"a": true}}})
	check(t.schema_version == 99 and t.cell_assignments["pc"]["cell"] == 2 and t.known_cells["pc"]["a"] == true, "a newer schema keeps its data and is not downgraded")

	# ---- Repair and malformed data ----
	t.loadData({"schema_version": 3, "cell_assignments": {
		"pc": {"block": "orange", "cell": 1},
		"z3": {"block": "orange", "cell": 1},
		"a1": {"block": "orange", "cell": 1},
		"m1": {"block": "orange", "cell": 2},
		"m2": {"block": "orange", "cell": 2},
		"": {"block": "orange", "cell": 3},
		"badblock": {"block": "green", "cell": 1},
		"nocell": {"block": "red"},
		"zero": {"block": "red", "cell": 0},
		"huge": {"block": "red", "cell": 10000},
		"text": {"block": "red", "cell": "two"},
		"notdict": "x",
		"float": {"block": "lilac", "cell": 2.0},
		"extra": {"block": "lilac", "cell": 2, "junk": {"a": 1}},
	}})
	check(t.cell_assignments.has("pc") and t.cell_assignments.has("a1") and !t.cell_assignments.has("z3"), "a cell with too many keeps the player and the lowest ids: " + str(t.cell_assignments.keys()))
	check(t.cell_assignments.has("m1") and t.cell_assignments.has("m2") and t.cell_assignments.has("float") and t.cell_assignments.has("extra"), "valid entries kept")
	for id in ["", "badblock", "nocell", "zero", "huge", "text", "notdict"]:
		check(!t.cell_assignments.has(id), "malformed entry dropped: " + id)
	var counts = {}
	for id in t.cell_assignments:
		var key = t.cell_assignments[id]["block"] + str(t.cell_assignments[id]["cell"])
		counts[key] = counts.get(key, 0) + 1
	for key in counts:
		check(counts[key] <= 2, "no cell holds more than two: " + key)
	check(typeof(t.cell_assignments["float"]["cell"]) == TYPE_INT and !t.cell_assignments["extra"].has("junk"), "cell numbers are ints and unknown keys are not carried")
	t.loadData({"schema_version": 3, "cell_assignments": "bad", "known_cells": "bad"})
	check(t.cell_assignments.empty() and t.known_cells.empty(), "non-dictionary data")
	t.loadData({"schema_version": 3, "known_cells": {"pc": {"a": true, "b": false, "c": "yes", "pc": true, "": true}, "": {"a": true}, "x": "bad", "y": {"z": true}}})
	check(t.known_cells.size() == 2 and t.known_cells["pc"].keys() == ["a"] and t.known_cells["y"]["z"] == true, "known cells keep only true, non-self, non-empty entries: " + str(t.known_cells))

	# ---- Tonight's attendance ----
	check(CellsScript.nightId("a", 22 * 3600, 5) == 5 and CellsScript.nightId("a", 3 * 3600, 6) == 5 and CellsScript.nightId("a", 6 * 3600 + 29 * 60, 6) == 5, "night ids: evening of day 5 and early morning of day 6 are night 5")
	m = make()
	s = m[0]
	c = m[1]
	c.ensureAssigned([["pc", "orange"], ["a", "orange"]])
	check(c.getPresence("a", 5) == "" and !c.setPresence("", 5, "home") and !c.setPresence("a", 5, "lost"), "nothing recorded, invalid records refused")
	check(c.setPresence("a", 5, "away") and c.getPresence("a", 5) == "away" and c.getPresence("a", 6) == "", "a record only counts for its own night")
	check(c.setPresence("a", 5, "home") and c.getPresence("a", 5) == "home" and s.cell_presence.size() == 1, "setting again replaces it")
	check(c.getCharacterIDs().has("a"), "presence ids are listed for pruning")
	var savedPresence = JSON.parse(JSON.print(s.saveData())).result
	var tp = StateScript.new()
	tp.loadData(savedPresence)
	check(CellsScript.new(tp).getPresence("a", 5) == "home", "presence survives save and load")
	savedPresence["cell_presence"]["a"]["state"] = "away"
	check(CellsScript.new(tp).getPresence("a", 5) == "home", "no aliasing with the save input")
	c.clearPresence("a")
	check(s.cell_presence.empty(), "clearPresence")
	c.setPresence("a", 5, "home")
	c.removeCharacter("a")
	check(s.cell_presence.empty() and !s.cell_assignments.has("a"), "removing a character removes their attendance too")
	tp.loadData({"schema_version": 3, "cell_assignments": {"pc": {"block": "orange", "cell": 1}}})
	check(tp.cell_presence.empty() and tp.cell_assignments.has("pc"), "a version-3 save without attendance loads with none")
	tp.loadData({"schema_version": 2, "cell_presence": {"a": {"night": 5, "state": "home"}}})
	check(tp.cell_presence.empty() and tp.schema_version == 8, "an older save ignores attendance")
	tp.loadData({"schema_version": 3, "cell_presence": {"a": {"night": 5.0, "state": "home"}, "b": {"night": "x", "state": "home"}, "c": {"night": 5, "state": "lost"}, "": {"night": 5, "state": "home"}, "d": "x", "e": {"state": "away"}}})
	check(tp.cell_presence.keys() == ["a"] and typeof(tp.cell_presence["a"]["night"]) == TYPE_INT, "malformed attendance dropped, numbers become ints: " + str(tp.cell_presence))
	tp.loadData({"schema_version": 3, "cell_presence": "bad"})
	check(tp.cell_presence.empty(), "non-dictionary attendance")
	tp.clear()
	check(tp.cell_presence.empty(), "reset clears attendance")
	
	print("CellsTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.0001
