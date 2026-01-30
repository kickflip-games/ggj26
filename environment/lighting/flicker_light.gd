extends Light3D

@export var enabled: bool = true

@export var base_energy: float = -1.0
@export var flicker_strength: float = 0.08
@export var flicker_speed_hz: float = 10.0
@export var noise_strength: float = 0.04

@export var dip_chance_per_second: float = 0.12
@export var dip_duration_seconds: float = 0.06
@export var dip_multiplier: float = 0.45

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0
var _base: float = 1.0
var _dip_time_left: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_base = base_energy if base_energy > 0.0 else light_energy


func _process(delta: float) -> void:
	if !enabled:
		return

	_time += delta

	if _dip_time_left > 0.0:
		_dip_time_left = maxf(0.0, _dip_time_left - delta)
	elif dip_chance_per_second > 0.0 and _rng.randf() < dip_chance_per_second * delta:
		_dip_time_left = dip_duration_seconds

	var flicker: float = 1.0 + sin(_time * TAU * flicker_speed_hz) * flicker_strength
	flicker += _rng.randf_range(-1.0, 1.0) * noise_strength

	var dip: float = dip_multiplier if _dip_time_left > 0.0 else 1.0
	light_energy = maxf(0.0, _base * flicker * dip)

