class_name SoundBank
extends RefCounted
## Placeholder audio, synthesised in code: noise bursts and tones, no files.
## Every sound has a normal and a muffled version (the same samples through a low-pass filter).

const RATE := 22050


## Returns kind -> [normal: AudioStreamWAV, muffled: AudioStreamWAV].
static func build() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var bank := {}
	# kind: [seconds, tone start Hz, tone end Hz, tone level, noise level, decay rate]
	var recipes := {
		"step_crouch": [0.07, 90.0, 60.0, 0.4, 0.3, 45.0],
		"step_walk": [0.09, 110.0, 70.0, 0.5, 0.5, 40.0],
		"step_sprint": [0.11, 130.0, 70.0, 0.6, 0.8, 34.0],
		"door_open": [0.5, 190.0, 330.0, 0.5, 0.15, 4.0],
		"door_crack": [0.25, 240.0, 300.0, 0.3, 0.08, 8.0],
		"door_close": [0.18, 95.0, 55.0, 0.9, 0.5, 22.0],
		"shot_carbine": [0.28, 220.0, 60.0, 0.5, 1.0, 16.0],
		"shot_pistol": [0.2, 320.0, 90.0, 0.4, 0.9, 22.0],
		"shot_shotgun": [0.42, 150.0, 40.0, 0.7, 1.0, 10.0],
		"throw": [0.1, 2800.0, 2400.0, 0.5, 0.1, 40.0],
		"bang": [0.7, 80.0, 30.0, 0.9, 1.0, 6.0],
		"fuse": [0.08, 1800.0, 1800.0, 0.7, 0.0, 6.0],
		"force": [0.14, 80.0, 45.0, 1.0, 0.7, 20.0],
		"alarm": [0.5, 2200.0, 1700.0, 0.7, 0.0, 1.0],
	}
	for kind: String in recipes:
		var r: Array = recipes[kind]
		var samples := _synthesise(r[0], r[1], r[2], r[3], r[4], r[5], rng)
		bank[kind] = [_stream(samples), _stream(_low_pass(samples, 0.15))]
	return bank


static func _synthesise(seconds: float, from_hz: float, to_hz: float, tone: float, noise: float,
		decay: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		phase += TAU * lerpf(from_hz, to_hz, float(i) / count) / RATE
		var envelope := exp(-decay * t) * minf(t * 400.0, 1.0)  # tiny fade-in avoids a click
		samples[i] = (sin(phase) * tone + rng.randf_range(-1.0, 1.0) * noise) * envelope
	return samples


static func _low_pass(samples: PackedFloat32Array, strength: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var held := 0.0
	for i in samples.size():
		held += (samples[i] - held) * strength
		out[i] = held
	return out


static func _stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
