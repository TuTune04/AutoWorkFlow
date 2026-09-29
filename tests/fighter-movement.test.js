import { describe, expect, it } from 'vitest';
import { createFighter, setState, updateFighter } from '../src/game/fighter.js';
import { neutralInput } from '../src/game/input.js';
import {
  AIR_SPEED, FIGHTER_WIDTH, FRICTION, GRAVITY, GROUND_Y,
  JUMP_VELOCITY, MAX_HEALTH, STAGE_LEFT, STAGE_RIGHT,
} from '../src/game/constants.js';

const input = (overrides = {}) => ({ ...neutralInput(), ...overrides });

describe('fighter movement', () => {
  it('creates the complete initial fighter state', () => {
    expect(createFighter(1, 256, -1)).toEqual({
      playerIndex: 1, x: 256, y: GROUND_Y, vx: 0, vy: 0, facing: -1,
      health: MAX_HEALTH, state: 'idle', stateFrame: 0, onGround: true,
      crouching: false, attack: null, usedAirAttack: false, stun: 0,
    });
  });

  it('walks 20 pixels in ten frames and counts state frames once per update', () => {
    const f = createFighter(0, 128, 1);
    for (let i = 0; i < 10; i++) {
      expect(updateFighter(f, input({ right: true }))).toEqual([]);
    }
    expect(f.x).toBe(148);
    expect(f.state).toBe('walk');
    expect(f.stateFrame).toBe(9);
    updateFighter(f, input());
    expect(f.state).toBe('idle');
    expect(f.stateFrame).toBe(0);
    expect(f.vx).toBe(0);
  });

  it.each([
    ['left', STAGE_LEFT + FIGHTER_WIDTH / 2],
    ['right', STAGE_RIGHT - FIGHTER_WIDTH / 2],
  ])('clamps movement at the %s wall', (direction, wall) => {
    const f = createFighter(0, wall, 1);
    for (let i = 0; i < 10; i++) updateFighter(f, input({ [direction]: true }));
    expect(f.x).toBe(wall);
  });

  it('jumps, crosses its apex, and lands exactly once within 60 frames', () => {
    const f = createFighter(1, 128, 1);
    const events = updateFighter(f, input({ up: true, down: true, right: true }));
    expect(f.onGround).toBe(false);
    expect(f.state).toBe('jump');
    expect(f.crouching).toBe(false);
    expect(f.vx).toBe(AIR_SPEED);
    expect(f.vy).toBe(JUMP_VELOCITY + GRAVITY);
    expect(f.y).toBeLessThan(GROUND_Y);
    f.usedAirAttack = true;
    let crossedApex = false;
    for (let i = 1; i < 60; i++) {
      const previousVy = f.vy;
      events.push(...updateFighter(f, input()));
      if (previousVy < 0 && f.vy >= 0) crossedApex = true;
    }
    expect(crossedApex).toBe(true);
    expect(events).toEqual([{ type: 'jump', player: 1 }, { type: 'land', player: 1 }]);
    expect(f).toMatchObject({ y: GROUND_Y, vy: 0, onGround: true,
      state: 'idle', usedAirAttack: false });
  });

  it('crouches before walking and clears crouching on release', () => {
    const f = createFighter(0, 128, 1);
    updateFighter(f, input({ down: true, right: true }));
    expect(f).toMatchObject({ state: 'crouch', crouching: true, vx: 0 });
    updateFighter(f, input());
    expect(f).toMatchObject({ state: 'idle', crouching: false, vx: 0 });
  });

  it('prioritizes block over jumping and walking, with optional crouching', () => {
    const f = createFighter(0, 128, 1);
    expect(updateFighter(f, input({ block: true, up: true, right: true }))).toEqual([]);
    expect(f).toMatchObject({ state: 'block', vx: 0, onGround: true, crouching: false });
    updateFighter(f, input({ block: true, down: true }));
    expect(f.crouching).toBe(true);
    updateFighter(f, input());
    expect(f).toMatchObject({ state: 'idle', crouching: false });
  });

  it.each(['hitstun', 'blockstun'])('ignores input for all three frames of %s', state => {
    const f = createFighter(0, 128, 1);
    Object.assign(f, { state, stun: 3, vx: 4 });
    for (let i = 0; i < 3; i++) {
      expect(updateFighter(f, input({ up: true, right: true }))).toEqual([]);
      expect(f.state).toBe(i === 2 ? 'idle' : state);
    }
    expect(f.stun).toBe(0);
    expect(f.vx).toBeCloseTo(4 * FRICTION ** 3);
    expect(f.x).toBeCloseTo(128 + 4 * (FRICTION + FRICTION ** 2 + FRICTION ** 3));
  });

  it('returns to jump when airborne stun expires', () => {
    const f = createFighter(0, 128, 1);
    Object.assign(f, { state: 'hitstun', stun: 1, onGround: false, y: GROUND_Y - 30 });
    updateFighter(f, input());
    expect(f).toMatchObject({ state: 'jump', stateFrame: 0, onGround: false });
  });

  it.each(['ko', 'hitstun', 'blockstun'])('preserves %s on landing and applies friction', state => {
    const f = createFighter(0, 128, 1);
    Object.assign(f, { state, stun: 5, vx: 4, vy: 2, onGround: false,
      y: GROUND_Y - 1, usedAirAttack: true });
    expect(updateFighter(f, input({ up: true, right: true })))
      .toEqual([{ type: 'land', player: 0 }]);
    expect(f).toMatchObject({ state, x: 128 + 4 * FRICTION,
      y: GROUND_Y, vy: 0, onGround: true, usedAirAttack: false });
  });

  it('ignores attack buttons and cancels opposing directions', () => {
    const f = createFighter(0, 128, 1);
    updateFighter(f, input({ left: true, right: true, punchPressed: true, kickPressed: true }));
    expect(f).toMatchObject({ x: 128, vx: 0, state: 'idle', attack: null });
  });
});

describe('setState', () => {
  it('increments unchanged states and resets changed states', () => {
    const f = createFighter(0, 128, 1);
    setState(f, 'idle');
    expect(f.stateFrame).toBe(1);
    setState(f, 'walk');
    expect(f.stateFrame).toBe(0);
    expect(f.state).toBe('walk');
  });
});
