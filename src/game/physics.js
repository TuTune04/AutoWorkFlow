import {
  CROUCH_HEIGHT, FIGHTER_HEIGHT, FIGHTER_WIDTH, STAGE_LEFT, STAGE_RIGHT,
} from './constants.js';
import { overlapX, rectsOverlap, toWorldBox } from './rect.js';

export function hurtbox(f) {
  const height = f.crouching ? CROUCH_HEIGHT : FIGHTER_HEIGHT;
  return { x: -FIGHTER_WIDTH / 2, y: -height, w: FIGHTER_WIDTH, h: height };
}

export function worldHurtbox(f) {
  return toWorldBox(f, hurtbox(f));
}

// Mutates positions and returns events (separation emits none).
export function separateFighters(a, b) {
  const aBox = worldHurtbox(a);
  const bBox = worldHurtbox(b);
  if (!rectsOverlap(aBox, bBox)) return [];

  const left = a.x <= b.x ? a : b;
  const right = left === a ? b : a;
  const halfOverlap = overlapX(aBox, bBox) / 2;
  const minX = STAGE_LEFT + FIGHTER_WIDTH / 2;
  const maxX = STAGE_RIGHT - FIGHTER_WIDTH / 2;
  left.x -= halfOverlap;
  right.x += halfOverlap;

  // Transfer any movement blocked by a wall to the other fighter.
  if (left.x < minX) {
    right.x += minX - left.x;
    left.x = minX;
  }
  if (right.x > maxX) {
    left.x -= right.x - maxX;
    right.x = maxX;
  }
  return [];
}

// Mutates facing and returns events (turning emits none).
export function updateFacing(a, b) {
  for (const [self, other] of [[a, b], [b, a]]) {
    if (self.onGround && ['idle', 'walk', 'crouch', 'block'].includes(self.state)) {
      if (other.x > self.x) self.facing = 1;
      else if (other.x < self.x) self.facing = -1;
    }
  }
  return [];
}
