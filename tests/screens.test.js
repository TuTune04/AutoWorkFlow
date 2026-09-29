import { describe, expect, it } from 'vitest';
import { createGame } from '../src/game/game.js';
import { createMatch } from '../src/game/match.js';
import { STRINGS } from '../src/game/strings.js';
import { render } from '../src/render/renderer.js';
import { drawTitle, drawVictory } from '../src/render/screens.js';
import { FIGHTER_STYLES } from '../src/render/sprites.js';
import { createMockCtx } from './helpers/mockCtx.js';

const texts = ctx => ctx.calls.filter(call => call[0] === 'fillText').map(call => call[1]);

function victory(winner = 1, sceneFrame = 0) {
  return { ...createGame(), scene: 'victory', sceneFrame,
    match: { ...createMatch(), matchWinner: winner, wins: [1, 2] } };
}

describe('menu screens and scene rendering', () => {
  it.each([0, 29, 30, 59, 60])('blinks the title prompt at frame %s', sceneFrame => {
    const ctx = createMockCtx();
    render(ctx, { ...createGame(), sceneFrame });
    expect(texts(ctx)).toEqual(expect.arrayContaining([
      'PIXEL FIGHTER', STRINGS.subtitle, STRINGS.controlsP1, STRINGS.controlsP2, STRINGS.muteHint,
    ]));
    expect(texts(ctx).includes(STRINGS.pressStart)).toBe(Math.floor(sceneFrame / 30) % 2 === 0);
    for (const style of FIGHTER_STYLES) {
      expect(ctx.calls).toContainEqual(['fillStyle', style.palette[5]]);
    }
  });

  it.each([[0, 'Rồng CHIẾN THẮNG!'], [1, 'Hổ CHIẾN THẮNG!'], ['draw', 'HÒA!']])(
    'renders winner %s and final score', (winner, announcement) => {
      const ctx = createMockCtx();
      render(ctx, victory(winner));
      expect(texts(ctx)).toEqual([announcement, '1 - 2']);
      if (winner !== 'draw') {
        expect(ctx.calls).toContainEqual(['fillStyle', FIGHTER_STYLES[winner].palette[5]]);
      }
    },
  );

  it.each([0, 59, 60, 61])('shows the return prompt after one second, frame %s', frame => {
    const ctx = createMockCtx();
    drawVictory(ctx, victory(1, frame));
    expect(texts(ctx).includes(STRINGS.backToTitle)).toBe(frame >= 60);
  });

  it('dispatches fight rendering with the match timer after intro', () => {
    const ctx = createMockCtx();
    const match = { ...createMatch(), phase: 'fight', phaseFrame: 60 };
    render(ctx, { ...createGame(), scene: 'fight', match });
    expect(texts(ctx)).toEqual(expect.arrayContaining(['60', 'Rồng', 'Hổ']));
    expect(texts(ctx)).not.toContain(STRINGS.title);
  });

  it.each(['title', 'fight', 'victory'])('draws the mute marker in %s only when muted', scene => {
    const game = { ...victory(), scene };
    const audible = createMockCtx();
    render(audible, game);
    expect(texts(audible)).not.toContain('TẮT TIẾNG');
    const muted = createMockCtx();
    render(muted, { ...game, muted: true });
    expect(texts(muted).at(-1)).toBe('TẮT TIẾNG');
  });

  it.each([[drawTitle, createGame()], [drawVictory, victory()]])(
    'preserves game state and context properties', (draw, game) => {
      const before = structuredClone(game);
      const ctx = createMockCtx();
      ctx.fillStyle = 'purple';
      ctx.globalAlpha = 0.5;
      draw(ctx, game);
      expect(game).toEqual(before);
      expect(ctx.fillStyle).toBe('purple');
      expect(ctx.globalAlpha).toBe(0.5);
    },
  );
});
