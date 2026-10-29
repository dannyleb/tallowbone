## Sound effects. Lives once in the main scene; anything can call
## Sfx.play("hit") through the static helper.
##
## The sounds in assets/sfx are synthesized placeholders
## (tools/make_sfx.py), here for feel and timing until real recordings
## replace them.
extends Node

const NAMES := [
	"swing", "heavy", "hit", "shot", "click", "glint", "parry", "visceral", "dash", "jump", "hurt",
	"splash", "heal", "blood", "burn", "lamp", "tallow", "gorge", "death", "buy", "deny", "gate", "find",
]
## Sounds recorded in several takes (assets/sfx/<name>_1.ogg, _2, ...), one
## picked at random each time: name -> how many.
const TAKES := {"step_stone": 4, "step_wood": 3, "land": 2, "growl": 2, "snarl": 2, "moan": 3}
## How much quieter (or louder) than the rest, in dB.
const GAIN := {"step_stone": -10.0, "step_wood": -9.0, "land": -5.0, "growl": -1.0, "snarl": -1.0, "moan": -3.0}
const VOICES := 12

static var _instance = null

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
## Which take to play: its own random numbers, so sounds never change what
## the game's do.
var _rng := RandomNumberGenerator.new()
## How many times each sound has played (for the playtest).
var counts := {}


static func play(sound: String) -> void:
	if _instance:
		_instance._play(sound)


func _ready() -> void:
	_instance = self
	for n in NAMES:
		_streams[n] = load("res://assets/sfx/%s.wav" % n)
	for n in TAKES:
		var takes: Array[AudioStream] = []
		for i in TAKES[n]:
			takes.append(load("res://assets/sfx/%s_%d.ogg" % [n, i + 1]))
		_streams[n] = takes
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _play(sound: String) -> void:
	counts[sound] = int(counts.get(sound, 0)) + 1
	var found = _streams.get(sound)
	if found is Array:
		found = found[_rng.randi() % found.size()]
	var stream: AudioStream = found
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.volume_db = -6.0 + float(GAIN.get(sound, 0.0))
	p.pitch_scale = _rng.randf_range(0.94, 1.06) if TAKES.has(sound) else 1.0
	p.play()
