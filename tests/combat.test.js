import { describe, expect, it } from 'vitest';
import { activeHitbox, canBlock, resolveHits } from '../src/game/combat.js';
import { GROUND_Y } from '../src/game/constants.js';
import { createFighter, updateFighter } from '../src/game/fighter.js';
import { MOVES } from '../src/game/moves.js';

function attacking(f, moveId = 'standPunch', frame = MOVES[moveId].startup) {
  f.state = 'attack';
  f.attack = { moveId, frame, hasHit: false };
  return f;
}

function pair() {
  return [attacking(createFighter(0, 100, 1)), createFighter(1, 130, -1)];
}

describe('activeHitbox', () => {
  it.each([1, -1])('converts the active box to world coordinates facing %s', facing => {
    const f = attacking(createFighter(0, 100, facing));
    expect(activeHitbox(f)).toEqual({ x: facing === 1 ? 110 : 68,
      y: GROUND_Y - 46, w: 22, h: 10 });
  });

  it('returns null without an attack, outside active frames, or after contact', () => {
    const f = createFighter(0, 100, 1);
    expect(activeHitbox(f)).toBeNull();
    for (const frame of [2, 7, 15]) {
      attacking(f, 'standPunch', frame);
      expect(activeHitbox(f)).toBeNull();
    }
    attacking(f).attack.hasHit = true;
    expect(activeHitbox(f)).toBeNull();
  });
});

describe('canBlock', () => {
  it.each(['block', 'blockstun'])('uses stance for %s', state => {
    const f = createFighter(0, 100, 1);
    f.state = state;
    for (const crouching of [false, true]) {
      f.crouching = crouching;
      expect(['high', 'mid', 'low'].map(level => canBlock(f, level)))
        .toEqual([!crouching, true, crouching]);
    }
  });

  it.each(['idle', 'crouch', 'attack', 'hitstun', 'ko'])('cannot block in %s', state => {
    const f = createFighter(0, 100, 1);
    f.state = state;
    expect(canBlock(f, 'mid')).toBe(false);
  });
});

describe('resolveHits', () => {
  it.each([false, true])('hits and pushes away with reversed positions=%s', reversed => {
    const [a, b] = pair();
    if (reversed) Object.assign(a, { x: 160, facing: -1 });
    attacking(b, 'standKick', 2);
    expect(resolveHits(a, b)).toEqual([
      { type: 'hit', attacker: 0, defender: 1, moveId: 'standPunch', damage: 6 },
    ]);
    expect(b).toMatchObject({ health: 94, state: 'hitstun', stun: 14,
      vx: reversed ? -3 : 3, attack: null });
    expect(a.attack.hasHit).toBe(true);
    a.attack.frame++;
    expect(resolveHits(a, b)).toEqual([]);
    expect(b.health).toBe(94);
  });

  it.each(['startup', 'distance', 'height', 'ko'])('ignores %s without mutation', reason => {
    const [a, b] = pair();
    if (reason === 'startup') a.attack.frame = 2;
    if (reason === 'distance') b.x = a.x + 80;
    if (reason === 'height') b.y = GROUND_Y - 100;
    if (reason === 'ko') b.state = 'ko';
    const before = structuredClone([a, b]);
    expect(resolveHits(a, b)).toEqual([]);
    expect([a, b]).toEqual(before);
  });

  it.each([
    ['standKick', false, true], ['airKick', false, true],
    ['crouchKick', false, false], ['crouchKick', true, true],
    ['airKick', true, false], ['standKick', true, true],
  ])('resolves %s against crouching=%s as blocked=%s', (moveId, crouching, blocked) => {
    const [a, b] = pair();
    attacking(a, moveId);
    Object.assign(b, { state: 'block', crouching });
    const move = MOVES[moveId];
    const event = { type: blocked ? 'block' : 'hit', attacker: 0, defender: 1, moveId };
    if (!blocked) event.damage = move.damage;
    expect(resolveHits(a, b)).toEqual([event]);
    expect(b).toMatchObject({ health: blocked ? 100 : 100 - move.damage,
      state: blocked ? 'blockstun' : 'hitstun',
      stun: blocked ? move.blockstun : move.hitstun,
      vx: move.knockback / (blocked ? 2 : 1) });
    expect(a.attack.hasHit).toBe(true);
    expect(resolveHits(a, b)).toEqual([]);
  });

  it.each([false, true])('allows simultaneous punches with reversed resolution=%s', reversed => {
    const [a, b] = pair();
    attacking(b);
    const attacks = [a.attack, b.attack];
    expect(reversed ? resolveHits(b, a) : resolveHits(a, b)).toEqual(
      (reversed ? [1, 0] : [0, 1]).map(player => ({ type: 'hit', attacker: player,
        defender: 1 - player, moveId: 'standPunch', damage: 6 })),
    );
    for (const f of [a, b]) {
      expect(f).toMatchObject({ health: 94, state: 'hitstun', stun: 14, attack: null });
    }
    expect(attacks.every(attack => attack.hasHit)).toBe(true);
    expect([a.vx, b.vx]).toEqual([-3, 3]);
  });

  it('emits KO after the hit and lets an airborne victim keep falling', () => {
    const [a, b] = pair();
    attacking(a, 'standKick');
    Object.assign(b, { health: 5, y: GROUND_Y - 10, onGround: false, vy: 1 });
    expect(resolveHits(a, b)).toEqual([
      { type: 'hit', attacker: 0, defender: 1, moveId: 'standKick', damage: 10 },
      { type: 'ko', player: 1 },
    ]);
    expect(b).toMatchObject({ health: 0, state: 'ko', onGround: false, vy: 1 });
    updateFighter(b, {});
    expect(b.y).toBeGreaterThan(GROUND_Y - 10);
    expect(b.state).toBe('ko');
  });
});
