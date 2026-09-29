export function createMockCtx() {
  const ctx = { calls: [] };
  const state = { fillStyle: '#000000', font: '10px sans-serif', textAlign: 'start', textBaseline: 'alphabetic', globalAlpha: 1 };
  const stack = [];
  for (const property of Object.keys(state)) {
    Object.defineProperty(ctx, property, {
      get: () => state[property],
      set(value) {
        state[property] = value;
        ctx.calls.push([property, value]);
      },
    });
  }
  for (const method of ['fillRect', 'fillText']) {
    ctx[method] = (...args) => ctx.calls.push([method, ...args]);
  }
  ctx.save = () => {
    ctx.calls.push(['save']);
    stack.push({ ...state });
  };
  ctx.restore = () => {
    ctx.calls.push(['restore']);
    if (stack.length) Object.assign(state, stack.pop());
  };
  return ctx;
}
