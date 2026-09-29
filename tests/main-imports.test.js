import { describe, expect, it } from 'vitest';
import { createGame, stepGame } from '../src/game/game.js';
import { FIGHTER_WIDTH } from '../src/game/constants.js';
import { KEY_BINDINGS, readMenuInput, readPlayerInput } from '../src/game/input.js';
import { render } from '../src/render/renderer.js';
import { createMockCtx } from './helpers/mockCtx.js';

const modules = import.meta.glob('../src/{game,render,audio}/**/*.js');

describe('headless browser dependencies', () => {
  it.each(Object.entries(modules))('imports %s without browser globals', async (_path, load) => {
    expect(await load()).toBeDefined();
  });

  it('plays a full match to a P1 victory while rendering every 100 frames', () => {
    const game = createGame();
    let prevHeld = new Set();
    function step(held) {
      stepGame(game, {
        p1: readPlayerInput(held, prevHeld, KEY_BINDINGS.p1),
        p2: readPlayerInput(held, prevHeld, KEY_BINDINGS.p2),
        menu: readMenuInput(held, prevHeld),
      });
      prevHeld = held;
    }

    expect(() => render(createMockCtx(), game)).not.toThrow();
    step(new Set(['Enter']));
    expect(game.scene).toBe('fight');
    for (let frame = 0; frame < 60 * 60 * 3 && game.scene !== 'victory'; frame += 1) {
      const [p1, p2] = game.match.fighters;
      // Walk into contact again after each knockback or round reset.
      const inRange = p2.x - p1.x <= FIGHTER_WIDTH;
      step(new Set(inRange && frame % 2 === 0 ? ['KeyD', 'KeyF'] : ['KeyD']));
      if (frame % 100 === 0) {
        expect(() => render(createMockCtx(), game)).not.toThrow();
      }
    }

    expect(game.scene).toBe('victory');
    expect(game.match.matchWinner).toBe(0);
    expect(() => render(createMockCtx(), game)).not.toThrow();
  });
});
