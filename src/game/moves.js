export const MOVES = {
  standPunch: { id: 'standPunch', startup: 4, active: 3, recovery: 8, damage: 6,
    hitstun: 14, blockstun: 8, knockback: 3, level: 'mid', hitbox: { x: 10, y: -46, w: 22, h: 10 } },
  standKick: { id: 'standKick', startup: 7, active: 4, recovery: 14, damage: 10,
    hitstun: 18, blockstun: 10, knockback: 5, level: 'mid', hitbox: { x: 8, y: -30, w: 30, h: 12 } },
  crouchPunch: { id: 'crouchPunch', startup: 4, active: 3, recovery: 8, damage: 5,
    hitstun: 12, blockstun: 7, knockback: 2, level: 'mid', hitbox: { x: 10, y: -28, w: 20, h: 8 } },
  crouchKick: { id: 'crouchKick', startup: 8, active: 4, recovery: 16, damage: 9,
    hitstun: 18, blockstun: 10, knockback: 4, level: 'low', hitbox: { x: 6, y: -10, w: 32, h: 10 } },
  airPunch: { id: 'airPunch', startup: 4, active: 6, recovery: 6, damage: 7,
    hitstun: 14, blockstun: 8, knockback: 3, level: 'high', hitbox: { x: 8, y: -42, w: 20, h: 12 } },
  airKick: { id: 'airKick', startup: 5, active: 8, recovery: 6, damage: 9,
    hitstun: 16, blockstun: 9, knockback: 4, level: 'high', hitbox: { x: 6, y: -26, w: 26, h: 14 } },
};

export function moveTotalFrames(move) {
  return move.startup + move.active + move.recovery;
}

export function attackPhase(attack) {
  const move = MOVES[attack.moveId];
  if (attack.frame < move.startup) return 'startup';
  if (attack.frame < move.startup + move.active) return 'active';
  if (attack.frame < moveTotalFrames(move)) return 'recovery';
  return 'done';
}

export function selectMove(button, crouching, airborne) {
  const stance = airborne ? 'air' : crouching ? 'crouch' : 'stand';
  return MOVES[stance + (button === 'punch' ? 'Punch' : 'Kick')];
}
