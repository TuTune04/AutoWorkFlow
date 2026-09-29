import { createGame, stepGame } from './game/game.js';
import { KEY_BINDINGS, readMenuInput, readPlayerInput } from './game/input.js';
import { createFixedStepper } from './game/loop.js';
import { createKeyboard } from './input/keyboard.js';
import { render } from './render/renderer.js';
import { createAudio, playEvents } from './audio/sfx.js';

const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
ctx.imageSmoothingEnabled = false;

const keyboard = createKeyboard(window);
const game = createGame();
const audio = createAudio(window.AudioContext || window.webkitAudioContext);

function resumeAudio() {
  window.removeEventListener('keydown', resumeAudio);
  window.removeEventListener('pointerdown', resumeAudio);
  audio.resume();
}
window.addEventListener('keydown', resumeAudio);
window.addEventListener('pointerdown', resumeAudio);

const stepper = createFixedStepper(() => {
  const { held, prevHeld } = keyboard.snapshot();
  const frameInput = {
    p1: readPlayerInput(held, prevHeld, KEY_BINDINGS.p1),
    p2: readPlayerInput(held, prevHeld, KEY_BINDINGS.p2),
    menu: readMenuInput(held, prevHeld),
  };
  const events = stepGame(game, frameInput);
  audio.setMuted(game.muted);
  playEvents(audio, events);
});

let last;
function frame(now) {
  stepper.advance(last === undefined ? 0 : now - last);
  last = now;
  render(ctx, game);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
