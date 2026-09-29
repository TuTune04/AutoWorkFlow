import { ALL_BOUND_CODES } from '../game/input.js';

export function createKeyboard(target = window) {
  const held = new Set();
  const boundCodes = new Set(ALL_BOUND_CODES);
  let prevHeld = new Set();

  target.addEventListener('keydown', event => {
    if (boundCodes.has(event.code)) event.preventDefault();
    held.add(event.code);
  });
  target.addEventListener('keyup', event => {
    if (boundCodes.has(event.code)) event.preventDefault();
    held.delete(event.code);
  });
  target.addEventListener('blur', () => held.clear());

  return {
    held,
    snapshot() {
      const snapshot = { held: new Set(held), prevHeld };
      prevHeld = new Set(held);
      return snapshot;
    },
  };
}
