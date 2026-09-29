import {
  AIR_SPEED, FIGHTER_WIDTH, FRICTION, GRAVITY, GROUND_Y,
  JUMP_VELOCITY, MAX_HEALTH, STAGE_LEFT, STAGE_RIGHT, WALK_SPEED,
} from './constants.js';

export function createFighter(playerIndex, x, facing) {
  return {
    playerIndex, x, y: GROUND_Y, vx: 0, vy: 0, facing, health: MAX_HEALTH,
    state: 'idle', stateFrame: 0, onGround: true, crouching: false,
    attack: null, usedAirAttack: false, stun: 0,
  };
}

export function setState(f, state) {
  f.stateFrame = f.state === state ? f.stateFrame + 1 : 0;
  f.state = state;
}

export function updateFighter(f, input) {
  const events = [];
  let state = f.state;

  if (state === 'hitstun' || state === 'blockstun') {
    f.stun = Math.max(0, f.stun - 1);
    f.vx *= FRICTION;
    if (f.stun === 0) state = f.onGround ? 'idle' : 'jump';
  } else if (state === 'ko') {
    f.vx *= FRICTION;
  } else if (f.onGround && ['idle', 'walk', 'crouch', 'block'].includes(state)) {
    const dir = Number(Boolean(input.right)) - Number(Boolean(input.left));
    f.crouching = false;
    f.vx = 0;
    if (input.block) {
      state = 'block';
      f.crouching = input.down;
    } else if (input.up) {
      f.vy = JUMP_VELOCITY;
      f.vx = dir * AIR_SPEED;
      f.onGround = false;
      state = 'jump';
      events.push({ type: 'jump', player: f.playerIndex });
    } else if (input.down) {
      state = 'crouch';
      f.crouching = true;
    } else if (dir !== 0) {
      state = 'walk';
      f.vx = dir * WALK_SPEED;
    } else {
      state = 'idle';
    }
  }

  f.x += f.vx;
  if (!f.onGround) {
    f.vy += GRAVITY;
    f.y += f.vy;
    if (f.y >= GROUND_Y) {
      f.y = GROUND_Y;
      f.vy = 0;
      f.onGround = true;
      f.usedAirAttack = false;
      if (state === 'jump') state = 'idle';
      events.push({ type: 'land', player: f.playerIndex });
    }
  }
  f.x = Math.max(STAGE_LEFT + FIGHTER_WIDTH / 2,
    Math.min(STAGE_RIGHT - FIGHTER_WIDTH / 2, f.x));
  setState(f, state);
  return events;
}
