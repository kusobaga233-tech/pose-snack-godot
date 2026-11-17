extends RefCounted
## Deterministic, injectable random source (xorshift32).
##
## The Web prototype uses `Math.random()` for everything except round/styles and
## powerups. A ported core cannot use a global RNG: tests must be reproducible
## and the presentation must not be able to change gameplay by drawing a number.
##
## Every consumer therefore owns a `PSRng` instance and receives it from outside:
##
##   * `PSGame.rng`        - world stream: food spawns, respawn points, snake
##                           jitter, cosmetic wave phases (the "Math.random()"
##                           stream of the JS game).
##   * `PSGame.round_rng`  - per-round stream: style + head-style shuffles
##                           (JS `roundRandom()`, xorshift32, re-seeded every round).
##   * `PSGame.powerup_rng`- powerup stream (JS `powerupRandom()`, never touches the
##                           world stream, so item placement cannot fork the sim).
##   * one `PSRng` per `PSBrain` - AI decisions (lapses, aim noise, wobble, sloppy picks).
##
## xorshift32 has a fixed 2^32-1 period and is *not* the same generator as
## V8's Math.random, so a Godot run is not bit-identical to a browser run (see
## docs/core-model.md, "Deviations"); it is however reproducible run-to-run, which
## is what the tests require.

## Current xorshift32 state (kept in [1, 0xFFFFFFFF]).
var state: int = 0x9E3779B9


func _init(p_seed: int = 0x9E3779B9) -> void:
	reset(p_seed)


## Re-seed the stream. Zero is remapped (xorshift32 must never hold 0) and the
## first four outputs are discarded so that nearby seeds diverge immediately.
func reset(p_seed: int) -> void:
	var s := p_seed & 0xFFFFFFFF
	if s == 0:
		s = 0x9E3779B9
	state = s
	next_u32()
	next_u32()
	next_u32()
	next_u32()


## Raw 32-bit step.
func next_u32() -> int:
	var x := state & 0xFFFFFFFF
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state = x & 0xFFFFFFFF
	return state


## Uniform float in `[0, 1)` (JS `Math.random()` shape).
func randf() -> float:
	return float(next_u32()) / 4294967296.0


## Uniform float in `[a, b)` (JS `randRange`).
##
## NOTE: `self.` is required on the `randf()` call. A bare `randf()` inside a
## method resolves to Godot's *global* built-in `randf()`, not to the method
## above: every `rand_range()` draw would then come from the engine's own RNG
## (nondeterministic across runs) and the seeded stream would never advance.
## That was the determinism bug found by `suite_determinism`; keep the `self.`
## prefix so the injected stream is the only source of randomness.
func rand_range(a: float, b: float) -> float:
	return a + self.randf() * (b - a)


## Uniform int in `[a, b]` (inclusive, like JS `randi` helpers).
func rand_int(a: int, b: int) -> int:
	if b <= a:
		return a
	var span := b - a + 1
	return a + int(self.randf() * float(span)) % span


## -1 or +1 with equal probability (JS `Math.random() < 0.5 ? -1 : 1`).
func rand_sign() -> float:
	return -1.0 if self.randf() < 0.5 else 1.0


## Stable 32-bit seed mixer, used to derive per-brain streams from one game seed.
## Kept to 32-bit intermediates so no literal can overflow a signed 64-bit int.
static func mix_seed(base_seed: int, salt: int) -> int:
	var h := (base_seed ^ (salt * 668265261)) & 0xFFFFFFFF
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	h = (h * 668265261) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return h
