extends RefCounted
## Grace-tolerant "hold this long" accumulator for the raise-a-hand gates.
##
## The pose stream arrives at 15-30 Hz and keypoint noise makes the wrist dip
## under the raise threshold for a single frame. Resetting the hold on that frame
## used to wipe ~1.4 s of a genuinely held raise (the owner held his arm up for
## 30 s and the READY slot never reached 已准备). This keeps the accumulated
## seconds for GRACE_SEC after the last frame that saw the raise and resumes
## counting from that value when the raise comes back inside the window.
##
## Two callers share it so the rule cannot drift apart:
##   * main.gd `_ready_step` — READY_RAISE_SEC (1.5 s) per slot
##   * ps_pose_input.gd — the raise-to-start menu shortcut
##
## `step()` is pure bookkeeping: no node, no timer, no allocation.

## Seconds the last observed raise stays credited after it disappears. 0.30 s
## covers ~4-9 dropped frames at 15-30 Hz without letting a lowered arm linger.
const GRACE_SEC := 0.30

## Accumulated seconds with the raise held (the grace window is never added).
var hold := 0.0
## Seconds left in the grace window: 0 while the hand is up or once it expired.
var grace := 0.0
## Clock (s) of the last frame that actually saw the raise; -1 = never.
var last_seen := -1.0
## One-shot latch: true once `hold` reached the threshold; the caller consumes it.
var latched := false
## True after at least one raise frame anchored `last_seen`, so a stale clock
## cannot credit a long gap to the hold.
var _seen := false


func reset() -> void:
	hold = 0.0
	grace = 0.0
	last_seen = -1.0
	latched = false
	_seen = false


## Feed one observation of the slot.
##   now       — clock in seconds (the caller's monotonic game time)
##   dt        — seconds since the previous observation of this slot
##   raised    — the hand is up on this frame
##   armed     — the gate is open (READY: the player held the zone long enough)
##   threshold — seconds the raise must accumulate before `latched` fires
func step(now: float, dt: float, raised: bool, armed: bool, threshold: float) -> void:
	if not armed:
		# A closed gate starts from zero: time held before the player entered the
		# zone must not count, and the grace window belongs to the gate only.
		hold = 0.0
		grace = 0.0
		_seen = false
		return
	if raised:
		hold += maxf(0.0, dt)
		last_seen = now
		grace = 0.0
		_seen = true
		if hold >= threshold:
			latched = true
		return
	# No raise on this frame: hold the accumulation for GRACE_SEC (one noisy
	# frame must not reset it), then drop it if the hand does not come back.
	if hold <= 0.0 or not _seen:
		hold = 0.0
		grace = 0.0
		return
	grace = maxf(0.0, GRACE_SEC - (now - last_seen))
	if grace <= 0.0:
		hold = 0.0
		_seen = false
