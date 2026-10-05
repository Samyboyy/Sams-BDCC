extends VBoxContainer

# A -100..+100 bar with zero in the middle. Negative values fill leftwards from the centre in red/orange, positive values fill rightwards in green/cyan, zero is empty with
# only the centre mark. Built from two of BDCC's own ProgressBars (the theme's bar styling, only the fill colour is changed), one flipped so it fills right to left, and
# a divider between them.
#
# Layout, top to bottom: the name of the metric on the left; the value and band ("+6  Unproven") centred exactly above the middle of the bar; the bar; one sentence below it; then
# clear space before the next bar. The value line and the bar are both fixed to the bar's own width and centred in the same way, so the text always sits over the centre mark
# whatever the width of the screen.

const NEGATIVE_COLOR = Color(0.95, 0.45, 0.22)
const POSITIVE_COLOR = Color(0.25, 0.85, 0.72)
const DIVIDER_COLOR = Color(1, 1, 1, 0.85)
const SCALE = 100.0
const BAR_WIDTH = 150.0
const BAR_HEIGHT = 16.0
const DIVIDER_WIDTH = 2.0
const GAP = 8 # between the parts of one bar
const SPACE_AFTER = 22.0 # before whatever comes next

var leftBar:ProgressBar
var rightBar:ProgressBar
var divider:ColorRect
var titleLabel:Label
var valueLabel:Label
var explanationLabel:Label
var barBlock:VBoxContainer
var barRow:HBoxContainer
var spacer:Control
var currentValue:float = 0.0

# The fill of each half for a value: {"left": 0..100, "right": 0..100}. Out-of-range values are clamped; anything that is not a number counts as zero.
static func fillOf(value) -> Dictionary:
	var number:float = float(value) if (typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) && !is_nan(float(value)) && !is_inf(float(value)) else 0.0
	number = clamp(number, -SCALE, SCALE)
	return {"left": max(0.0, -number), "right": max(0.0, number)}

static func signedText(value) -> String:
	var whole:int = int(round(float(clamp(float(value), -SCALE, SCALE)))) if (typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) else 0
	return ("+" if whole > 0 else "") + str(whole)

# The width of the bar itself, both halves and the divider.
static func barWidth() -> float:
	return BAR_WIDTH * 2.0 + DIVIDER_WIDTH

func _init():
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_constant_override("separation", GAP)
	titleLabel = Label.new()
	titleLabel.align = Label.ALIGN_LEFT
	add_child(titleLabel)
	barBlock = VBoxContainer.new()
	barBlock.size_flags_horizontal = SIZE_SHRINK_CENTER
	barBlock.add_constant_override("separation", 4)
	add_child(barBlock)
	valueLabel = Label.new()
	valueLabel.align = Label.ALIGN_CENTER
	valueLabel.rect_min_size = Vector2(barWidth(), 0.0)
	valueLabel.size_flags_horizontal = SIZE_SHRINK_CENTER
	barBlock.add_child(valueLabel)
	barRow = HBoxContainer.new()
	barRow.size_flags_horizontal = SIZE_SHRINK_CENTER
	barRow.add_constant_override("separation", 0)
	leftBar = makeBar(NEGATIVE_COLOR)
	rightBar = makeBar(POSITIVE_COLOR)
	divider = ColorRect.new()
	divider.color = DIVIDER_COLOR
	divider.rect_min_size = Vector2(DIVIDER_WIDTH, BAR_HEIGHT + 6.0)
	barRow.add_child(leftBar)
	barRow.add_child(divider)
	barRow.add_child(rightBar)
	barBlock.add_child(barRow)
	explanationLabel = Label.new()
	explanationLabel.autowrap = true
	explanationLabel.modulate = Color(1, 1, 1, 0.75)
	explanationLabel.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(explanationLabel)
	spacer = Control.new()
	spacer.rect_min_size = Vector2(0.0, SPACE_AFTER)
	add_child(spacer)
	var _err:int = leftBar.connect("resized", self, "_flipLeft")

func makeBar(color:Color) -> ProgressBar:
	var bar:ProgressBar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = SCALE
	bar.step = 0.01
	bar.value = 0.0
	bar.percent_visible = false
	bar.rect_min_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	var fill:StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_stylebox_override("fg", fill)
	return bar

# The left bar is the same ProgressBar mirrored, so it fills from the centre outwards.
func _flipLeft():
	leftBar.rect_pivot_offset = Vector2(leftBar.rect_size.x / 2.0, leftBar.rect_size.y / 2.0)

# title, value (-100..100), band text, one sentence, tooltip.
func setup(title:String, value, band:String, explanation:String, tooltip:String = "") -> void:
	titleLabel.text = title
	explanationLabel.text = explanation
	hint_tooltip = tooltip
	setValue(value, band)
	leftBar.rect_scale = Vector2(-1.0, 1.0)
	_flipLeft()

func setValue(value, band:String) -> void:
	var fill:Dictionary = fillOf(value)
	leftBar.value = fill["left"]
	rightBar.value = fill["right"]
	currentValue = float(clamp(float(value), -SCALE, SCALE)) if (typeof(value) == TYPE_INT || typeof(value) == TYPE_REAL) else 0.0
	valueLabel.text = signedText(value) + " — " + band
	hint_tooltip = hint_tooltip if hint_tooltip != "" else signedText(value) + " on a scale from -100 to +100. " + band + "."
	leftBar.hint_tooltip = hint_tooltip
	rightBar.hint_tooltip = hint_tooltip
