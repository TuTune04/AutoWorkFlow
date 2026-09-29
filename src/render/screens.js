import { FPS, HEIGHT, P1_START_X, P2_START_X, WIDTH } from '../game/constants.js';
import { STRINGS } from '../game/strings.js';
import { FIGHTER_STYLES, generateSprite, spriteToRuns } from './sprites.js';

function background(ctx) {
  ctx.globalAlpha = 1;
  ctx.fillStyle = '#151522';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
}

function text(ctx, value, y, size = 10) {
  ctx.fillStyle = '#fff4e4';
  ctx.font = `${size}px monospace`;
  ctx.fillText(value, WIDTH / 2, y);
}

function idleSprite(ctx, playerIndex, x, y, facing, pose) {
  const sprite = generateSprite(pose);
  for (const run of spriteToRuns(sprite)) {
    const offset = facing === -1
      ? sprite.w / 2 - run.x - run.len
      : run.x - sprite.w / 2;
    ctx.fillStyle = FIGHTER_STYLES[playerIndex].palette[run.c];
    ctx.fillRect(x + offset, y - (sprite.h - 1) + run.y, run.len, 1);
  }
}

export function drawTitle(ctx, game) {
  ctx.save();
  background(ctx);
  text(ctx, STRINGS.title, 26, 28);
  text(ctx, STRINGS.subtitle, 51, 12);
  const pose = `idle${Math.floor(game.sceneFrame / 20) % 2}`;
  idleSprite(ctx, 0, P1_START_X, 126, 1, pose);
  idleSprite(ctx, 1, P2_START_X, 126, -1, pose);
  if (Math.floor(game.sceneFrame / (FPS / 2)) % 2 === 0) {
    text(ctx, STRINGS.pressStart, 145, 12);
  }
  text(ctx, STRINGS.controlsP1, 170, 9);
  text(ctx, STRINGS.controlsP2, 185, 9);
  text(ctx, STRINGS.muteHint, 204, 9);
  ctx.restore();
}

export function drawVictory(ctx, game) {
  ctx.save();
  background(ctx);
  const { matchWinner, wins } = game.match;
  text(ctx, matchWinner === 'draw'
    ? STRINGS.draw
    : STRINGS.wins(FIGHTER_STYLES[matchWinner].name), 35, 24);
  text(ctx, `${wins[0]} - ${wins[1]}`, 67, 18);
  if (matchWinner !== 'draw') {
    idleSprite(ctx, matchWinner, WIDTH / 2, 148, 1, 'idle0');
  }
  if (game.sceneFrame >= FPS) text(ctx, STRINGS.backToTitle, 185, 12);
  ctx.restore();
}
