extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/CellLayoutTest.gd --quit
# Exits with code 1 on failure.

const LayoutScript = preload("res://Modules/SandboxOverhaulModule/Prison/CellLayout.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

# Every position a block's cells use, as "x,y" keys, plus the vanilla rooms that are in the way.
const VANILLA_FLOOR = [Vector2(0, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 2), Vector2(-1, 2), Vector2(1, 2), Vector2(0, 3), Vector2(8, 2)]

func same(a, b) -> bool:
	return JSON.print(a, "", true) == JSON.print(b, "", true)

func _init():
	# ---- Capacity: ceil(population / 2), at least eight ----
	for pair in [[0, 8], [1, 8], [8, 8], [16, 8], [17, 9], [20, 10], [25, 13], [30, 15], [31, 16], [100, 50]]:
		check(LayoutScript.requiredCapacity(pair[0]) == pair[1], "capacity for " + str(pair[0]) + " inmates is " + str(pair[1]) + ", got " + str(LayoutScript.requiredCapacity(pair[0])))
	check(LayoutScript.requiredCapacity(-4) == 8, "a negative population still gets the base")

	# ---- Distribution among the blocks ----
	var d25 = LayoutScript.distribute({"orange": 11, "red": 8, "lilac": 6})
	check(same(d25, {"orange": 6, "red": 4, "lilac": 3}) and LayoutScript.totalCells(d25) == 13, "25 inmates (11/8/6): 6 + 4 + 3 = 13 cells: " + str(d25))
	var d8 = LayoutScript.distribute({"orange": 8, "red": 0, "lilac": 0})
	check(LayoutScript.totalCells(d8) == 8 and d8["orange"] >= 4 and d8["red"] >= 1 and d8["lilac"] >= 1, "8 inmates: base of eight, every block keeps its vanilla cell: " + str(d8))
	var d16 = LayoutScript.distribute({"orange": 8, "red": 4, "lilac": 4})
	check(LayoutScript.totalCells(d16) == 8 and same(d16, {"orange": 4, "red": 2, "lilac": 2}), "16 inmates: 4 + 2 + 2: " + str(d16))
	var d20 = LayoutScript.distribute({"orange": 10, "red": 5, "lilac": 5})
	check(LayoutScript.totalCells(d20) >= 10 and d20["orange"] >= 5 and d20["red"] >= 3 and d20["lilac"] >= 3, "20 inmates: at least 10 cells, each block big enough (blocks round up): " + str(d20))
	var d30 = LayoutScript.distribute({"orange": 15, "red": 8, "lilac": 7})
	check(LayoutScript.totalCells(d30) >= 15 and d30["orange"] >= 8 and d30["red"] >= 4 and d30["lilac"] >= 4, "30 inmates: at least 15 cells, each block big enough: " + str(d30))
	# Types do not have to split evenly: a lopsided prison gets a lopsided layout, never fewer cells than a block needs.
	var skew = LayoutScript.distribute({"orange": 3, "red": 21, "lilac": 1})
	check(skew["red"] >= 11 and LayoutScript.totalCells(skew) >= 13, "a red-heavy prison has a big red block: " + str(skew))
	# A block never shrinks below the highest cell somebody is assigned to.
	var kept = LayoutScript.distribute({"orange": 2, "red": 2, "lilac": 2}, {"orange": 9, "red": 1, "lilac": 1})
	check(kept["orange"] >= 9, "an assigned cell is never removed: " + str(kept))
	check(same(LayoutScript.distribute({"orange": 11, "red": 8, "lilac": 6}), d25), "distribution is deterministic")
	# Every block always has two seats per cell or more.
	for counts in [{"orange": 11, "red": 8, "lilac": 6}, {"orange": 15, "red": 8, "lilac": 7}, {"orange": 1, "red": 1, "lilac": 1}, {"orange": 40, "red": 0, "lilac": 0}]:
		var dist = LayoutScript.distribute(counts)
		for block in LayoutScript.BLOCKS:
			check(dist[block] * LayoutScript.PER_CELL >= counts[block], "enough seats in " + block + " for " + str(counts[block]) + ": " + str(dist[block]))

	# ---- IDs ----
	check(LayoutScript.roomID("orange", 1) == "cellblock_orange_playercell" and LayoutScript.roomID("red", 1) == "cellblock_red_playercell" and LayoutScript.roomID("lilac", 1) == "cellblock_pink_playercell", "cell 1 is the vanilla room of each block")
	check(LayoutScript.roomID("orange", 3) == "sbx_cell_orange_3" and LayoutScript.roomID("lilac", 12) == "sbx_cell_lilac_12", "later cells have stable IDs")
	check(LayoutScript.roomID("green", 2) == "" and LayoutScript.roomID("orange", 0) == "" and LayoutScript.roomID(null, 2) == "", "invalid blocks and numbers have no room")
	check(same(LayoutScript.parse("sbx_cell_red_7"), {"block": "red", "cell": 7}) and same(LayoutScript.parse("cellblock_pink_playercell"), {"block": "lilac", "cell": 1}), "IDs parse back")
	for bad in ["sbx_cell_red_1", "sbx_cell_red_07", "sbx_cell_red_x", "sbx_cell_purple_3", "sbx_cell_red", "sbx_cell_red_3_4", "hall_canteen", "", null, 4]:
		check(LayoutScript.parse(bad).empty(), "not a cell room: " + str(bad))
	check(LayoutScript.label("lilac", 3) == "Lilac Cell 3" and LayoutScript.zoneOf("red", 2) == "sbxcell_red_2", "labels and zones")
	check(LayoutScript.joinNames([]) == "" and LayoutScript.joinNames(["Alec"]) == "Alec" and LayoutScript.joinNames(["Alec", "Jeffery"]) == "Alec and Jeffery" and LayoutScript.joinNames(["A", "B", "C"]) == "A, B and C", "resident names read naturally")

	# ---- Layout: compact, no collisions, everything connected ----
	var dirs = [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)]
	for total in [8, 13, 20, 30, 60]:
		# A prison with this many cells in all, split the usual way
		var perBlock = LayoutScript.distribute({"orange": total, "red": int(total * 0.7), "lilac": int(total * 0.5)})
		var occupied = {}
		for v in LayoutScript.VANILLA_FLOOR:
			occupied[v] = "vanilla"
		for block in LayoutScript.BLOCKS:
			var count = perBlock[block]
			check(count >= 1, block + " has a cell")
			var cells = LayoutScript.buildBlock(block, count)
			check(cells.size() == count - 1, block + ": cells 2.." + str(count))
			var mine = {LayoutScript.ORIGINS[block]: true}
			var minX = LayoutScript.ORIGINS[block].x
			var maxX = minX
			var minY = LayoutScript.ORIGINS[block].y
			var maxY = minY
			for entry in cells:
				var pos = Vector2(entry["x"], entry["y"])
				check(!occupied.has(pos) or (occupied[pos] == "vanilla" and false), block + " cell " + str(entry["cell"]) + " at " + str(pos) + " is free (" + str(occupied.get(pos, "")) + ")")
				check(LayoutScript.inRegion(block, pos), block + " cell " + str(entry["cell"]) + " stays in the block's part of the map")
				occupied[pos] = block + " " + str(entry["cell"])
				mine[pos] = true
				minX = min(minX, pos.x)
				maxX = max(maxX, pos.x)
				minY = min(minY, pos.y)
				maxY = max(maxY, pos.y)
			# compact: the blob's bounding box is not much bigger than the cells in it
			var area = (maxX - minX + 1) * (maxY - minY + 1)
			check(area <= (count + 1) * 2.2 + 4, block + " with " + str(count) + " cells is compact (bounding box " + str(area) + ")")
			# neither one endless line: short straight runs
			var longest = 0
			for axisDir in [Vector2(1, 0), Vector2(0, 1)]:
				for point in mine:
					if(mine.has(point - axisDir)):
						continue
					var run = 0
					var cursor = point
					while(mine.has(cursor)):
						run += 1
						cursor += axisDir
					longest = int(max(longest, run))
			check(longest <= (4 if count <= 13 else 7), block + " with " + str(count) + " cells has no straight run longer than " + str(longest))
			if(count >= 6):
				check(maxX - minX >= 2 and maxY - minY >= 1, block + " extends both across and up/down: " + str(maxX - minX + 1) + " x " + str(maxY - minY + 1))
			# connectivity from cell 1 and the hall by the opening flags, both sides agreeing
			var reachable = {1: true}
			var queue = [1]
			while(!queue.empty()):
				var current = queue.pop_front()
				var currentOpen = LayoutScript.openings(block, current, count)
				for index in range(4):
					if(current == 1):
						continue
					if(!currentOpen[index]):
						continue
					var there = LayoutScript.position(block, current) + dirs[index]
					if(there == LayoutScript.HALL_POS[block]):
						continue
					for other in range(1, count + 1):
						if(LayoutScript.position(block, other) == there and !reachable.has(other)):
							if(other != 1):
								check(LayoutScript.openings(block, other, count)[(index + 2) % 4], block + ": " + str(current) + " and " + str(other) + " open on both sides")
							reachable[other] = true
							queue.append(other)
				if(current == 1):
					# cell 1 is a vanilla room with every side open: its neighbours inside the block connect to it
					for other in range(2, count + 1):
						var delta = LayoutScript.position(block, other) - LayoutScript.ORIGINS[block]
						if(abs(delta.x) + abs(delta.y) == 1.0 and !reachable.has(other)):
							reachable[other] = true
							queue.append(other)
			# cells that touch the hall connect to it directly
			var touchingHall = 0
			for other in range(2, count + 1):
				var delta2 = LayoutScript.position(block, other) - LayoutScript.HALL_POS[block]
				if(abs(delta2.x) + abs(delta2.y) == 1.0):
					touchingHall += 1
					var openToHall = LayoutScript.openings(block, other, count)
					var towards = [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)].find(-delta2)
					check(openToHall[towards], block + " cell " + str(other) + " opens onto the hall")
					reachable[other] = true
			check(reachable.size() == count, block + " with " + str(count) + " cells is fully connected: " + str(reachable.size()))
			if(count >= 4 and block != "lilac"):
				check(touchingHall >= 1, block + ": at least one new cell opens straight onto the hall (no buffer in front of the cells)")
	# the order never depends on how many cells there are
	check(LayoutScript.buildBlock("orange", 5)[3]["x"] == LayoutScript.buildBlock("orange", 12)[3]["x"] and LayoutScript.buildBlock("orange", 5)[3]["y"] == LayoutScript.buildBlock("orange", 12)[3]["y"], "cell 5 is always in the same place")
	check(LayoutScript.position("red", 1) == Vector2(2, 2) and LayoutScript.position("lilac", 1) == Vector2(0, 4) and LayoutScript.position("orange", 1) == Vector2(-2, 2), "cell 1 is the vanilla room's own place")
	# blocks never share a position
	var seen = {}
	for block in LayoutScript.BLOCKS:
		for cell in range(1, 61):
			var pos2 = LayoutScript.position(block, cell)
			check(!seen.has(pos2), "no two cells share " + str(pos2))
			seen[pos2] = true
			check(!(cell > 1 and LayoutScript.VANILLA_FLOOR.has(pos2)), "no cell sits on a vanilla room: " + str(pos2))
	# the first cells of each block hug the hall and cell 1
	for block in LayoutScript.BLOCKS:
		var first = LayoutScript.position(block, 2)
		check((first - LayoutScript.ORIGINS[block]).abs().x + (first - LayoutScript.ORIGINS[block]).abs().y == 1.0 or (first - LayoutScript.HALL_POS[block]).abs().x + (first - LayoutScript.HALL_POS[block]).abs().y == 1.0, block + " cell 2 is right next to the hall or cell 1")
	var originalSixCheck = 0
	for block in LayoutScript.BLOCKS:
		if(LayoutScript.roomID(block, 1) == LayoutScript.FIRST_CELL_ROOMS[block] and LayoutScript.parse(LayoutScript.HALL_ROOMS[block]).empty()):
			originalSixCheck += 1
	check(originalSixCheck == 3, "the three player cells are cell 1 of their block and the three halls are halls, not cells")

	# ---- Rooms added one at a time to a map that already exists stay connected (a door must not depend on how many cells there were when its room was built) ----
	var mapDirs = [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)]
	for count in range(1, 61):
		var grid = {}
		for point in LayoutScript.VANILLA_FLOOR:
			grid[point] = {"open": [true, true, true, true], "id": "vanilla" + str(point)}
		var builtAt = {}
		for block in LayoutScript.BLOCKS:
			var perBlock = int(min(60, count + (3 if block == "red" else 0)))
			for entry in LayoutScript.buildBlock(block, perBlock):
				var spot = Vector2(entry["x"], entry["y"])
				check(!grid.has(spot), block + " cell " + str(entry["cell"]) + " never lands on another room: " + str(spot))
				grid[spot] = {"open": entry["open"], "id": entry["id"]}
				builtAt[spot] = true
		var seenFrom = {Vector2(0, 2): true}
		var frontier = [Vector2(0, 2)]
		while(!frontier.empty()):
			var at = frontier.pop_front()
			for index in range(4):
				var next = at + mapDirs[index]
				if(grid.has(next) and grid[at]["open"][index] and grid[next]["open"][(index + 2) % 4] and !seenFrom.has(next)):
					seenFrom[next] = true
					frontier.append(next)
		for spot in builtAt:
			check(seenFrom.has(spot), "with " + str(count) + " cells per block, " + grid[spot]["id"] + " has a real route from the cellblock entrance")
		for block in LayoutScript.BLOCKS:
			var hallSeen = seenFrom.has(LayoutScript.HALL_POS[block]) and seenFrom.has(LayoutScript.ORIGINS[block])
			check(hallSeen, block + " hall and cell 1 are connected")

	print("CellLayoutTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)
