export const SPRITE_W = 48;
export const SPRITE_H = 64;
// All poses face right, with the feet centered at (24, 63).
export const FIGHTER_STYLES = [
  { name: 'Rồng', palette: [null, '#191923', '#efb589', '#24212b', '#fff4e4',
    '#db3945', '#942b3c', '#eee4cc', '#302d3c'] },
  { name: 'Hổ', palette: [null, '#191923', '#efb589', '#65412f', '#ffd34d',
    '#387cdb', '#285091', '#eee4cc', '#302d3c'] },
];

export const POSES = ['idle0', 'idle1', 'walk0', 'walk1', 'crouch', 'jump',
  'punch', 'kick', 'crouchPunch', 'crouchKick', 'airPunch', 'airKick',
  'block', 'crouchBlock', 'hit', 'ko'];

const sprites = new Map();
const runsCache = new WeakMap();

// Cached sprites and runs are shared read-only render data.
export function generateSprite(pose) {
  if (!POSES.includes(pose)) throw new RangeError(`Unknown sprite pose: ${pose}`);
  if (sprites.has(pose)) return sprites.get(pose);
  const data = new Uint8Array(SPRITE_W * SPRITE_H);
  function rect(x, y, w, h, c) {
    for (let row = Math.max(0, y); row < Math.min(SPRITE_H, y + h); row++) {
      for (let col = Math.max(0, x); col < Math.min(SPRITE_W, x + w); col++) {
        data[row * SPRITE_W + col] = c;
      }
    }
  }

  if (pose === 'ko') {
    rect(5, 51, 11, 10, 2); // Head, hair and headband.
    rect(4, 50, 5, 10, 3);
    rect(8, 50, 2, 11, 4);
    rect(16, 50, 14, 12, 5);
    rect(17, 58, 13, 4, 6);
    rect(27, 50, 3, 12, 7);
    rect(30, 51, 11, 5, 5);
    rect(30, 58, 12, 4, 6);
    rect(40, 50, 4, 6, 8);
    rect(41, 57, 4, 5, 8);
    rect(14, 58, 11, 4, 2);
  } else {
    const crouch = pose.startsWith('crouch');
    const air = pose === 'jump' || pose.startsWith('air');
    const punch = ['punch', 'crouchPunch', 'airPunch'].includes(pose);
    const kick = ['kick', 'crouchKick', 'airKick'].includes(pose);
    const block = pose === 'block' || pose === 'crouchBlock';
    const lean = pose === 'hit' ? -5 : 0;
    const bob = pose === 'idle1' ? 1 : 0;
    const headY = crouch ? 28 : 7 + bob;
    const hipY = crouch ? 49 : 40 + bob;

    // Rear leg and supporting foot.
    const rearX = pose === 'walk0' ? 12 : pose === 'walk1' ? 21 : 16;
    rect(rearX, hipY, 8, (air ? 54 : 60) - hipY, 6);
    rect(rearX - 1, air ? 53 : 59, 10, 4, 8);
    if (kick) {
      const legY = crouch ? 54 : 35;
      rect(23, legY, 20, 8, 5);
      rect(40, legY - 1, 6, 10, 8);
    } else if (crouch) {
      rect(24, 50, 11, 8, 5);
      rect(29, 56, 6, 5, 6);
      rect(28, 59, 9, 4, 8);
    } else if (air) {
      rect(24, hipY, 10, 8, 5);
      rect(29, 46, 7, 7, 6);
      rect(29, 51, 10, 4, 8);
    } else {
      const frontX = pose === 'walk1' ? 12 : pose === 'walk0' ? 27 : 25;
      rect(frontX, hipY, 7, 20 - bob, 5);
      rect(frontX, 59, 10, 4, 8);
    }

    rect(16 + lean, headY + 13, 16, hipY - headY - 10, 5);
    rect(16 + lean, headY + 14, 5, hipY - headY - 11, 6);
    rect(16 + lean, hipY - 3, 17, 4, 7);
    rect(25 + lean, hipY, 3, 6, 7);
    rect(19 + lean, headY, 12, 13, 2);
    rect(18 + lean, headY, 13, 4, 3);
    rect(18 + lean, headY + 3, 3, 6, 3);
    rect(18 + lean, headY + 4, 14, 2, 4);
    rect(29 + lean, headY + 7, 1, 2, 1);
    rect(12 + lean, headY + 16, 6, 12, 6);
    rect(12 + lean, headY + 26, 6, 5, 2);
    if (punch) {
      rect(29 + lean, headY + 15, 10, 7, 5);
      rect(37, headY + 15, 9, 7, 2);
    } else if (block) {
      rect(29, headY + 14, 6, 10, 5);
      rect(30, headY + 7, 6, 11, 2);
      rect(25, headY + 7, 7, 5, 2);
    } else {
      rect(28 + lean, headY + 15, 6, 9, 5);
      rect(29 + lean, headY + 21, 6, 7, 2);
    }
  }

  // Read the original body so the outline cannot grow recursively.
  const body = data.slice();
  for (let y = 0; y < SPRITE_H; y++) {
    for (let x = 0; x < SPRITE_W; x++) {
      const i = y * SPRITE_W + x;
      if (!body[i] && ((x > 0 && body[i - 1]) ||
          (x + 1 < SPRITE_W && body[i + 1]) ||
          (y > 0 && body[i - SPRITE_W]) ||
          (y + 1 < SPRITE_H && body[i + SPRITE_W]))) data[i] = 1;
    }
  }
  const sprite = { w: SPRITE_W, h: SPRITE_H, data };
  sprites.set(pose, sprite);
  return sprite;
}

export function spriteToRuns(sprite) {
  if (runsCache.has(sprite)) return runsCache.get(sprite);
  const runs = [];
  for (let y = 0; y < sprite.h; y++) {
    let x = 0;
    while (x < sprite.w) {
      const start = x;
      const c = sprite.data[y * sprite.w + x++];
      while (x < sprite.w && sprite.data[y * sprite.w + x] === c) x++;
      if (c) runs.push({ x: start, y, len: x - start, c });
    }
  }
  runsCache.set(sprite, runs);
  return runs;
}

export function poseForFighter(f) {
  if (f.state === 'ko') return 'ko';
  if (f.state === 'hitstun') return 'hit';
  if (f.state === 'block' || f.state === 'blockstun') {
    return f.crouching ? 'crouchBlock' : 'block';
  }
  if (f.state === 'attack') {
    const move = f.attack.moveId;
    return { standPunch: 'punch', standKick: 'kick' }[move] ?? move;
  }
  if (!f.onGround) return 'jump';
  if (f.state === 'crouch') return 'crouch';
  if (f.state === 'walk') return `walk${Math.floor(f.stateFrame / 8) % 2}`;
  return `idle${Math.floor(f.stateFrame / 20) % 2}`;
}
