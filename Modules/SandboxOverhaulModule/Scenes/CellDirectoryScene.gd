extends SceneBase

# The cell directory of a cell block and the view of one cell. One reusable cell interior serves every cell.
# Opened from the "Cell directory" action in a block's hall, or the "Cell info" action in the player's own cell.

const CellsScript = preload("res://Modules/SandboxOverhaulModule/Cells/Cells.gd")

var block:String = "orange"
var page:int = 0
var viewedCell:int = 1

func _init():
	sceneID = "CellDirectoryScene"

func _initScene(_args = []):
	var location:String = GM.pc.getLocation()
	if(location.begins_with("cellblock_red")):
		block = "red"
	elif(location.begins_with("cellblock_lilac") || location.begins_with("cellblock_pink")):
		block = "lilac"
	else:
		block = "orange"
	if(location.ends_with("_playercell")):
		var mine:Dictionary = GlobalRegistry.getModule("SandboxOverhaulModule").getPlayerCell()
		if(!mine.empty()):
			block = mine["block"]
			viewedCell = mine["cell"]
			state = "cell"

func _run():
	var module = GlobalRegistry.getModule("SandboxOverhaulModule")
	if(state == "cell"):
		saynn(module.getCellViewText(block, viewedCell))
		addButton("Directory", "Back to the list of cells", "directory")
		addButton("Leave", "Done looking", "endthescene")
		return
	
	saynn("[b]" + CellsScript.BLOCK_NAMES[block] + " cellblock - cell directory[/b]")
	saynn(module.getMyCellText())
	var entries:Array = module.getRosterPage(block, page)
	if(entries.empty()):
		saynn("Nobody is assigned to a cell in this block.")
	else:
		for entry in entries:
			sayn(entry["line"])
		sayn("")
	var pageCount:int = module.getRosterPageCount(block)
	if(pageCount > 1):
		saynn("Page " + str(page + 1) + " of " + str(pageCount))
	for entry in entries:
		addButton("Cell " + str(entry["cell"]), "Look into " + CellsScript.cellLabel(entry["block"], entry["cell"]), "viewcell", [entry["cell"]])
	if(page > 0):
		addButton("Previous page", "Earlier cells", "prevpage")
	if(page + 1 < pageCount):
		addButton("Next page", "Later cells", "nextpage")
	addButton("Leave", "Done looking", "endthescene")

func _react(_action: String, _args):
	if(_action == "endthescene"):
		endScene()
		return
	if(_action == "viewcell"):
		viewedCell = int(_args[0])
		setState("cell")
		return
	if(_action == "directory"):
		setState("")
		return
	if(_action == "nextpage"):
		page += 1
		setState("")
		return
	if(_action == "prevpage"):
		page = int(max(0, page - 1))
		setState("")
		return
	setState(_action)

func saveData():
	var data = .saveData()
	data["block"] = block
	data["page"] = page
	data["viewedCell"] = viewedCell
	return data

func loadData(_data):
	.loadData(_data)
	block = SAVE.loadVar(_data, "block", "orange")
	page = SAVE.loadVar(_data, "page", 0)
	viewedCell = SAVE.loadVar(_data, "viewedCell", 1)
