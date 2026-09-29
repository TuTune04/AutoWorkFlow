import { describe, expect, it } from 'vitest';
import {
  FPS, GROUND_Y, INTRO_FRAMES, MAX_HEALTH, P1_START_X, P2_START_X,
  ROUND_END_FRAMES, ROUND_TIME,
} from '../src/game/constants.js';
import { createFighter } from '../src/game/fighter.js';
import { neutralInput } from '../src/game/input.js';
import { createMatch, resetRound, stepMatch, timerSeconds } from '../src/game/match.js';

const neutral = () => [neutralInput(), neutralInput()];
const active = () => [0, 1].map(() => ({ ...neutralInput(), right: true, up: true,
  punchPressed: true, kickPressed: true, block: true }));

function advance(match, frames, inputs = neutral()) {
  const events = [];
  for (let frame = 0; frame < frames; frame++) events.push(...stepMatch(match, inputs));
  return events;
}

function fightingMatch() {
  const match = createMatch();
  advance(match, INTRO_FRAMES);
  return match;
}

describe('match', () => {
  it('creates independent matches with the specified initial state', () => {
    const match = createMatch();
    expect(match).toEqual({ round: 1, wins: [0, 0], phase: 'intro', phaseFrame: 0,
      timer: ROUND_TIME * FPS, fighters: [createFighter(0, P1_START_X, 1),
        createFighter(1, P2_START_X, -1)], roundWinner: null, matchWinner: null });
    match.wins[0]++;
    match.fighters[0].health = 1;
    expect(createMatch().wins).toEqual([0, 0]);
    expect(createMatch().fighters[0].health).toBe(MAX_HEALTH);
  });

  it('ignores intro inputs and starts fighting on exactly the last intro frame', () => {
    const match = createMatch();
    expect(advance(match, INTRO_FRAMES - 1, active()))
      .toEqual([{ type: 'roundStart', round: 1 }]);
    expect(match).toMatchObject({ phase: 'intro', phaseFrame: INTRO_FRAMES - 1,
      timer: ROUND_TIME * FPS });
    expect(match.fighters.map(f => [f.x, f.state, f.attack]))
      .toEqual([[P1_START_X, 'idle', null], [P2_START_X, 'idle', null]]);
    expect(stepMatch(match, active())).toEqual([{ type: 'fight' }]);
    expect(match).toMatchObject({ phase: 'fight', phaseFrame: 0 });
    expect(timerSeconds(match)).toBe(60);
    advance(match, FPS - 1);
    expect(timerSeconds(match)).toBe(60);
    stepMatch(match, neutral());
    expect(timerSeconds(match)).toBe(59);
    expect(match.timer).toBe(ROUND_TIME * FPS - FPS);
  });

  it('runs combat and forwards attack, hit and KO events before ending the round', () => {
    const match = fightingMatch();
    match.fighters[1].x = P1_START_X + 30;
    match.fighters[1].health = 1;
    const inputs = neutral();
    inputs[0].punchPressed = true;
    expect(stepMatch(match, inputs)).toContainEqual({ type: 'whiff', player: 0,
      moveId: 'standPunch' });
    const events = advance(match, 4);
    expect(events).toEqual([
      { type: 'hit', attacker: 0, defender: 1, moveId: 'standPunch', damage: 6 },
      { type: 'ko', player: 1 },
      { type: 'roundEnd', winner: 0, reason: 'ko' },
    ]);
    expect(match).toMatchObject({ phase: 'roundEnd', phaseFrame: 0,
      roundWinner: 0, wins: [1, 0] });
  });

  it.each([[0, 1, [0, 1]], [1, 0, [1, 0]], ['both', 'draw', [1, 1]]])(
    'awards the round for KO of %s', (victim, winner, wins) => {
      const match = fightingMatch();
      for (const f of match.fighters) {
        if (victim === 'both' || f.playerIndex === victim) f.state = 'ko';
      }
      expect(stepMatch(match, neutral())).toEqual([{ type: 'roundEnd', winner, reason: 'ko' }]);
      expect(match.wins).toEqual(wins);
      expect(match.roundWinner).toBe(winner);
    },
  );

  it.each([[50, 40, 0, [1, 0]], [40, 50, 1, [0, 1]], [50, 50, 'draw', [1, 1]]])(
    'resolves time-over at health %s to %s', (health1, health2, winner, wins) => {
      const match = fightingMatch();
      match.fighters[0].health = health1;
      match.fighters[1].health = health2;
      expect(advance(match, ROUND_TIME * FPS)).toEqual([
        { type: 'timeUp' }, { type: 'roundEnd', winner, reason: 'time' },
      ]);
      expect(match).toMatchObject({ phase: 'roundEnd', phaseFrame: 0,
        timer: 0, roundWinner: winner, wins });
      expect(timerSeconds(match)).toBe(0);
      expect(advance(match, 10)).toEqual([]);
      expect(match.timer).toBe(0);
      expect(match.wins).toEqual(wins);
    },
  );

  it('settles KO fighters, ignores end inputs, and resets on exactly the final end frame', () => {
    const match = fightingMatch();
    Object.assign(match.fighters[1], { state: 'ko', health: 0,
      y: GROUND_Y - 10, onGround: false, vy: 1 });
    match.fighters[0].health = 50;
    stepMatch(match, neutral());
    const timer = match.timer;
    expect(advance(match, ROUND_END_FRAMES - 1, active()))
      .toEqual([{ type: 'land', player: 1 }]);
    expect(match).toMatchObject({ phase: 'roundEnd', phaseFrame: ROUND_END_FRAMES - 1,
      round: 1, timer, wins: [1, 0] });
    expect(match.fighters[1]).toMatchObject({ state: 'ko', onGround: true, y: GROUND_Y });
    expect(stepMatch(match, active())).toEqual([]);
    expect(match).toMatchObject({ phase: 'intro', phaseFrame: 0, round: 2,
      timer: ROUND_TIME * FPS, roundWinner: null, matchWinner: null, wins: [1, 0] });
    expect(match.fighters).toEqual(createMatch().fighters);
    expect(stepMatch(match, neutral())).toEqual([{ type: 'roundStart', round: 2 }]);
  });

  it.each([0, 1, 'draw'])('finishes a match with winner %s and freezes over state', winner => {
    const match = fightingMatch();
    for (let round = 0; round < 2; round++) {
      for (const f of match.fighters) {
        if (winner === 'draw' || f.playerIndex !== winner) f.state = 'ko';
      }
      stepMatch(match, neutral());
      advance(match, ROUND_END_FRAMES - 1);
      expect(match.phase).toBe('roundEnd');
      const events = stepMatch(match, neutral());
      if (round === 0) {
        expect(events).toEqual([]);
        expect(match.round).toBe(2);
        expect(match.fighters).toEqual(createMatch().fighters);
        advance(match, INTRO_FRAMES);
      } else {
        expect(events).toEqual([{ type: 'matchOver', winner }]);
      }
    }
    expect(match).toMatchObject({ phase: 'over', phaseFrame: 0, matchWinner: winner });
    const before = structuredClone(match);
    expect(advance(match, 100, active())).toEqual([]);
    expect(match).toEqual(before);
  });

  it('exports a round reset that preserves the round and scores', () => {
    const match = fightingMatch();
    match.round = 3;
    match.wins = [1, 1];
    match.timer = 1;
    match.roundWinner = 'draw';
    match.fighters[0].health = 2;
    resetRound(match);
    expect(match).toEqual({ ...createMatch(), round: 3, wins: [1, 1] });
  });
});
