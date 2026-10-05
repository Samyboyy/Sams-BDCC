extends Node

# Run: godot --path <project dir> res://Modules/SandboxOverhaulModule/Tests/SignedBarLayoutBootTest.tscn
# The reputation bars laid out for real by Godot's containers at several window widths: the value text sits over the middle of the bar, the metric name stays at the left, and
# nothing crowds. Exits with code 1 on failure.

const BarScript = preload("res://Modules/SandboxOverhaulModule/UI/SignedBar.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func centerX(control) -> float:
	return control.rect_global_position.x + control.rect_size.x / 2.0

func _ready():
	get_tree().create_timer(60.0).connect("timeout", get_tree(), "quit", [2])
	var cases = [[-100.0, -100.0], [-50.0, -50.0], [0.0, 0.0], [6.0, 6.0], [50.0, 50.0], [100.0, 100.0]]
	for width in [420, 640, 1024, 1280, 1920]:
		var host = Control.new()
		host.rect_min_size = Vector2(width, 700)
		host.rect_size = Vector2(width, 700)
		var column = VBoxContainer.new()
		column.anchor_right = 1.0
		column.anchor_bottom = 1.0
		host.add_child(column)
		var combat = BarScript.new()
		var defiance = BarScript.new()
		combat.setup("Combat Reputation", 0.0, CombatScript.getCombatBand(0.0), CombatScript.DESCRIPTION_COMBAT, "")
		defiance.setup("Defiance", 0.0, CombatScript.getDefianceBand(0.0), CombatScript.DESCRIPTION_DEFIANCE, "")
		column.add_child(combat)
		column.add_child(defiance)
		add_child(host)
		for entry in cases:
			combat.setValue(entry[0], CombatScript.getCombatBand(entry[0]))
			defiance.setValue(entry[1], CombatScript.getDefianceBand(entry[1]))
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			for bar in [combat, defiance]:
				var offset = abs(centerX(bar.valueLabel) - centerX(bar.barRow))
				check(offset <= 1.5, "width " + str(width) + ", value " + str(entry[0]) + ": the value text is centred over the bar (off by " + str(offset) + "): " + bar.valueLabel.text)
				check(abs(centerX(bar.divider) - centerX(bar.barRow)) <= 1.5, "the centre mark is in the middle of the bar")
				check(bar.titleLabel.rect_global_position.x <= bar.barRow.rect_global_position.x + 1.0 and bar.titleLabel.align == Label.ALIGN_LEFT, "the metric name stays at the left")
				check(bar.valueLabel.rect_global_position.y + bar.valueLabel.rect_size.y <= bar.barRow.rect_global_position.y + 0.5, "the value is above the bar, not on it")
				check(bar.barRow.rect_global_position.y + bar.barRow.rect_size.y + 4.0 <= bar.explanationLabel.rect_global_position.y, "the explanation is clear of the bar")
			check(defiance.titleLabel.rect_global_position.y >= combat.explanationLabel.rect_global_position.y + combat.explanationLabel.rect_size.y + 18.0, "width " + str(width) + ": clear space between the Combat explanation and the Defiance heading: " + str(defiance.titleLabel.rect_global_position.y - (combat.explanationLabel.rect_global_position.y + combat.explanationLabel.rect_size.y)))
			check(defiance.barRow.rect_global_position.y > defiance.titleLabel.rect_global_position.y + defiance.titleLabel.rect_size.y, "the Defiance bar is below its heading")
			check(combat.rect_global_position.y + combat.rect_size.y <= defiance.rect_global_position.y + 0.5, "the two bars do not overlap")
			# fill is unchanged by the layout
			check(abs(combat.rightBar.value - max(0.0, entry[0])) < 0.01 and abs(combat.leftBar.value - max(0.0, -entry[0])) < 0.01, "fill follows the value " + str(entry[0]))
		check(combat.valueLabel.rect_size.x >= BarScript.barWidth() - 0.5 and combat.valueLabel.rect_size.x <= BarScript.barWidth() + 0.5, "the value line is exactly as wide as the bar")
		host.queue_free()
		yield(get_tree(), "idle_frame")
	print("SignedBarLayoutBootTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	get_tree().quit(1 if failures > 0 else 0)
