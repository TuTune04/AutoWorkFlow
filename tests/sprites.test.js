import { describe, expect, it } from 'vitest';
import { FIGHTER_STYLES, POSES, SPRITE_W, SPRITE_H,
  generateSprite, spriteToRuns, poseForFighter } from '../src/render/sprites.js';
import { createFighter } from '../src/game/fighter.js';
import { MOVES } from '../src/game/moves.js';

function bounds(pose) {
  const sprite = generateSprite(pose);
  const xs = [], ys = [];
  sprite.data.forEach((c, i) => {
    if (c) { xs.push(i % sprite.w); ys.push(Math.floor(i / sprite.w)); }
  });
  return { right: Math.max(...xs), top: Math.min(...ys),
    height: Math.max(...ys) - Math.min(...ys) + 1 };
}

describe('procedural sprites', () => {
  it('provides compatible named fighter palettes', () => {
    expect(FIGHTER_STYLES.map(s => s.name)).toEqual(['Rồng', 'Hổ']);
    for (const style of FIGHTER_STYLES) {
      expect(style.palette).toHaveLength(9);
      expect(style.palette[0]).toBeNull();
      for (const color of style.palette.slice(1)) expect(color).toMatch(/^#[0-9a-f]{6}$/);
    }
    expect(FIGHTER_STYLES[0].palette[5]).not.toBe(FIGHTER_STYLES[1].palette[5]);
  });

  it.each(POSES)('generates and losslessly encodes %s', pose => {
    const sprite = generateSprite(pose);
    expect([SPRITE_W, SPRITE_H]).toEqual([48, 64]);
    expect(sprite).toMatchObject({ w: 48, h: 64 });
    expect(sprite.data).toBeInstanceOf(Uint8Array);
    expect(sprite.data).toHaveLength(48 * 64);
    const occupied = sprite.data.filter(c => c !== 0).length;
    expect(occupied).toBeGreaterThanOrEqual(200);
    expect(Math.max(...sprite.data)).toBeLessThan(9);
    const runs = spriteToRuns(sprite);
    expect(runs.reduce((sum, run) => sum + run.len, 0)).toBe(occupied);
    const decoded = new Uint8Array(sprite.data.length);
    for (const { x, y, len, c } of runs) {
      expect(c).toBeGreaterThan(0);
      expect(x + len).toBeLessThanOrEqual(sprite.w);
      decoded.fill(c, y * sprite.w + x, y * sprite.w + x + len);
    }
    expect(decoded).toEqual(sprite.data);
    expect(spriteToRuns(generateSprite(pose))).toBe(runs);
  });

  it('extends attacks and lowers crouching and KO silhouettes', () => {
    for (const pose of ['punch', 'kick']) {
      expect(bounds(pose).right - bounds('idle0').right).toBeGreaterThanOrEqual(8);
    }
    expect(bounds('crouch').top - bounds('idle0').top).toBeGreaterThanOrEqual(18);
    for (const pose of POSES.filter(p => p.startsWith('crouch'))) {
      expect(bounds(pose).height).toBeLessThanOrEqual(38);
    }
    expect(bounds('ko').height).toBeLessThanOrEqual(20);
    expect(bounds('ko').top).toBeGreaterThanOrEqual(44);
  });

  it('adds a one-pixel orthogonal outline without wrapping at edges', () => {
    const sprite = { w: 3, h: 2, data: Uint8Array.from([2, 2, 0, 0, 3, 3]) };
    expect(spriteToRuns(sprite)).toEqual([
      { x: 0, y: 0, len: 2, c: 2 }, { x: 1, y: 1, len: 2, c: 3 },
    ]);
    for (const pose of POSES) {
      const { w, h, data } = generateSprite(pose);
      data.forEach((c, i) => {
        if (c <= 1) return;
        const x = i % w, y = Math.floor(i / w);
        const neighbors = [];
        if (x > 0) neighbors.push(i - 1);
        if (x < w - 1) neighbors.push(i + 1);
        if (y > 0) neighbors.push(i - w);
        if (y < h - 1) neighbors.push(i + w);
        for (const n of neighbors) expect(data[n]).toBeGreaterThan(0);
      });
    }
  });
});

describe('fighter pose selection', () => {
  const pose = overrides => poseForFighter({ ...createFighter(0, 100, 1), ...overrides });

  it.each([
    [{ state: 'ko', onGround: false }, 'ko'],
    [{ state: 'hitstun', onGround: false }, 'hit'],
    [{ state: 'block' }, 'block'],
    [{ state: 'block', crouching: true }, 'crouchBlock'],
    [{ state: 'blockstun', onGround: false }, 'block'],
    [{ state: 'blockstun', crouching: true }, 'crouchBlock'],
    [{ onGround: false, state: 'crouch' }, 'jump'],
    [{ state: 'crouch' }, 'crouch'],
    [{ state: 'walk', stateFrame: 7 }, 'walk0'],
    [{ state: 'walk', stateFrame: 8 }, 'walk1'],
    [{ state: 'walk', stateFrame: 16 }, 'walk0'],
    [{ stateFrame: 19 }, 'idle0'],
    [{ stateFrame: 20 }, 'idle1'],
    [{ stateFrame: 40 }, 'idle0'],
  ])('maps %j to %s', (fighter, expected) => expect(pose(fighter)).toBe(expected));

  it.each(Object.keys(MOVES))('maps attack %s before airborne status', moveId => {
    expect(pose({ state: 'attack', onGround: false, attack: { moveId } }))
      .toBe({ standPunch: 'punch', standKick: 'kick' }[moveId] ?? moveId);
  });
});
