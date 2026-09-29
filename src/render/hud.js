import { MAX_HEALTH, ROUNDS_TO_WIN } from '../game/constants.js';
import { timerSeconds } from '../game/match.js';

export const HEALTH_BAR = { y: 12, h: 10, w: 144, p1x: 16, p2x: 224 };

export function healthBarFill(playerIndex, health) {
  const { y, h, w, p1x, p2x } = HEALTH_BAR;
  const width = Math.round(w * health / MAX_HEALTH);
  return { x: playerIndex === 0 ? p1x + w - width : p2x, y, w: width, h };
}

export function timerText(match) {
  return String(timerSeconds(match)).padStart(2, '0');
}

export function roundPips(playerIndex, wins) {
  const barX = playerIndex === 0 ? HEALTH_BAR.p1x : HEALTH_BAR.p2x;
  return Array.from({ length: ROUNDS_TO_WIN }, (_, i) => ({
    x: barX + i * 10,
    y: HEALTH_BAR.y + HEALTH_BAR.h + 5,
    filled: i < wins,
  }));
}
