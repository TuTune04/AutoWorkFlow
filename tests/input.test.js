import { describe, expect, it } from 'vitest';
import {
  ALL_BOUND_CODES, KEY_BINDINGS, MENU_KEYS,
  neutralInput, readMenuInput, readPlayerInput,
} from '../src/game/input.js';

describe('player input', () => {
  it('returns a fresh neutral input with every action false', () => {
    expect(neutralInput()).toEqual({
      left: false, right: false, up: false, down: false,
      punch: false, kick: false, block: false,
      punchPressed: false, kickPressed: false,
    });
    expect(neutralInput()).not.toBe(neutralInput());
  });

  it('maps KeyD to P1 right and ignores it for P2', () => {
    const held = new Set(['KeyD']);
    expect(readPlayerInput(held, new Set(), KEY_BINDINGS.p1).right).toBe(true);
    expect(readPlayerInput(held, new Set(), KEY_BINDINGS.p2)).toEqual(neutralInput());
  });

  it.each([
    ['p1', ['KeyA', 'KeyD', 'KeyW', 'KeyS', 'KeyF', 'KeyG', 'KeyH']],
    ['p2', ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Comma', 'Period', 'Slash']],
  ])('maps every %s action and cancels opposing directions', (player, codes) => {
    const actions = ['left', 'right', 'up', 'down', 'punch', 'kick', 'block'];
    codes.forEach((code, index) => {
      expect(readPlayerInput(new Set([code]), new Set(), KEY_BINDINGS[player])[actions[index]])
        .toBe(true);
    });
    const held = new Set(codes);
    expect(readPlayerInput(held, new Set(), KEY_BINDINGS[player])).toMatchObject({
      left: false, right: false, up: true, down: true,
      punch: true, kick: true, block: true,
    });
    expect([...held]).toEqual(codes);
  });

  it.each([
    ['p1', 'punch', 'KeyF'], ['p1', 'kick', 'KeyG'],
    ['p2', 'punch', 'Comma'], ['p2', 'kick', 'Period'],
  ])('triggers %s %s only on a press edge', (player, action, code) => {
    const held = new Set([code]);
    const bindings = KEY_BINDINGS[player];
    expect(readPlayerInput(held, new Set(), bindings)).toMatchObject({
      [action]: true, [`${action}Pressed`]: true,
    });
    expect(readPlayerInput(held, held, bindings)).toMatchObject({
      [action]: true, [`${action}Pressed`]: false,
    });
    expect(readPlayerInput(new Set(), held, bindings)).toEqual(neutralInput());
    expect(readPlayerInput(held, new Set(), bindings)[`${action}Pressed`]).toBe(true);
  });
});

describe('menu input', () => {
  it.each([
    ['Space', 'startPressed'], ['Enter', 'startPressed'],
    ['Escape', 'backPressed'], ['KeyM', 'mutePressed'],
  ])('detects the %s press edge', (code, action) => {
    const neutral = { startPressed: false, backPressed: false, mutePressed: false };
    const held = new Set([code]);
    expect(readMenuInput(held, new Set())).toEqual({ ...neutral, [action]: true });
    expect(readMenuInput(held, held)).toEqual(neutral);
    expect(readMenuInput(new Set(), held)).toEqual(neutral);
  });

  it('detects a new start key while another start key is held', () => {
    expect(readMenuInput(new Set(['Enter', 'Space']), new Set(['Enter'])).startPressed)
      .toBe(true);
  });
});

describe('bound codes', () => {
  it('includes every player and menu code exactly once', () => {
    expect(MENU_KEYS).toEqual({ start: ['Enter', 'Space'], back: ['Escape'], mute: ['KeyM'] });
    expect(ALL_BOUND_CODES).toContain('Slash');
    expect(ALL_BOUND_CODES).toContain('Enter');
    expect(ALL_BOUND_CODES).toHaveLength(18);
    expect(new Set(ALL_BOUND_CODES).size).toBe(ALL_BOUND_CODES.length);
    expect(new Set(ALL_BOUND_CODES)).toEqual(new Set([
      ...Object.values(KEY_BINDINGS.p1), ...Object.values(KEY_BINDINGS.p2),
      ...Object.values(MENU_KEYS).flat(),
    ]));
  });
});
