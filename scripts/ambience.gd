## The night's sound (tools/make_ambience.py makes it).
##
## Beds loop under everything and are mixed by where the Lamplighter is:
## rain in the open, the same rain muffled under a roof, the wind in gusts
## that swell and die away, the canal when it's near, and the drone, which
## rises with the dread (no lit lamp nearby, under the ground, hurt, and
## after an omen). Far-off sounds come at random: howls, a bell tolling,
## creaks in the wind, whispers when it's dark enough. Lightning is decided
## here too: `lightning` tells the stage to flash, and the thunder follows
## after the light, later the further off it struck. Now and then the flash
## shows something in the fog, and then it calls.
##
## This is presentation: it runs on the frame clock, never touches the
## game, and keeps its own random numbers.
extends Node

## strength 0..1 (1 is overhead); reveal: the flash shows the thing in the
## fog (scripts/stage.gd draws it).
signal lightning(strength: float, reveal: bool)
## A thunderclap is heard now: 1 overhead, less further off (the stage
## shakes the view for the near ones).
signal thundered(strength: float)

const DIR := "res://assets/ambience/"

## Beds: name -> level in dB at full presence.
const BEDS := {"rain_out": -15.0, "rain_in": -12.0, "wind": -12.0, "water": -12.0, "drone": -13.0}

## Far-off sounds. every: seconds between them (random in the range);
## first: before the first one; db: level; inside_db: added under a roof;
## pitch: random pitch range. A sound listed twice comes twice as often.
const EVENTS := {
	"howl": {"sounds": ["howl_a", "howl_b", "howl_a", "howl_b", "howl_c"], "every": [30.0, 75.0], "first": [12.0, 20.0], "db": -18.0, "inside_db": -8.0, "pitch": [0.9, 1.06]},
	"bell": {"sounds": ["bell"], "every": [80.0, 160.0], "first": [35.0, 55.0], "db": -14.0, "inside_db": -6.0, "pitch": [0.97, 1.0]},
	"creak": {"sounds": ["creak_a", "creak_b"], "every": [10.0, 26.0], "first": [5.0, 12.0], "db": -17.0, "inside_db": -60.0, "pitch": [0.85, 1.15]},
	"whisper": {"sounds": ["whisper_a", "whisper_b", "whisper_c"], "every": [35.0, 80.0], "first": [40.0, 70.0], "db": -15.0, "inside_db": 0.0, "pitch": [0.9, 1.05]},
	"storm": {"sounds": [], "every": [22.0, 55.0], "first": [12.0, 25.0], "db": 0.0, "inside_db": 0.0, "pitch": [1.0, 1.0]},
}
## A bell tolls 1 to 3 times, this many seconds apart.
const TOLL_GAP := 3.8
## Whispers only come when the dread is at least this.
const WHISPER_DREAD := 0.45
## Creaks only come in a gust at least this strong.
const CREAK_GUST := 0.55
## Thunder: strength above NEAR is overhead, above MID nearby; the delay
## after the flash (seconds) for each.
const NEAR := 0.75
const MID := 0.4
const THUNDER_DELAY := {"thunder_near": [0.1, 0.4], "thunder_mid": [0.8, 1.8], "thunder_far": [2.2, 4.5]}
const THUNDER_DB := {"thunder_near": -4.0, "thunder_mid": -7.0, "thunder_far": -11.0}
## A strong flash shows the thing in the fog this often, but not again for
## REVEAL_REST seconds; its call follows CALL_DELAY seconds after.
const REVEAL_CHANCE := 0.4
const REVEAL_REST := 90.0
const CALL_DELAY := 2.2
const CALL_DB := -8.0
## After a reveal the dread is raised by this, fading over OMEN_FADE s.
const OMEN := 0.6
const OMEN_FADE := 25.0
## Seconds to cross between outdoors and under a roof.
const ROOF_FADE := 1.2
## Gusts: a new target strength every GUST_EVERY seconds, reached over
## GUST_RAMP seconds; the wind never drops below GUST_MIN.
const GUST_EVERY := [5.0, 16.0]
const GUST_RAMP := [2.5, 8.0]
const GUST_MIN := 0.2
## The canal is heard from this many tiles away.
const WATER_RANGE := 9
## A lit lamp within this many px keeps the dread down.
const LAMP_CALM := 320.0
const VOICES := 6

var world
## False stops the frame clock (the playtest steps by hand).
var auto := true
## Every far-off sound played, by name, in order (for the playtest).
var heard: Array[String] = []
## How things stand now, 0..1.
var inside := 0.0
var gust := 0.5
var dread := 0.3
var near_water := 0.0

var _rng := RandomNumberGenerator.new()
var _beds := {}
var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _timers := {}
var _queue: Array = []
var _clock := 0.0
var _gust_target := 0.5
var _gust_rate := 0.1
var _gust_t := 0.0
var _omen := 0.0
var _last_reveal := -1000.0
var _water_cell := Vector2i(-9999, -9999)
var _water_target := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for bed in BEDS:
		var stream: AudioStream = load(DIR + bed + ".ogg")
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = -80.0
		add_child(p)
		_beds[bed] = p
	for i in VOICES:
		var v := AudioStreamPlayer.new()
		add_child(v)
		_voices.append(v)
	reset_timers()
	_mix(1.0)
	for bed in _beds:
		(_beds[bed] as AudioStreamPlayer).play(_rng.randf() * 10.0)


## Same random numbers every run (the playtest).
func reseed(value: int) -> void:
	_rng.seed = value
	reset_timers()


func reset_timers() -> void:
	for name in EVENTS:
		var first: Array = EVENTS[name]["first"]
		_timers[name] = _rng.randf_range(first[0], first[1])


func _process(delta: float) -> void:
	if auto:
		step(delta)


## Advances the night by dt seconds.
func step(dt: float) -> void:
	_clock += dt
	_listen(dt)
	_wind(dt)
	_mix(dt)
	for name in _timers:
		_timers[name] -= dt
		if _timers[name] <= 0.0:
			_fire(name)
	var due := _queue.filter(func(q): return q[0] <= _clock)
	for q in due:
		_queue.erase(q)
		_play(q[1], q[2], q[3])


## Where the Lamplighter is: under a roof, near water, near a lit lamp.
func _listen(dt: float) -> void:
	var p = world.player if world else null
	var playing: bool = world != null and world.running and p != null
	var roofed := 0.0
	var calm := false
	var hurt := 0.0
	if playing:
		roofed = 1.0 if world.level.roofed_at(p.position + Vector2(0, -24)) else 0.0
		for l in world.lamps:
			if l.lit and l.position.distance_to(p.position) < LAMP_CALM:
				calm = true
		hurt = 1.0 - clampf(p.hp / p.max_hp, 0.0, 1.0)
		var cell: Vector2i = world.level.cell_at(p.position)
		if cell != _water_cell:
			_water_cell = cell
			_water_target = _water_near(cell)
	else:
		_water_target = 0.0
	inside = move_toward(inside, roofed, dt / ROOF_FADE)
	near_water = move_toward(near_water, _water_target, dt)
	_omen = maxf(0.0, _omen - dt / OMEN_FADE * OMEN)
	var want := 0.25
	if playing:
		want = (0.15 if calm else 0.55) + inside * 0.25 + hurt * 0.25
	dread = move_toward(dread, clampf(want + _omen, 0.0, 1.0), dt / 4.0)


## 1 right by the canal, falling to 0 at WATER_RANGE tiles.
func _water_near(cell: Vector2i) -> float:
	var best := WATER_RANGE + 1
	for dy in range(-4, 6):
		for dx in range(-WATER_RANGE, WATER_RANGE + 1):
			if absi(dx) < best and world.level.kind_at(cell + Vector2i(dx, dy)) == "water":
				best = absi(dx)
	return clampf(1.0 - float(best) / WATER_RANGE, 0.0, 1.0)


func _wind(dt: float) -> void:
	_gust_t -= dt
	if _gust_t <= 0.0:
		_gust_t = _rng.randf_range(GUST_EVERY[0], GUST_EVERY[1])
		_gust_target = lerpf(GUST_MIN, 1.0, pow(_rng.randf(), 0.7))
		_gust_rate = absf(_gust_target - gust) / _rng.randf_range(GUST_RAMP[0], GUST_RAMP[1])
	gust = move_toward(gust, _gust_target, _gust_rate * dt)


## Bed levels, as linear presence 0..1 -> dB.
func presence() -> Dictionary:
	return {
		"rain_out": 1.0 - inside,
		"rain_in": inside,
		"wind": gust * lerpf(1.0, 0.18, inside),
		"water": near_water * lerpf(1.0, 0.45, inside),
		"drone": lerpf(0.3, 1.0, dread),
	}


func _mix(_dt: float) -> void:
	var now := presence()
	for bed in _beds:
		var g: float = now[bed]
		(_beds[bed] as AudioStreamPlayer).volume_db = BEDS[bed] + linear_to_db(maxf(g, 0.0005))


func _fire(name: String) -> void:
	var e: Dictionary = EVENTS[name]
	var every: Array = e["every"]
	_timers[name] = _rng.randf_range(every[0], every[1])
	match name:
		"whisper":
			if dread < WHISPER_DREAD:
				_timers[name] = _rng.randf_range(6.0, 12.0)
				return
		"creak":
			if gust < CREAK_GUST or inside > 0.5:
				_timers[name] = _rng.randf_range(3.0, 6.0)
				return
		"storm":
			strike(pow(_rng.randf(), 0.8))
			return
	var sounds: Array = e["sounds"]
	var sound: String = sounds[_rng.randi() % sounds.size()]
	var pitch: Array = e["pitch"]
	var db: float = e["db"] + float(e["inside_db"]) * inside
	if name == "whisper":
		db += (dread - WHISPER_DREAD) * 8.0
	var p := _rng.randf_range(pitch[0], pitch[1])
	if name == "bell":
		for i in _rng.randi_range(1, 3):
			_queue.append([_clock + i * TOLL_GAP, sound, db, p])
		return
	_play(sound, db, p)


## Lightning now: tells the stage, and the thunder follows. Strong strikes
## may show the thing in the fog (not too often), and it answers.
func strike(strength: float) -> void:
	var reveal := strength > MID and _clock - _last_reveal > REVEAL_REST and _rng.randf() < REVEAL_CHANCE
	if reveal:
		_last_reveal = _clock
		_omen = OMEN
		_queue.append([_clock + CALL_DELAY, "call", CALL_DB, _rng.randf_range(0.92, 1.02)])
	lightning.emit(strength, reveal)
	var sound := "thunder_far"
	if strength > NEAR:
		sound = "thunder_near"
	elif strength > MID:
		sound = "thunder_mid"
	var delay: Array = THUNDER_DELAY[sound]
	var db: float = THUNDER_DB[sound] - 8.0 * inside
	_queue.append([_clock + _rng.randf_range(delay[0], delay[1]), sound, db, _rng.randf_range(0.85, 1.1)])


func _play(sound: String, db: float, pitch: float) -> void:
	if sound.begins_with("thunder"):
		thundered.emit({"thunder_near": 1.0, "thunder_mid": 0.5}.get(sound, 0.15) * (1.0 - inside * 0.7))
	if not _streams.has(sound):
		_streams[sound] = load(DIR + sound + ".ogg")
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	v.stream = _streams[sound]
	v.volume_db = db
	v.pitch_scale = pitch
	v.play()
	heard.append(sound)


## A bed's player (the playtest checks they loop and play).
func bed(name: String) -> AudioStreamPlayer:
	return _beds.get(name)
