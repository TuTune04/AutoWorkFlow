import { describe, expect, it } from 'vitest';
import { MOVES, attackPhase, moveTotalFrames, selectMove } from '../src/game/moves.js';
import { createFighter, updateFighter } from '../src/game/fighter.js';
import { neutralInput } from '../src/game/input.js';
import { AIR_SPEED, GROUND_Y } from '../src/game/constants.js';

const input = (overrides = {}) => ({ ...neutralInput(), ...overrides });

describe('moves', () => {
  it('defines exactly six moves with valid frame data and local hitboxes', () => {
    expect(Object.keys(MOVES).sort()).toEqual([
      'airKick', 'airPunch', 'crouchKick', 'crouchPunch', 'standKick', 'standPunch',
    ]);
    for (const [id, move] of Object.entries(MOVES)) {
      expect(move.id).toBe(id);
      expect(['high', 'mid', 'low']).toContain(move.level);
      for (const field of ['startup', 'active', 'recovery', 'damage', 'hitstun', 'blockstun', 'knockback']) {
        expect(Number.isInteger(move[field])).toBe(true);
        expect(move[field]).toBeGreaterThan(0);
      }
      for (const field of ['x', 'y', 'w', 'h']) {
        expect(Number.isInteger(move.hitbox[field])).toBe(true);
        expect(move.hitbox[field] * (field === 'y' ? -1 : 1)).toBeGreaterThan(0);
      }
    }
  });

  it('uses exact phase boundaries for standPunch', () => {
    expect(moveTotalFrames(MOVES.standPunch)).toBe(15);
    for (let frame = 0; frame <= 16; frame++) {
      expect(attackPhase({ moveId: 'standPunch', frame })).toBe(
        frame < 4 ? 'startup' : frame < 7 ? 'active' : frame < 15 ? 'recovery' : 'done',
      );
    }
  });

  it.each(['punch', 'kick'])('selects %s by stance, with airborne taking priority', button => {
    const suffix = button === 'punch' ? 'Punch' : 'Kick';
    expect(selectMove(button, false, false)).toBe(MOVES[`stand${suffix}`]);
    expect(selectMove(button, true, false)).toBe(MOVES[`crouch${suffix}`]);
    expect(selectMove(button, false, true)).toBe(MOVES[`air${suffix}`]);
    expect(selectMove(button, true, true)).toBe(MOVES[`air${suffix}`]);
  });
});

describe('fighter attacks', () => {
  it.each([false, true])('prioritizes punch over other actions with down=%s', down => {
    const f = createFighter(0, 128, 1);
    updateFighter(f, input({ right: true }));
    const moveId = down ? 'crouchPunch' : 'standPunch';
    expect(updateFighter(f, input({ punchPressed: true, kickPressed: true,
      down, block: true, up: true, right: true })))
      .toEqual([{ type: 'whiff', player: 0, moveId }]);
    expect(f).toMatchObject({ state: 'attack', crouching: down, vx: 0, onGround: true,
      attack: { moveId, frame: 0, hasHit: false } });
  });

  it.each([false, true])('finishes after exactly 15 further updates with down=%s', down => {
    const f = createFighter(0, 128, 1);
    updateFighter(f, input({ punchPressed: true }));
    for (let frame = 1; frame <= moveTotalFrames(MOVES.standPunch); frame++) {
      expect(updateFighter(f, input({ right: true, up: true, block: true,
        punchPressed: true, kickPressed: true, down }))).toEqual([]);
      expect(f.x).toBe(128);
      expect(f.vx).toBe(0);
      if (frame < 15) {
        expect(f.state).toBe('attack');
        expect(f.attack.frame).toBe(frame);
      }
    }
    expect(f).toMatchObject({ attack: null, state: down ? 'crouch' : 'idle', crouching: down });
  });

  it('allows one air attack per jump, retaining momentum and resetting on landing', () => {
    const f = createFighter(1, 128, -1);
    updateFighter(f, input({ up: true, right: true }));
    expect(updateFighter(f, input({ kickPressed: true })))
      .toEqual([{ type: 'whiff', player: 1, moveId: 'airKick' }]);
    expect(f).toMatchObject({ vx: AIR_SPEED, usedAirAttack: true,
      attack: { moveId: 'airKick', frame: 0, hasHit: false } });
    for (let i = 0; i < moveTotalFrames(MOVES.airKick); i++) updateFighter(f, input());
    expect(f).toMatchObject({ state: 'jump', onGround: false, attack: null });
    expect(updateFighter(f, input({ punchPressed: true }))).toEqual([]);
    expect(f.attack).toBeNull();
    for (let i = 0; i < 40 && !f.onGround; i++) updateFighter(f, input());
    expect(f).toMatchObject({ onGround: true, usedAirAttack: false });
    updateFighter(f, input({ up: true }));
    expect(updateFighter(f, input({ punchPressed: true })))
      .toEqual([{ type: 'whiff', player: 1, moveId: 'airPunch' }]);
  });

  it('cancels an air attack on landing', () => {
    const f = createFighter(0, 128, 1);
    Object.assign(f, { state: 'jump', onGround: false, y: GROUND_Y - 3, vy: 1 });
    updateFighter(f, input({ kickPressed: true }));
    expect(f.state).toBe('attack');
    expect(updateFighter(f, input({ down: true }))).toEqual([{ type: 'land', player: 0 }]);
    expect(f).toMatchObject({ state: 'idle', attack: null, usedAirAttack: false, onGround: true });
  });
});
