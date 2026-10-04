extends Object
class_name FeelingAxis

# The five directed feeling axes. An axis is identified by its name constant, stored under its short key.

const Affection = "affection"
const Trust = "trust"
const Respect = "respect"
const Fear = "fear"
const Desire = "desire"

const ALL = [Affection, Trust, Respect, Fear, Desire]

const DATA = {
	"affection": {key = "a", minValue = -100.0, maxValue = 100.0, defaultValue = 0.0},
	"trust": {key = "t", minValue = -100.0, maxValue = 100.0, defaultValue = 0.0},
	"respect": {key = "r", minValue = -100.0, maxValue = 100.0, defaultValue = 0.0},
	"fear": {key = "f", minValue = 0.0, maxValue = 100.0, defaultValue = 0.0},
	"desire": {key = "d", minValue = -100.0, maxValue = 100.0, defaultValue = 0.0},
}

static func isValid(axis) -> bool:
	return (axis is String) && DATA.has(axis)

static func getKey(axis) -> String:
	return DATA[axis]["key"] if isValid(axis) else ""

static func getMin(axis) -> float:
	return DATA[axis]["minValue"] if isValid(axis) else 0.0

static func getMax(axis) -> float:
	return DATA[axis]["maxValue"] if isValid(axis) else 0.0

static func getDefault(axis) -> float:
	return DATA[axis]["defaultValue"] if isValid(axis) else 0.0

static func clampValue(axis, value) -> float:
	return clamp(float(value), getMin(axis), getMax(axis))

# Finite int or float. Rejects bool, string, null, NaN and infinity.
static func isNumber(value) -> bool:
	if(typeof(value) != TYPE_INT && typeof(value) != TYPE_REAL):
		return false
	var asFloat:float = float(value)
	return !is_nan(asFloat) && !is_inf(asFloat)
