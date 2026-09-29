export const KEY_BINDINGS = {
  p1: {
    left: 'KeyA', right: 'KeyD', up: 'KeyW', down: 'KeyS',
    punch: 'KeyF', kick: 'KeyG', block: 'KeyH',
  },
  p2: {
    left: 'ArrowLeft', right: 'ArrowRight', up: 'ArrowUp', down: 'ArrowDown',
    punch: 'Comma', kick: 'Period', block: 'Slash',
  },
};

export const MENU_KEYS = {
  start: ['Enter', 'Space'],
  back: ['Escape'],
  mute: ['KeyM'],
};

export const ALL_BOUND_CODES = [...new Set([
  ...Object.values(KEY_BINDINGS.p1),
  ...Object.values(KEY_BINDINGS.p2),
  ...Object.values(MENU_KEYS).flat(),
])];

export function neutralInput() {
  return {
    left: false, right: false, up: false, down: false,
    punch: false, kick: false, block: false,
    punchPressed: false, kickPressed: false,
  };
}

function isPressed(held, prevHeld, code) {
  return held.has(code) && !prevHeld.has(code);
}

export function readPlayerInput(held, prevHeld, bindings) {
  const input = neutralInput();
  for (const [action, code] of Object.entries(bindings)) {
    input[action] = held.has(code);
  }
  if (input.left && input.right) {
    input.left = false;
    input.right = false;
  }
  input.punchPressed = isPressed(held, prevHeld, bindings.punch);
  input.kickPressed = isPressed(held, prevHeld, bindings.kick);
  return input;
}

export function readMenuInput(held, prevHeld) {
  return {
    startPressed: MENU_KEYS.start.some(code => isPressed(held, prevHeld, code)),
    backPressed: MENU_KEYS.back.some(code => isPressed(held, prevHeld, code)),
    mutePressed: MENU_KEYS.mute.some(code => isPressed(held, prevHeld, code)),
  };
}
