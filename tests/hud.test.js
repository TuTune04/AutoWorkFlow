import { describe, expect, it } from 'vitest';
import { FPS } from '../src/game/constants.js';
import { createMatch } from '../src/game/match.js';
import { HEALTH_BAR, healthBarFill, roundPips, timerText } from '../src/render/hud.js';

describe('HUD layout', () => {
  it('aligns health fills toward the center', () => {
    expect(HEALTH_BAR).toEqual({ y: 12, h: 10, w: 144, p1x: 16, p2x: 224 });
    expect(healthBarFill(0, 100)).toEqual({ x: 16, y: 12, w: 144, h: 10 });
    expect(healthBarFill(0, 50)).toEqual({ x: 88, y: 12, w: 72, h: 10 });
    expect(healthBarFill(1, 50)).toEqual({ x: 224, y: 12, w: 72, h: 10 });
    expect(healthBarFill(0, 0)).toEqual({ x: 160, y: 12, w: 0, h: 10 });
    expect(healthBarFill(1, 0).w).toBe(0);
    expect(healthBarFill(0, 33).w).toBe(48);
  });

  it('formats remaining seconds with two digits', () => {
    const match = createMatch();
    expect(timerText(match)).toBe('60');
    match.timer = 5 * FPS;
    expect(timerText(match)).toBe('05');
    match.timer = 0;
    expect(timerText(match)).toBe('00');
  });

  it('places two pips below each bar and fills earned wins', () => {
    for (const player of [0, 1]) {
      const pips = roundPips(player, 1);
      expect(pips).toHaveLength(2);
      expect(pips.map(pip => pip.filled)).toEqual([true, false]);
      expect(pips[0].y).toBeGreaterThan(HEALTH_BAR.y + HEALTH_BAR.h);
      expect(pips[0].x).toBe(player === 0 ? HEALTH_BAR.p1x : HEALTH_BAR.p2x);
      expect(pips[1].x).toBeGreaterThan(pips[0].x);
      expect(roundPips(player, 2).every(pip => pip.filled)).toBe(true);
    }
  });
});
