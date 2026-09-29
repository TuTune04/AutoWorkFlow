import { describe, expect, it } from 'vitest';
import { FPS, ROUND_END_FRAMES, ROUNDS_TO_WIN } from '../src/game/constants.js';
import { createGame, stepGame } from '../src/game/game.js';
import { neutralInput } from '../src/game/input.js';
import { createMatch } from '../src/game/match.js';

function frame(menu = {}, p1 = neutralInput(), p2 = neutralInput()) {
  return { p1, p2, menu: { startPressed: false, backPressed: false,
    mutePressed: false, ...menu } };
}

function fightingGame() {
  const game = createGame();
  stepGame(game, frame({ startPressed: true }));
  return game;
}

describe('game scenes', () => {
  it('starts on the title and ignores player input', () => {
    const game = createGame();
    expect(game).toEqual({ scene: 'title', sceneFrame: 0, match: null, muted: false });
    const active = { ...neutralInput(), right: true, up: true, punchPressed: true };
    expect(stepGame(game, frame({}, active, active))).toEqual([]);
    expect(game).toEqual({ scene: 'title', sceneFrame: 1, match: null, muted: false });
  });

  it('starts a fresh match without stepping it on the title transition', () => {
    const game = createGame();
    stepGame(game, frame());
    expect(stepGame(game, frame({ startPressed: true }))).toEqual([{ type: 'select' }]);
    expect(game).toEqual({ scene: 'fight', sceneFrame: 0, match: createMatch(), muted: false });
    const previousMatch = game.match;
    previousMatch.wins[0] = 1;
    stepGame(game, frame({ backPressed: true }));
    stepGame(game, frame({ startPressed: true }));
    expect(game.match).not.toBe(previousMatch);
    expect(game.match).toEqual(createMatch());
  });

  it('forwards match events and both player inputs while fighting', () => {
    const game = fightingGame();
    expect(stepGame(game, frame())).toEqual([{ type: 'roundStart', round: 1 }]);
    expect(game.sceneFrame).toBe(1);
    game.match.phase = 'fight';
    const positions = game.match.fighters.map(fighter => fighter.x);
    stepGame(game, frame({}, { ...neutralInput(), left: true },
      { ...neutralInput(), right: true }));
    expect(game.match.fighters[0].x).toBeLessThan(positions[0]);
    expect(game.match.fighters[1].x).toBeGreaterThan(positions[1]);
    expect(game.sceneFrame).toBe(2);
  });

  it('enters victory and ignores confirmation for exactly the first 60 frames', () => {
    const game = fightingGame();
    game.match.phase = 'over';
    const finishedMatch = structuredClone(game.match);
    expect(stepGame(game, frame({ startPressed: true }))).toEqual([]);
    expect(game).toMatchObject({ scene: 'victory', sceneFrame: 0 });
    for (let i = 0; i < FPS; i++) {
      expect(stepGame(game, frame({ startPressed: true }))).toEqual([]);
      expect(game.scene).toBe('victory');
      expect(game.sceneFrame).toBe(i + 1);
    }
    expect(game.match).toEqual(finishedMatch);
    expect(stepGame(game, frame({ startPressed: true }))).toEqual([{ type: 'select' }]);
    expect(game).toMatchObject({ scene: 'title', sceneFrame: 0 });
    stepGame(game, frame({ startPressed: true }));
    expect(game.match).toEqual(createMatch());
  });

  it('preserves the final match event when the match enters over during a step', () => {
    const game = fightingGame();
    Object.assign(game.match, { phase: 'roundEnd', phaseFrame: ROUND_END_FRAMES - 1,
      wins: [ROUNDS_TO_WIN, 0] });
    expect(stepGame(game, frame())).toEqual([{ type: 'matchOver', winner: 0 }]);
    expect(game).toMatchObject({ scene: 'victory', sceneFrame: 0,
      match: { phase: 'over', matchWinner: 0 } });
  });

  it.each(['title', 'fight', 'victory'])('toggles mute in %s', scene => {
    const game = scene === 'title' ? createGame() : fightingGame();
    if (scene === 'victory') {
      game.match.phase = 'over';
      stepGame(game, frame());
    }
    stepGame(game, frame({ mutePressed: true }));
    expect(game.muted).toBe(true);
    stepGame(game, frame());
    expect(game.muted).toBe(true);
    stepGame(game, frame({ mutePressed: true }));
    expect(game.muted).toBe(false);
    expect(game.scene).toBe(scene);
  });

  it('handles Escape before stepping the match and mute alongside transitions', () => {
    const game = createGame();
    stepGame(game, frame({ startPressed: true, mutePressed: true }));
    expect(game.muted).toBe(true);
    const match = game.match;
    const before = structuredClone(match);
    expect(stepGame(game, frame({ backPressed: true, startPressed: true,
      mutePressed: true }))).toEqual([]);
    expect(match).toEqual(before);
    expect(game).toEqual(createGame());
  });
});
