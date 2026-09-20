extends AudioStreamPlayer

var playback
var phase := 0.0
const MIX_RATE := 22050.0

@onready var car = get_parent()

func _ready():
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.35
	stream = generator
	volume_db = -17.0
	play()
	playback = get_stream_playback()

func _process(_delta):
	if playback == null or car == null:
		return
	var frames = playback.get_frames_available()
	var speed_ratio = clamp(abs(car.speed) / car.max_speed, 0.0, 1.0)
	var frequency = 52.0 + speed_ratio * 118.0
	var radio_strength = float(car.get_meta("radio_signal", 0.0))
	var engine_amp = 0.035 + speed_ratio * 0.055
	var hiss_amp = (1.0 - radio_strength) * 0.014
	for i in range(frames):
		phase += TAU * frequency / MIX_RATE
		if phase > TAU:
			phase -= TAU
		var engine = (sin(phase) + 0.28 * sin(phase * 2.03)) * engine_amp
		var hiss = randf_range(-1.0, 1.0) * hiss_amp
		var sample = clamp(engine + hiss, -0.18, 0.18)
		playback.push_frame(Vector2(sample, sample))
