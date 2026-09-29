import {
  FPS, INTRO_FRAMES, P1_START_X, P2_START_X, ROUND_END_FRAMES,
  ROUND_TIME, ROUNDS_TO_WIN,
} from './constants.js';
import { resolveHits } from './combat.js';
import { createFighter, updateFighter } from './fighter.js';
import { neutralInput } from './input.js';
import { separateFighters, updateFacing } from './physics.js';

function changePhase(match, phase) {
  match.phase = phase;
  match.phaseFrame = 0;
}

// Resets round-local state while preserving the round number and match score.
export function resetRound(match) {
  match.fighters = [createFighter(0, P1_START_X, 1), createFighter(1, P2_START_X, -1)];
  match.timer = ROUND_TIME * FPS;
  match.roundWinner = null;
  changePhase(match, 'intro');
}

export function createMatch() {
  const match = { round: 1, wins: [0, 0], matchWinner: null };
  resetRound(match);
  return match;
}

export function timerSeconds(match) {
  return Math.ceil(match.timer / FPS);
}

export function stepMatch(match, inputs) {
  if (match.phase === 'over') return [];

  const events = [];
  const [a, b] = match.fighters;
  if (match.phase === 'intro' || match.phase === 'roundEnd') {
    if (match.phase === 'intro' && match.phaseFrame === 0) {
      events.push({ type: 'roundStart', round: match.round });
    }
    for (const fighter of match.fighters) {
      events.push(...updateFighter(fighter, neutralInput()));
    }
    match.phaseFrame++;
    if (match.phase === 'intro' && match.phaseFrame >= INTRO_FRAMES) {
      changePhase(match, 'fight');
      events.push({ type: 'fight' });
    } else if (match.phase === 'roundEnd' && match.phaseFrame >= ROUND_END_FRAMES) {
      const won = match.wins.map(wins => wins >= ROUNDS_TO_WIN);
      if (won[0] || won[1]) {
        match.matchWinner = won[0] && won[1] ? 'draw' : won[0] ? 0 : 1;
        changePhase(match, 'over');
        events.push({ type: 'matchOver', winner: match.matchWinner });
      } else {
        match.round++;
        resetRound(match);
      }
    }
    return events;
  }

  events.push(...updateFighter(a, inputs[0]), ...updateFighter(b, inputs[1]));
  events.push(...separateFighters(a, b), ...resolveHits(a, b), ...updateFacing(a, b));
  match.timer--;
  match.phaseFrame++;

  let winner;
  let reason;
  if (a.state === 'ko' || b.state === 'ko') {
    winner = a.state === b.state ? 'draw' : a.state === 'ko' ? 1 : 0;
    reason = 'ko';
  } else if (match.timer === 0) {
    events.push({ type: 'timeUp' });
    winner = a.health === b.health ? 'draw' : a.health > b.health ? 0 : 1;
    reason = 'time';
  }
  if (reason) {
    match.roundWinner = winner;
    if (winner === 'draw') {
      match.wins[0]++;
      match.wins[1]++;
    } else {
      match.wins[winner]++;
    }
    changePhase(match, 'roundEnd');
    events.push({ type: 'roundEnd', winner, reason });
  }
  return events;
}
