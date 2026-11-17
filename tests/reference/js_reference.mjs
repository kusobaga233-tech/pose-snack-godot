// Reference values extracted from the Web prototype's own source.
//
// The GDScript test suite hard-codes the numbers printed here, so any drift in
// the port shows up as a failing assertion instead of a silent behaviour change.
//
//   node tests/reference/js_reference.mjs
//
// It imports `js/config.js` directly from the prototype checkout, so the formulas
// (snakeRadius, computeAiPressure) are the real ones, not a re-implementation.
// The two compound formulas that live in `js/snake.js` / `js/ai.js` (speed
// slowdown, AI turn ease) are reproduced verbatim below with a comment pointing at
// their source lines.

import { CONFIG, TUNING, snakeRadius, computeAiPressure } from
  '../../../pose-snake-full-20261112/pose-snake/js/config.js';

const C = CONFIG;

const out = [];
const p = (label, value) => out.push(`${label}=${value}`);

p('world.w', C.world.tileW * C.world.tilesX);
p('world.h', C.world.tileH * C.world.tilesY);
p('radius@16', snakeRadius(16));
p('radius@40', snakeRadius(40));
p('radius@68', snakeRadius(68));
p('radius@120', snakeRadius(120));
p('radius@500', snakeRadius(500));

// js/snake.js updateSpeed(): base * speedMul * (1 - strength * (1 - e^(-extra/scale)))
const speedAt = (len, speedMul = 1, boost = 1, pose = 1) => {
  const S = C.slowdown;
  const extra = Math.max(0, len - C.snake.startSegments);
  const k = 1 - Math.exp(-extra / S.scale);
  return C.snake.baseSpeed * speedMul * (1 - S.strength * k) * boost * pose;
};
p('speed@16', speedAt(16));
p('speed@21', speedAt(21));
p('speed@76', speedAt(76));
p('speed@136', speedAt(136));
p('speed@76.speedMul1.1', speedAt(76, 1.1));
p('speed@76.pose1.8', speedAt(76, 1, 1, 1.8));
p('speed@76.boost', speedAt(76, 1, C.powerups.boost.speedMul));

// js/snake.js update(): maxTurn = rate * turnEase * turnMul * (1 + |diff|/PI * (reverseBoost-1)) * dt
const maxTurn = (diff, rate = C.turn.rate, ease = 1, turnMul = 1, dt = 1 / 60) =>
  rate * ease * turnMul * (1 + (Math.abs(diff) / Math.PI) * (C.turn.reverseBoost - 1)) * dt;
p('turn.PI', maxTurn(Math.PI));
p('turn.half', maxTurn(Math.PI / 2));
p('turn.quarter', maxTurn(Math.PI / 4));
p('turn.small', maxTurn(0.1));
// The applied turn is `const turned = clamp(diff, -maxTurn, maxTurn)`:
// when |diff| < maxTurn the snake follows the target exactly, it is not
// snapped up to the ceiling. These are the values suite_config/suite_snake
// assert for a small diff / wobble.
const appliedTurn = (diff, rate = C.turn.rate, ease = 1, turnMul = 1, dt = 1 / 60) =>
  Math.max(-maxTurn(diff, rate, ease, turnMul, dt),
    Math.min(maxTurn(diff, rate, ease, turnMul, dt), diff));
p('turn.small.applied', appliedTurn(0.1));
p('turn.aboveKnee.applied', appliedTurn(0.2));
p('turn.wobbleAboveCap.applied', appliedTurn(0.5));

// js/game.js rewardKill()
const killGain = (loserLen, isPlayer) => {
  const K = C.snake.killReward;
  let gain = K.enabled
    ? Math.min(K.maxGain, Math.max(K.minGain, Math.round(loserLen * K.absorb)))
    : C.snake.growPerKill;
  if (isPlayer) gain = Math.round(gain * K.playerMul);
  else gain = Math.max(1, Math.round(gain * K.aiMul));
  return gain;
};
p('kill.16.player', killGain(16, true));
p('kill.16.ai', killGain(16, false));
p('kill.60.player', killGain(60, true));
p('kill.60.ai', killGain(60, false));
p('kill.200.player', killGain(200, true));
p('kill.200.ai', killGain(200, false));

p('food.bigRadius', C.food.radius * 1.22);
p('eatR.22.24', 22 + 24 * C.food.eatPadding);

// js/ai.js: AI_TURN_EASE and AI_WOBBLE_GAIN are module-private constants.
p('ai.turnEase', 0.72 + (1.32 - 0.72) * 0.62);
p('ai.wobbleGain', 0.15);

// js/config.js computeAiPressure()
p('pressure.level1.pressure1', computeAiPressure({ aiLevel: 1, aiPressure: 1 }));
p('pressure.level0.85.pressure1', computeAiPressure({ aiLevel: 0.85, aiPressure: 1 }));
p('pressure.level0.5.pressure1', computeAiPressure({ aiLevel: 0.5, aiPressure: 1 }));
p('pressure.level0.85.pressure0', computeAiPressure({ aiLevel: 0.85, aiPressure: 0 }));

// AI derived coefficients at the default difficulty/pressure (js/ai.js think()).
const level = TUNING.aiLevel;
const pressure = computeAiPressure(TUNING);
const D = C.ai.difficulty;
p('ai.level', level);
p('ai.pressure', pressure);
p('ai.weak', 1 - level);
p('ai.sense', D.senseFloor + (1 - D.senseFloor) * level);
p('ai.guard', 1 - level + (level - (1 - level)) * pressure);
p('ai.probeDist', (C.ai.probeDist + C.ai.survival.wallProbeAdd * pressure) *
  (D.senseFloor + (1 - D.senseFloor) * level));
p('ai.avoidRadius', C.ai.avoidRadius * (1 + C.ai.survival.senseAdd * pressure) *
  (D.senseFloor + (1 - D.senseFloor) * level));
p('ai.attackRatio', (C.ai.attackRatio + D.attackBonus * (1 - level)) *
  (1 - pressure) + C.ai.hunt.ratio * pressure);
p('ai.attackRange', 420 * (0.4 + 0.6 * level) + C.ai.hunt.rangeAdd * pressure);
p('ai.aggression', (0.8 + C.ai.hunt.aggressionAdd * pressure) * (0.25 + 0.75 * level));
p('ai.reactionSec', D.reactionMaxSec * (1 - level));
p('ai.retargetExtra', D.retargetMaxSec * (1 - level));
p('ai.lapsePerSec', D.lapsePerSec * D.mistakeRate);

p('round.duration', C.round.durationSec);
p('food.target', C.food.targetCount);
p('ai.count', C.ai.count);
p('round.totalPlayers', C.round.totalPlayers);
p('snake.startSegments', C.snake.startSegments);
p('snake.segDist', C.snake.segDist);
p('collide.headOnCos', C.collide.headOnCos);

console.log(out.join('\n'));
