import { describe, expect, it } from 'vitest';
import { overlapX, rectsOverlap, toWorldBox } from '../src/game/rect.js';

describe('rectsOverlap', () => {
  const rect = { x: 0, y: 0, w: 10, h: 10 };

  it.each([
    ['intersection', { x: 5, y: 5, w: 10, h: 10 }, true],
    ['horizontal separation', { x: 11, y: 0, w: 10, h: 10 }, false],
    ['vertical separation', { x: 0, y: 11, w: 10, h: 10 }, false],
    ['horizontal edge contact', { x: 10, y: 0, w: 10, h: 10 }, false],
    ['vertical edge contact', { x: 0, y: 10, w: 10, h: 10 }, false],
    ['corner contact', { x: 10, y: 10, w: 10, h: 10 }, false],
    ['containment', { x: 2, y: 2, w: 3, h: 3 }, true],
    ['identical rectangles', rect, true],
  ])('handles %s in either argument order', (_label, other, expected) => {
    expect(rectsOverlap(rect, other)).toBe(expected);
    expect(rectsOverlap(other, rect)).toBe(expected);
  });
});

describe('toWorldBox', () => {
  it.each([
    [1, 110],
    [-1, 70],
  ])('transforms a local box with facing %i', (facing, x) => {
    const fighter = Object.freeze({ x: 100, y: 184, facing });
    const box = Object.freeze({ x: 10, y: -40, w: 20, h: 10 });

    expect(toWorldBox(fighter, box)).toEqual({ x, y: 144, w: 20, h: 10 });
  });
});

describe('overlapX', () => {
  it.each([
    ['intersection', { x: 5, w: 10 }, 5],
    ['separation', { x: 11, w: 10 }, 0],
    ['edge contact', { x: 10, w: 10 }, 0],
    ['containment', { x: 2, w: 3 }, 3],
  ])('measures horizontal %s in either argument order', (_label, other, expected) => {
    const rect = { x: 0, w: 10 };
    expect(overlapX(rect, other)).toBe(expected);
    expect(overlapX(other, rect)).toBe(expected);
  });
});
