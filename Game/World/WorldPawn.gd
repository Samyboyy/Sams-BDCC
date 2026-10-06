extends Node2D

var pawn
var id
var loc
var floorid

onready var move_tween = $MoveTween
onready var icon = $Icon
onready var icon_2 = $Icon2
onready var icon_3 = $Icon/Icon3
onready var relationship_label = $RelationshipLabel

func moveToPos(thePos:Vector2):
	move_tween.interpolate_property(self, "position",
			global_position, thePos + Vector2(RNG.randi_range(-16, 16), RNG.randi_range(-16, 16)), 0.5,
			Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	move_tween.start()
	
	#global_position = thePos + Vector2(RNG.randi_range(-16, 16), RNG.randi_range(-16, 16))

func setPawnTexture(theText):
	if(theText == RoomStuff.PawnTexture.Fem):
		icon.texture = preload("res://Images/WorldPawns/fem.png")
	elif(theText == RoomStuff.PawnTexture.Masc):
		icon.texture = preload("res://Images/WorldPawns/masc.png")
	else:
		icon.texture = null

func setPawnActivityIcon(theIcon):
	if(theIcon == RoomStuff.PawnActivity.Chat):
		icon_2.texture = preload("res://Images/WorldPawnActivity/chat.png")
	elif(theIcon == RoomStuff.PawnActivity.Fight):
		icon_2.texture = preload("res://Images/WorldPawnActivity/fight.png")
	elif(theIcon == RoomStuff.PawnActivity.Sex):
		icon_2.texture = preload("res://Images/WorldPawnActivity/sex.png")
	elif(theIcon == RoomStuff.PawnActivity.Eat):
		icon_2.texture = preload("res://Images/WorldPawnActivity/eating.png")
	elif(theIcon == RoomStuff.PawnActivity.Shower):
		icon_2.texture = preload("res://Images/WorldPawnActivity/showering.png")
	elif(theIcon == RoomStuff.PawnActivity.Stocks):
		icon_2.texture = preload("res://Images/WorldPawnActivity/stocks.png")
	elif(theIcon == RoomStuff.PawnActivity.Unconscious):
		icon_2.texture = preload("res://Images/WorldPawnActivity/unconscious.png")
	elif(theIcon == RoomStuff.PawnActivity.Work):
		icon_2.texture = preload("res://Images/WorldPawnActivity/working.png")
	elif(theIcon == RoomStuff.PawnActivity.Help):
		icon_2.texture = preload("res://Images/WorldPawnActivity/help.png")
	elif(theIcon == RoomStuff.PawnActivity.Down):
		icon_2.texture = preload("res://Images/WorldPawnActivity/down.png")
	elif(theIcon == RoomStuff.PawnActivity.Prostitution):
		icon_2.texture = preload("res://Images/WorldPawnActivity/prostitution.png")
	elif(theIcon == RoomStuff.PawnActivity.Struggle):
		icon_2.texture = preload("res://Images/WorldPawnActivity/struggle.png")
	elif(theIcon == RoomStuff.PawnActivity.GiveBirth):
		icon_2.texture = preload("res://Images/WorldPawnActivity/givebirth.png")
	elif(theIcon == RoomStuff.PawnActivity.LayEggs):
		icon_2.texture = preload("res://Images/WorldPawnActivity/layeggs.png")
	else:
		icon_2.texture = null

func setPawnColor(theColor:Color):
	icon.self_modulate = theColor

func setShowCollar(isShow:bool):
	icon_3.visible = isShow

# Sandbox overhaul: the gang badge ("G" in the colour of how that gang stands with the player), drawn beside the relationship tag. Created on first use, hidden when empty.
var gangLabel:Label = null

func setGangBadge(_text:String, _color:Color = Color.white, _tooltip:String = "", _afterTag:bool = false):
	if(_text.empty() && gangLabel == null):
		return
	if(gangLabel == null):
		gangLabel = Label.new()
		gangLabel.mouse_filter = Control.MOUSE_FILTER_PASS
		gangLabel.add_font_override("font", relationship_label.get_font("font"))
		add_child(gangLabel)
	gangLabel.visible = !_text.empty()
	gangLabel.text = _text
	gangLabel.hint_tooltip = _tooltip
	gangLabel.rect_position = relationship_label.rect_position + Vector2(12.0 if _afterTag else 0.0, 0.0)
	gangLabel.add_color_override("font_color", _color)

# Sandbox overhaul: a third badge, "S" (purple), for somebody the player owns. It sits after the relationship tag and the gang badge ("F S", "G S", "N G S"): slots is how many badges come before it.
var slaveLabel:Label = null

func setSlaveBadge(_text:String, _color:Color = Color.white, _tooltip:String = "", _slots:int = 0):
	if(_text.empty() && slaveLabel == null):
		return
	if(slaveLabel == null):
		slaveLabel = Label.new()
		slaveLabel.mouse_filter = Control.MOUSE_FILTER_PASS
		slaveLabel.add_font_override("font", relationship_label.get_font("font"))
		add_child(slaveLabel)
	slaveLabel.visible = !_text.empty()
	slaveLabel.text = _text
	slaveLabel.hint_tooltip = _tooltip
	slaveLabel.rect_position = relationship_label.rect_position + Vector2(12.0 * _slots, 0.0)
	slaveLabel.add_color_override("font_color", _color)

# Sandbox overhaul: a fourth badge, a yellow "Q", for the person a tracked task points at, after the other badges (slots: how many of them are showing).
var taskLabel:Label = null

func setTaskBadge(_text:String, _color:Color = Color.white, _tooltip:String = "", _slots:int = 0):
	if(_text.empty() && taskLabel == null):
		return
	if(taskLabel == null):
		taskLabel = Label.new()
		taskLabel.mouse_filter = Control.MOUSE_FILTER_PASS
		taskLabel.add_font_override("font", relationship_label.get_font("font"))
		add_child(taskLabel)
	taskLabel.visible = !_text.empty()
	taskLabel.text = _text
	taskLabel.hint_tooltip = _tooltip
	taskLabel.rect_position = relationship_label.rect_position + Vector2(12.0 * _slots, 0.0)
	taskLabel.add_color_override("font_color", _color)

func setRelationshipText(_text:String, _color:Color = Color.white):
	if(_text.empty()):
		relationship_label.visible = false
		relationship_label.text = _text
		return
	relationship_label.visible = true
	relationship_label.text = _text
	relationship_label["custom_colors/font_color"] = _color
