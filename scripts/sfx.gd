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
const VOICES := 10

static var _instance = null

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


static func play(sound: String) -> void:
	if _instance:
		_instance._play(sound)


func _ready() -> void:
	_instance = self
	for n in NAMES:
		_streams[n] = load("res://assets/sfx/%s.wav" % n)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _play(sound: String) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.play()
