import { describe, expect, it, vi } from 'vitest';
import { FPS } from '../src/game/constants.js';
import { createFixedStepper } from '../src/game/loop.js';

describe('fixed-timestep loop', () => {
  it('runs one step for one default frame', () => {
    const step = vi.fn();
    const stepper = createFixedStepper(step);

    expect(stepper.advance(1000 / FPS)).toBe(1);
    expect(step).toHaveBeenCalledTimes(1);
  });

  it('accumulates partial frames at the default simulation rate', () => {
    const step = vi.fn();
    const stepper = createFixedStepper(step);

    expect(stepper.advance(8)).toBe(0);
    expect(stepper.advance(8)).toBe(0);
    expect(stepper.advance(1)).toBe(1);
    expect(step).toHaveBeenCalledTimes(1);
  });

  it('runs a 16 ms step after two 8 ms advances', () => {
    const step = vi.fn();
    const stepper = createFixedStepper(step, { stepMs: 16 });

    expect(stepper.advance(8)).toBe(0);
    expect(stepper.advance(8)).toBe(1);
    expect(step).toHaveBeenCalledTimes(1);
  });

  it('caps catch-up at five steps and discards the backlog', () => {
    const step = vi.fn();
    const stepper = createFixedStepper(step);

    expect(stepper.advance(1000)).toBe(5);
    expect(stepper.advance(0)).toBe(0);
    expect(step).toHaveBeenCalledTimes(5);
  });

  it('treats negative and NaN elapsed time as zero without losing accumulated time', () => {
    const step = vi.fn();
    const stepper = createFixedStepper(step, { stepMs: 16 });

    expect(stepper.advance(8)).toBe(0);
    expect(stepper.advance(-5)).toBe(0);
    expect(stepper.advance(NaN)).toBe(0);
    expect(step).not.toHaveBeenCalled();
    expect(stepper.advance(8)).toBe(1);
    expect(step).toHaveBeenCalledTimes(1);
  });

  it('preserves remainders below the cap and honors a custom catch-up budget', () => {
    const step = vi.fn();
    const stepper = createFixedStepper(step, { stepMs: 10, maxSteps: 3 });

    expect(stepper.advance(25)).toBe(2);
    expect(stepper.advance(5)).toBe(1);
    expect(stepper.advance(100)).toBe(3);
    expect(stepper.advance(0)).toBe(0);
    expect(step).toHaveBeenCalledTimes(6);
  });
});
