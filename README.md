# Pixel Fighter

A browser pixel-art fighting game for two players sharing one keyboard. Built
with vanilla JavaScript, HTML5 Canvas and Vite, with Vietnamese UI, procedural
sprites and synthesized Web Audio sounds. Matches are best of three rounds.

## Run

```sh
npm install
npm run dev
```

Open http://localhost:5173, or open forwarded port **5173** in GitHub Codespaces.
Press Enter to start; the first key press or pointer press enables audio.

```sh
npm test
npm run build
```

Tests run headlessly in Node with Vitest. The production build goes to `dist/`.

## Controls

| Action | Player 1 | Player 2 |
| --- | --- | --- |
| Move left / right | A / D | Left / Right arrows |
| Jump | W | Up arrow |
| Crouch | S | Down arrow |
| Punch | F | Comma (,) |
| Kick | G | Period (.) |
| Block | H | Slash (/) |

Enter or Space starts/confirms. Escape returns to the title during a fight.
M toggles mute. Confirm on the victory screen after one second to return to the title.

## Layout

- `src/main.js`: browser wiring and animation loop.
- `src/game/`: pure input, fighter, combat, match and scene logic.
- `src/input/`: keyboard event adapter.
- `src/render/`: procedural sprites, HUD, screens and Canvas renderer.
- `src/audio/`: synthesized sound effects.
- `tests/`: unit tests, headless match integration and rendering mocks.
