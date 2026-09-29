import { describe, expect, it } from 'vitest';
import {
  CROUCH_HEIGHT, FIGHTER_HEIGHT, FIGHTER_WIDTH, GROUND_Y, STAGE_LEFT, STAGE_RIGHT,
} from '../src/game/constants.js';
import { createFighter } from '../src/game/fighter.js';
import { hurtbox, separateFighters, updateFacing, worldHurtbox } from '../src/game/physics.js';
import { rectsOverlap } from '../src/game/rect.js';

const minX = STAGE_LEFT + FIGHTER_WIDTH / 2;
const maxX = STAGE_RIGHT - FIGHTER_WIDTH / 2;

function expectSeparated(a, b) {
  expect(rectsOverlap(worldHurtbox(a), worldHurtbox(b))).toBe(false);
  for (const f of [a, b]) {
    expect(f.x).toBeGreaterThanOrEqual(minX);
    expect(f.x).toBeLessThanOrEqual(maxX);
  }
}

describe('hurtboxes', () => {
  it.each([false, true])('uses crouching=%s to choose height in either facing', crouching => {
    const height = crouching ? CROUCH_HEIGHT : FIGHTER_HEIGHT;
    for (const facing of [-1, 1]) {
      const f = createFighter(0, 100, facing);
      f.crouching = crouching;
      expect(hurtbox(f)).toEqual({ x: -12, y: -height, w: 24, h: height });
      expect(worldHurtbox(f)).toEqual({ x: 88, y: GROUND_Y - height, w: 24, h: height });
    }
  });
});

describe('separateFighters', () => {
  it.each([false, true])('shares overlap equally with reversed arguments=%s', reversed => {
    const a = createFighter(0, 100, 1);
    const b = createFighter(1, 110, -1);
    expect(reversed ? separateFighters(b, a) : separateFighters(a, b)).toEqual([]);
    expect([a.x, b.x]).toEqual([93, 117]);
    expect((a.x + b.x) / 2).toBe(105);
    expectSeparated(a, b);
  });

  it.each([
    [minX, 1], [maxX, -1],
  ])('transfers all blocked movement at wall %s', (wall, direction) => {
    const a = createFighter(0, wall, direction);
    const b = createFighter(1, wall + direction * 10, -direction);
    separateFighters(a, b);
    expect(a.x).toBe(wall);
    expect(b.x).toBe(wall + direction * FIGHTER_WIDTH);
    expectSeparated(a, b);
  });

  it.each([minX, 100, maxX])('pushes a left and b right at equal x=%s', x => {
    const a = createFighter(0, x, 1);
    const b = createFighter(1, x, -1);
    separateFighters(a, b);
    expect(a.x).toBeLessThan(b.x);
    expect(b.x - a.x).toBe(FIGHTER_WIDTH);
    expectSeparated(a, b);
  });

  it.each([FIGHTER_HEIGHT, FIGHTER_HEIGHT + 10])('leaves vertically separated fighters alone at height %s', height => {
    const a = createFighter(0, 100, 1);
    const b = createFighter(1, 100, -1);
    Object.assign(a, { y: GROUND_Y - height, onGround: false, state: 'jump' });
    const before = structuredClone([a, b]);
    expect(separateFighters(a, b)).toEqual([]);
    expect([a, b]).toEqual(before);
  });

  it.each([24, 40])('leaves horizontally non-overlapping fighters alone at distance %s', distance => {
    const a = createFighter(0, 100, 1);
    const b = createFighter(1, 100 + distance, -1);
    separateFighters(a, b);
    expect([a.x, b.x]).toEqual([100, 100 + distance]);
  });
});

describe('updateFacing', () => {
  it.each(['idle', 'walk', 'crouch', 'block'])('turns grounded fighters in %s after crossing sides', state => {
    const a = createFighter(0, 110, 1);
    const b = createFighter(1, 100, -1);
    a.state = b.state = state;
    expect(updateFacing(a, b)).toEqual([]);
    expect([a.facing, b.facing]).toEqual([-1, 1]);
  });

  it.each(['attack', 'jump', 'hitstun', 'blockstun', 'ko'])('preserves facing in %s independently of the opponent', state => {
    const a = createFighter(0, 110, 1);
    const b = createFighter(1, 100, -1);
    a.state = state;
    updateFacing(a, b);
    expect([a.facing, b.facing]).toEqual([1, 1]);
  });

  it.each(['idle', 'walk', 'crouch', 'block'])('does not turn airborne fighters even in %s', state => {
    const a = createFighter(0, 110, 1);
    const b = createFighter(1, 100, -1);
    Object.assign(a, { onGround: false, state });
    updateFacing(a, b);
    expect(a.facing).toBe(1);
  });

  it('preserves both facings at equal positions', () => {
    const a = createFighter(0, 100, -1);
    const b = createFighter(1, 100, 1);
    updateFacing(a, b);
    expect([a.facing, b.facing]).toEqual([-1, 1]);
  });
});
