import { describe, expect, it } from 'vitest';
import { FPS } from '../src/game/constants.js';
import { createMatch } from '../src/game/match.js';
import { drawFight } from '../src/render/renderer.js';
import { FIGHTER_STYLES } from '../src/render/sprites.js';
import { createMockCtx } from './helpers/mockCtx.js';

function texts(ctx) {
  return ctx.calls.filter(call => call[0] === 'fillText').map(call => call[1]);
}

function fighterRects(ctx) {
  let color;
  return ctx.calls.filter(call => {
    if (call[0] === 'fillStyle') color = call[1];
    return call[0] === 'fillRect' && color === FIGHTER_STYLES[0].palette[5];
  }).map(call => call.slice(1));
}

describe('fight renderer', () => {
  it('draws the stage, fighters, names, timer and intro without mutating the match', () => {
    const ctx = createMockCtx();
    const match = createMatch();
    const before = structuredClone(match);
    drawFight(ctx, match);
    expect(ctx.calls.filter(call => call[0] === 'fillRect').length).toBeGreaterThan(50);
    expect(texts(ctx)).toEqual(expect.arrayContaining(['HIỆP 1', '60', 'Rồng', 'Hổ']));
    expect(match).toEqual(before);
  });

  it('mirrors each colored sprite run around rounded feet positions', () => {
    const match = createMatch();
    match.fighters[0].x = 128.4;
    match.fighters[0].y += 0.4;
    const right = createMockCtx();
    drawFight(right, match);
    match.fighters[0].facing = -1;
    const left = createMockCtx();
    drawFight(left, match);
    const rightRects = fighterRects(right);
    const leftRects = fighterRects(left);
    expect(rightRects.length).toBeGreaterThan(0);
    expect(leftRects).toEqual(rightRects.map(([x, y, w, h]) => [256 - x - w, y, w, h]));
    expect(Math.min(...leftRects.map(rect => rect[0]))).not.toBe(Math.min(...rightRects.map(rect => rect[0])));
    expect(rightRects.flat().every(Number.isInteger)).toBe(true);
  });

  it.each([
    ['fight', 0, null, false, 'ĐÁNH!'],
    ['roundEnd', 0, 0, true, 'K.O.'],
    ['roundEnd', 0, 1, false, 'HẾT GIỜ!'],
    ['roundEnd', 0, 'draw', false, 'HÒA!'],
  ])('renders %s phase overlay %s', (phase, frame, winner, ko, expected) => {
    const match = createMatch();
    Object.assign(match, { phase, phaseFrame: frame, roundWinner: winner });
    if (ko) match.fighters[1].state = 'ko';
    const ctx = createMockCtx();
    drawFight(ctx, match);
    expect(texts(ctx)).toContain(expected);
  });

  it('clears the fight announcement and restores context properties', () => {
    const match = createMatch();
    Object.assign(match, { phase: 'fight', phaseFrame: FPS });
    const ctx = createMockCtx();
    ctx.fillStyle = 'purple';
    ctx.globalAlpha = 0.5;
    drawFight(ctx, match);
    expect(texts(ctx)).not.toContain('ĐÁNH!');
    expect(ctx.fillStyle).toBe('purple');
    expect(ctx.globalAlpha).toBe(0.5);
  });
});
