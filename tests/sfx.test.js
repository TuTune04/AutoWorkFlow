import { describe, expect, it, vi } from 'vitest';
import { createAudio, playEvents, SFX } from '../src/audio/sfx.js';

function createHarness() {
  const contexts = [];
  const param = () => ({
    setValueAtTime: vi.fn(),
    linearRampToValueAtTime: vi.fn(),
    exponentialRampToValueAtTime: vi.fn(),
  });
  const node = () => ({ connect: vi.fn(), start: vi.fn(), stop: vi.fn() });
  class FakeAudioContext {
    constructor() {
      contexts.push(this);
      this.currentTime = 10;
      this.sampleRate = 8000;
      this.destination = {};
      this.resume = vi.fn().mockResolvedValue(undefined);
      this.createOscillator = vi.fn(() => ({ ...node(), frequency: param() }));
      this.createGain = vi.fn(() => ({ ...node(), gain: param() }));
      this.createBufferSource = vi.fn(node);
      this.createBuffer = vi.fn((channels, length, sampleRate) => {
        const data = new Float32Array(length);
        return { sampleRate, getChannelData: () => data };
      });
    }
  }
  return { audio: createAudio(FakeAudioContext), contexts };
}

describe('sound effects', () => {
  it('defines a valid recipe for every game sound', () => {
    const types = ['hit', 'block', 'whiff', 'jump', 'land', 'ko', 'roundStart', 'fight', 'timeUp', 'select'];
    expect(Object.keys(SFX).sort()).toEqual(types.sort());
    for (const recipe of Object.values(SFX).flat()) {
      expect(['square', 'triangle', 'sawtooth', 'noise']).toContain(recipe.wave);
      expect(recipe.duration).toBeGreaterThan(0);
      expect(recipe.duration).toBeLessThanOrEqual(1);
      expect(recipe.gain).toBeGreaterThan(0);
      expect(recipe.gain).toBeLessThanOrEqual(1);
      expect(recipe.freqStart).toBeGreaterThan(0);
      expect(recipe.freqEnd).toBeGreaterThan(0);
    }
  });

  it('constructs one context lazily and schedules a connected oscillator and envelope', async () => {
    const { audio, contexts } = createHarness();
    audio.play('hit');
    expect(contexts).toHaveLength(0);
    await audio.resume();
    await audio.resume();
    expect(contexts).toHaveLength(1);
    const ctx = contexts[0];
    expect(ctx.resume).toHaveBeenCalledTimes(2);
    expect(ctx.createOscillator).not.toHaveBeenCalled();
    audio.play('hit');
    const source = ctx.createOscillator.mock.results[0].value;
    const envelope = ctx.createGain.mock.results[0].value;
    const recipe = SFX.hit;
    expect(source.type).toBe(recipe.wave);
    expect(source.frequency.setValueAtTime).toHaveBeenCalledWith(recipe.freqStart, 10);
    expect(source.frequency.linearRampToValueAtTime).toHaveBeenCalledWith(recipe.freqEnd, 10 + recipe.duration);
    expect(envelope.gain.setValueAtTime).toHaveBeenCalledWith(recipe.gain, 10);
    expect(envelope.gain.exponentialRampToValueAtTime).toHaveBeenCalledWith(0.0001, 10 + recipe.duration);
    expect(source.connect).toHaveBeenCalledWith(envelope);
    expect(envelope.connect).toHaveBeenCalledWith(ctx.destination);
    expect(source.start).toHaveBeenCalledWith(10);
    expect(source.stop).toHaveBeenCalledWith(10 + recipe.duration);
  });

  it('ignores muted and unknown sounds, then allows unmuting', async () => {
    const { audio, contexts } = createHarness();
    audio.setMuted(true);
    await audio.resume();
    for (const type of Object.keys(SFX)) audio.play(type);
    audio.setMuted(false);
    for (const type of ['unknown', 'toString', '__proto__']) {
      expect(() => audio.play(type)).not.toThrow();
    }
    const ctx = contexts[0];
    for (const method of ['createOscillator', 'createGain', 'createBuffer', 'createBufferSource']) {
      expect(ctx[method]).not.toHaveBeenCalled();
    }
    audio.play('hit');
    expect(ctx.createOscillator).toHaveBeenCalledTimes(1);
  });

  it('plays each event type, including noise, and reuses deterministic noise samples', async () => {
    const { audio, contexts } = createHarness();
    await audio.resume();
    playEvents(audio, [{ type: 'jump' }, { type: 'land' }]);
    const ctx = contexts[0];
    expect(ctx.createOscillator).toHaveBeenCalledTimes(1);
    expect(ctx.createBufferSource).toHaveBeenCalledTimes(1);
    for (const source of [ctx.createOscillator.mock.results[0].value, ctx.createBufferSource.mock.results[0].value]) {
      expect(source.start).toHaveBeenCalledTimes(1);
      expect(source.stop).toHaveBeenCalledTimes(1);
    }
    audio.play('whiff');
    audio.play('land');
    expect(ctx.createBuffer).toHaveBeenCalledTimes(1);
    const buffer = ctx.createBuffer.mock.results[0].value;
    for (const { value: source } of ctx.createBufferSource.mock.results) {
      expect(source.buffer).toBe(buffer);
    }
    const other = createHarness();
    await other.audio.resume();
    other.audio.play('land');
    const samples = buffer.getChannelData(0);
    expect(samples).toEqual(other.contexts[0].createBuffer.mock.results[0].value.getChannelData(0));
    expect(samples.some(value => value !== 0)).toBe(true);
    expect(samples.every(value => value >= -1 && value <= 1)).toBe(true);
  });

  it('schedules KO notes in sequence using cumulative durations', async () => {
    const { audio, contexts } = createHarness();
    await audio.resume();
    audio.play('ko');
    const sources = contexts[0].createOscillator.mock.results;
    expect(sources).toHaveLength(SFX.ko.length);
    let start = contexts[0].currentTime;
    SFX.ko.forEach((recipe, index) => {
      expect(sources[index].value.start).toHaveBeenCalledWith(start);
      start += recipe.duration;
      expect(sources[index].value.stop).toHaveBeenCalledWith(start);
    });
  });
});
