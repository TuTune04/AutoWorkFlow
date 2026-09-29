import { FPS } from './constants.js';

export function createFixedStepper(step, { stepMs = 1000 / FPS, maxSteps = 5 } = {}) {
  let accumulator = 0;

  return {
    advance(elapsedMs) {
      accumulator += Number.isNaN(elapsedMs) || elapsedMs < 0 ? 0 : elapsedMs;
      let steps = 0;

      while (accumulator >= stepMs && steps < maxSteps) {
        accumulator -= stepMs;
        step();
        steps += 1;
      }

      // Drop accumulated time when the catch-up budget is exhausted.
      if (steps === maxSteps) accumulator = 0;
      return steps;
    },
  };
}
