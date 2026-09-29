import { FPS, GROUND_Y, HEIGHT, WIDTH } from '../game/constants.js';
import { STRINGS } from '../game/strings.js';
import { HEALTH_BAR, healthBarFill, roundPips, timerText } from './hud.js';
import { FIGHTER_STYLES, generateSprite, poseForFighter, spriteToRuns } from './sprites.js';

function drawBackdrop(ctx) {
  ctx.fillStyle = '#20283e';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);
  ctx.fillStyle = '#343e57';
  for (let x = 0; x < WIDTH; x += 32) {
    const height = 28 + (x / 32 % 3) * 16;
    ctx.fillRect(x, GROUND_Y - height, 28, height);
  }
  ctx.fillStyle = '#596175';
  ctx.fillRect(0, GROUND_Y, WIDTH, HEIGHT - GROUND_Y);
  ctx.fillStyle = '#89909b';
  ctx.fillRect(0, GROUND_Y, WIDTH, 3);
  ctx.fillStyle = '#454d60';
  for (let y = GROUND_Y + 8; y < HEIGHT; y += 8) {
    ctx.fillRect(0, y, WIDTH, 1);
    for (let x = (y % 16 ? 0 : 16); x < WIDTH; x += 32) {
      ctx.fillRect(x, y, 1, 8);
    }
  }
}

function drawFighter(ctx, fighter, playerIndex) {
  const sprite = generateSprite(poseForFighter(fighter));
  const footX = Math.round(fighter.x);
  const top = Math.round(fighter.y) - (sprite.h - 1);
  for (const run of spriteToRuns(sprite)) {
    const x = fighter.facing === -1
      ? sprite.w / 2 - run.x - run.len
      : run.x - sprite.w / 2;
    ctx.fillStyle = FIGHTER_STYLES[playerIndex].palette[run.c];
    ctx.fillRect(footX + x, top + run.y, run.len, 1);
  }
}

function drawHud(ctx, match) {
  ctx.font = '8px monospace';
  ctx.textBaseline = 'top';
  for (let i = 0; i < match.fighters.length; i++) {
    const x = i === 0 ? HEALTH_BAR.p1x : HEALTH_BAR.p2x;
    ctx.fillStyle = '#151522';
    ctx.fillRect(x, HEALTH_BAR.y, HEALTH_BAR.w, HEALTH_BAR.h);
    const fill = healthBarFill(i, match.fighters[i].health);
    ctx.fillStyle = i === 0 ? '#f8cf50' : '#eb5353';
    ctx.fillRect(fill.x, fill.y, fill.w, fill.h);
    for (const pip of roundPips(i, match.wins[i])) {
      ctx.fillStyle = pip.filled ? '#f8cf50' : '#151522';
      ctx.fillRect(pip.x, pip.y, 6, 4);
    }
    ctx.fillStyle = '#fff4e4';
    ctx.textAlign = i === 0 ? 'left' : 'right';
    ctx.fillText(FIGHTER_STYLES[i].name, i === 0 ? x : x + HEALTH_BAR.w, 2);
  }
  ctx.font = '16px monospace';
  ctx.textAlign = 'center';
  ctx.fillStyle = '#fff4e4';
  ctx.fillText(timerText(match), WIDTH / 2, HEALTH_BAR.y);
}

function overlayText(match) {
  if (match.phase === 'intro') return STRINGS.round(match.round);
  if (match.phase === 'fight' && match.phaseFrame < FPS / 2) return STRINGS.fight;
  if (match.phase === 'roundEnd' || match.phase === 'over') {
    if (match.roundWinner === 'draw') return STRINGS.draw;
    return match.fighters.some(fighter => fighter.state === 'ko') ? STRINGS.ko : STRINGS.timeUp;
  }
  return null;
}

export function drawFight(ctx, match) {
  ctx.save();
  ctx.globalAlpha = 1;
  drawBackdrop(ctx);
  match.fighters.forEach((fighter, i) => drawFighter(ctx, fighter, i));
  drawHud(ctx, match);
  const text = overlayText(match);
  if (text) {
    ctx.fillStyle = '#fff4e4';
    ctx.font = 'bold 24px monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, WIDTH / 2, HEIGHT / 2 - 24);
  }
  ctx.restore();
}
