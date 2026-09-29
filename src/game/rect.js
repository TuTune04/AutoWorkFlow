// World rectangles use their top-left corner as the origin.
export function rectsOverlap(a, b) {
  return overlapX(a, b) > 0
    && Math.min(a.y + a.h, b.y + b.h) > Math.max(a.y, b.y);
}

export function toWorldBox(fighter, box) {
  return {
    x: fighter.facing === 1
      ? fighter.x + box.x
      : fighter.x - box.x - box.w,
    y: fighter.y + box.y,
    w: box.w,
    h: box.h,
  };
}

export function overlapX(a, b) {
  return Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x));
}
