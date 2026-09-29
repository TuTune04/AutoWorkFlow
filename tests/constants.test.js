import { describe, expect, it } from 'vitest';
import {
  WIDTH, HEIGHT, FPS, STAGE_LEFT, STAGE_RIGHT,
  P1_START_X, P2_START_X, CROUCH_HEIGHT, FIGHTER_HEIGHT, GROUND_Y,
} from '../src/game/constants.js';
import config from '../vite.config.js';

describe('game constants', () => {
  it('uses the required logical resolution and simulation rate', () => {
    expect(WIDTH).toBe(384);
    expect(HEIGHT).toBe(216);
    expect(FPS).toBe(60);
  });

  it('places players in order inside the stage', () => {
    expect(STAGE_LEFT).toBeLessThan(P1_START_X);
    expect(P1_START_X).toBeLessThan(P2_START_X);
    expect(P2_START_X).toBeLessThan(STAGE_RIGHT);
  });

  it('keeps crouching lower than standing and ground within the screen', () => {
    expect(CROUCH_HEIGHT).toBeLessThan(FIGHTER_HEIGHT);
    expect(GROUND_Y).toBeLessThan(HEIGHT);
  });
});

describe('Vite configuration', () => {
  it('exposes the development server on all interfaces', () => {
    expect(config.server.host).toBe('0.0.0.0');
  });

  it('runs tests in Node', () => {
    expect(config.test.environment).toBe('node');
  });
});
