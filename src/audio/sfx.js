// Web Audio durations are in seconds; simulation events carry no audio state.
export const SFX = {
  hit: { wave: 'square', freqStart: 180, freqEnd: 45, duration: 0.12, gain: 0.25 },
  block: { wave: 'triangle', freqStart: 320, freqEnd: 120, duration: 0.1, gain: 0.2 },
  whiff: { wave: 'noise', freqStart: 1, freqEnd: 1, duration: 0.08, gain: 0.12 },
  jump: { wave: 'square', freqStart: 180, freqEnd: 540, duration: 0.15, gain: 0.12 },
  land: { wave: 'noise', freqStart: 1, freqEnd: 1, duration: 0.09, gain: 0.18 },
  ko: [
    { wave: 'sawtooth', freqStart: 300, freqEnd: 150, duration: 0.25, gain: 0.2 },
    { wave: 'sawtooth', freqStart: 150, freqEnd: 40, duration: 0.45, gain: 0.2 },
  ],
  roundStart: { wave: 'triangle', freqStart: 440, freqEnd: 660, duration: 0.3, gain: 0.2 },
  fight: { wave: 'square', freqStart: 440, freqEnd: 880, duration: 0.2, gain: 0.2 },
  timeUp: { wave: 'triangle', freqStart: 660, freqEnd: 220, duration: 0.4, gain: 0.2 },
  select: { wave: 'square', freqStart: 660, freqEnd: 880, duration: 0.07, gain: 0.12 },
};

export function createAudio(AudioCtor) {
  let context;
  let muted = false;
  let noiseBuffer;

  function getNoiseBuffer() {
    if (!noiseBuffer) {
      noiseBuffer = context.createBuffer(1, context.sampleRate, context.sampleRate);
      const samples = noiseBuffer.getChannelData(0);
      let seed = 1;
      for (let i = 0; i < samples.length; i += 1) {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        samples[i] = (seed / 4294967296) * 2 - 1;
      }
    }
    return noiseBuffer;
  }

  function play(type) {
    if (!context || muted || !Object.hasOwn(SFX, type)) return;
    const recipes = Array.isArray(SFX[type]) ? SFX[type] : [SFX[type]];
    let start = context.currentTime;
    for (const recipe of recipes) {
      const end = start + recipe.duration;
      let source;
      if (recipe.wave === 'noise') {
        source = context.createBufferSource();
        source.buffer = getNoiseBuffer();
      } else {
        source = context.createOscillator();
        source.type = recipe.wave;
        source.frequency.setValueAtTime(recipe.freqStart, start);
        source.frequency.linearRampToValueAtTime(recipe.freqEnd, end);
      }
      const envelope = context.createGain();
      envelope.gain.setValueAtTime(recipe.gain, start);
      envelope.gain.exponentialRampToValueAtTime(0.0001, end);
      source.connect(envelope);
      envelope.connect(context.destination);
      source.start(start);
      source.stop(end);
      start = end;
    }
  }

  return {
    resume() {
      if (!context) context = new AudioCtor();
      return context.resume();
    },
    play,
    setMuted(value) {
      muted = Boolean(value);
    },
  };
}

export function playEvents(audio, events) {
  for (const event of events) audio.play(event.type);
}
