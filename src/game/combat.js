import { setState } from './fighter.js';
import { attackPhase, MOVES } from './moves.js';
import { worldHurtbox } from './physics.js';
import { rectsOverlap, toWorldBox } from './rect.js';

export function activeHitbox(f) {
  if (!f.attack || f.attack.hasHit || attackPhase(f.attack) !== 'active') return null;
  return toWorldBox(f, MOVES[f.attack.moveId].hitbox);
}

export function canBlock(defender, level) {
  return (defender.state === 'block' || defender.state === 'blockstun')
    && (level === 'mid' || level === (defender.crouching ? 'low' : 'high'));
}

export function resolveHits(a, b) {
  const contacts = [];
  // Capture both contacts before a hit can cancel the other fighter's attack.
  for (const [attacker, defender] of [[a, b], [b, a]]) {
    const box = activeHitbox(attacker);
    if (!box || defender.state === 'ko' || !rectsOverlap(box, worldHurtbox(defender))) continue;
    const move = MOVES[attacker.attack.moveId];
    contacts.push({ attacker, defender, attack: attacker.attack, move,
      blocked: canBlock(defender, move.level) });
  }

  const events = [];
  for (const { attacker, defender, attack, move, blocked } of contacts) {
    attack.hasHit = true;
    const event = { type: blocked ? 'block' : 'hit', attacker: attacker.playerIndex,
      defender: defender.playerIndex, moveId: move.id };
    if (blocked) {
      setState(defender, 'blockstun');
      defender.stun = move.blockstun;
      defender.vx = attacker.facing * move.knockback / 2;
      events.push(event);
    } else {
      defender.health = Math.max(0, defender.health - move.damage);
      defender.attack = null;
      setState(defender, 'hitstun');
      defender.stun = move.hitstun;
      defender.vx = attacker.facing * move.knockback;
      events.push({ ...event, damage: move.damage });
      if (defender.health === 0) {
        setState(defender, 'ko');
        events.push({ type: 'ko', player: defender.playerIndex });
      }
    }
  }
  return events;
}
