extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/SignedBarTest.gd --quit
# The -100..+100 reputation bar: fill on each side of the centre, colours, text and bands. Exits with code 1 on failure.

const BarScript = preload("res://Modules/SandboxOverhaulModule/UI/SignedBar.gd")
const CombatScript = preload("res://Modules/SandboxOverhaulModule/Relationships/CombatConsequences.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func near(a: float, b: float) -> bool:
	return abs(a - b) < 0.001

func _init():
	# Pure fill rules
	var cases = [[-100, 100.0, 0.0], [-50, 50.0, 0.0], [-1, 1.0, 0.0], [0, 0.0, 0.0], [6, 0.0, 6.0], [50, 0.0, 50.0], [100, 0.0, 100.0], [-250, 100.0, 0.0], [250, 0.0, 100.0], [-0.4, 0.4, 0.0]]
	for entry in cases:
		var fill = BarScript.fillOf(entry[0])
		check(near(fill["left"], entry[1]) and near(fill["right"], entry[2]), "fill of " + str(entry[0]) + ": left " + str(fill["left"]) + ", right " + str(fill["right"]))
	for bad in [null, "x", [], {}, NAN, INF]:
		var fillBad = BarScript.fillOf(bad)
		check(near(fillBad["left"], 0.0) and near(fillBad["right"], 0.0), "a non-number fills nothing: " + str(bad))
	check(BarScript.signedText(6) == "+6" and BarScript.signedText(-6) == "-6" and BarScript.signedText(0) == "0" and BarScript.signedText(100) == "+100" and BarScript.signedText(-100) == "-100" and BarScript.signedText(250) == "+100" and BarScript.signedText("x") == "0" and BarScript.signedText(5.6) == "+6", "the number is shown with its sign, clamped")

	# The control
	var bar = BarScript.new()
	bar.setup("Combat Reputation", 6.0, CombatScript.getCombatBand(6.0), CombatScript.DESCRIPTION_COMBAT, "")
	check(near(bar.leftBar.value, 0.0) and near(bar.rightBar.value, 6.0), "at +6 only the right half has a sliver of fill (6 of 100)")
	check(bar.leftBar.max_value == 100.0 and bar.rightBar.max_value == 100.0 and bar.leftBar.min_value == 0.0 and !bar.leftBar.percent_visible and !bar.rightBar.percent_visible, "each half is a 0..100 ProgressBar without a percentage")
	check(bar.leftBar.rect_scale.x < 0.0 and bar.rightBar.rect_scale.x > 0.0, "the left half is mirrored so it fills from the centre outwards")
	check(bar.divider.rect_min_size.x > 0.0 and bar.divider.get_parent() == bar.leftBar.get_parent() and bar.leftBar.get_index() < bar.divider.get_index() and bar.divider.get_index() < bar.rightBar.get_index(), "a centre divider sits between the halves")
	check(bar.valueLabel.text == "+6 — Unproven" and bar.titleLabel.text == "Combat Reputation" and bar.explanationLabel.text == CombatScript.DESCRIPTION_COMBAT, "the value, the band and one explanation are shown: " + bar.valueLabel.text)
	check(bar.hint_tooltip != "" and bar.leftBar.hint_tooltip == bar.hint_tooltip, "there is a tooltip")
	var leftColor = bar.leftBar.get_stylebox("fg").bg_color
	var rightColor = bar.rightBar.get_stylebox("fg").bg_color
	check(leftColor.r > 0.8 and leftColor.g < 0.6 and leftColor.b < 0.4, "negative values are red/orange")
	check(rightColor.g > 0.7 and rightColor.r < 0.4, "positive values are green/cyan")
	for pair in [[-100.0, 100.0, 0.0, "-100", "Easy target"], [-45.0, 45.0, 0.0, "-45", "Weak reputation"], [0.0, 0.0, 0.0, "0", "Unproven"], [45.0, 0.0, 45.0, "+45", "Capable fighter"], [100.0, 0.0, 100.0, "+100", "Formidable"]]:
		bar.setValue(pair[0], CombatScript.getCombatBand(pair[0]))
		check(near(bar.leftBar.value, pair[1]) and near(bar.rightBar.value, pair[2]) and bar.valueLabel.text == pair[3] + " — " + pair[4], "value " + str(pair[0]) + " draws left " + str(pair[1]) + ", right " + str(pair[2]) + " and says " + bar.valueLabel.text)
	bar.setValue(0.0, "Unproven")
	check(near(bar.leftBar.value, 0.0) and near(bar.rightBar.value, 0.0), "neutral is empty on both sides, with only the centre mark")
	bar.free()

	# Defiance uses the same control, with its own bands, and its words do not call it good or bad
	var defiance = BarScript.new()
	defiance.setup("Defiance", -70.0, CombatScript.getDefianceBand(-70.0), CombatScript.DESCRIPTION_DEFIANCE, "")
	check(near(defiance.leftBar.value, 70.0) and near(defiance.rightBar.value, 0.0) and defiance.valueLabel.text == "-70 — Highly compliant", "Defiance at -70 fills the left side: " + defiance.valueLabel.text)
	defiance.setValue(80.0, CombatScript.getDefianceBand(80.0))
	check(near(defiance.leftBar.value, 0.0) and near(defiance.rightBar.value, 80.0) and defiance.valueLabel.text == "+80 — Unbreakable", "and +80 fills the right: " + defiance.valueLabel.text)
	for word in ["good", "bad", "virtue", "evil", "should", "must"]:
		check(CombatScript.DESCRIPTION_DEFIANCE.to_lower().find(word) == -1, "the Defiance description does not judge: " + word)
	for value in [-100.0, -61.0, -21.0, 0.0, 21.0, 61.0, 100.0]:
		var bandText = CombatScript.getDefianceBand(value).to_lower()
		check(bandText != "" and bandText.find("good") == -1 and bandText.find("bad") == -1, "band for " + str(value) + " is neutral wording: " + bandText)
	defiance.free()

	print("SignedBarTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)
