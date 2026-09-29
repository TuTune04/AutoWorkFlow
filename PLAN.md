# PLAN — Pixel Fighter (browser, local versus)

## Project overview

A 2D pixel-art arcade fighting game for two players sharing one keyboard. Runs in the browser on an
HTML5 Canvas, written in vanilla JavaScript (ES modules), served/bundled by Vite, unit-tested by Vitest.
No external image/audio/font assets: sprites are generated procedurally in code, sounds are synthesized
with Web Audio. UI text is Vietnamese (code, comments, identifiers and tests are English).

TEST_CMD: npm test --silent

### Stack
- Node + npm. Dev dependencies only: `vite`, `vitest` (install latest via `npm install -D vite vitest`, commit `package-lock.json`).
- `package.json` has `"type": "module"` and scripts:
  - `"dev": "vite"` (config binds to `0.0.0.0`, port 5173, so GitHub Codespaces port forwarding works)
  - `"build": "vite build"`, `"preview": "vite preview"`
  - `"test": "vitest run --reporter=dot"`
- Vitest runs in the `node` environment (no jsdom). Tests live in `tests/` and are named `*.test.js`.

### Layout
```
index.html               # <canvas id="game">, loads /src/main.js
vite.config.js           # server host 0.0.0.0, allowedHosts; vitest config (environment node)
src/
  main.js                # browser entry: wires keyboard, loop, game, renderer, audio (NOT unit-tested)
  game/                  # PURE game logic — no DOM, no window, no canvas, no audio
    constants.js         # all tuning numbers
    rect.js              # boxes, overlap, local->world conversion
    input.js             # key bindings + pure input snapshot reading
    moves.js             # attack frame data
    fighter.js           # fighter state + per-frame update (movement, attacks, stun)
    physics.js           # pushbox separation, facing
    combat.js            # hitbox vs hurtbox resolution, damage, block
    match.js             # rounds, timer, KO/time-over, best-of-3
    game.js              # scenes: title -> fight -> victory
    loop.js              # fixed-timestep accumulator
    strings.js           # Vietnamese UI text
  input/keyboard.js      # DOM keyboard listener (thin adapter, not unit-tested)
  render/
    sprites.js           # procedural pixel sprites (pure data)
    hud.js               # pure HUD layout math
    renderer.js          # draws everything to a CanvasRenderingContext2D
    screens.js           # title + victory screens
  audio/sfx.js           # Web Audio synth; AudioContext constructor is injected
tests/                   # Vitest tests; tests/helpers/ for mocks
```

### Conventions (all tasks must follow)
- Everything under `src/game/`, `src/render/sprites.js` and `src/render/hud.js` is pure: must not reference
  `window`, `document`, `requestAnimationFrame`, `AudioContext` or canvas APIs. Deterministic (no `Math.random`).
- Game state is plain JSON-like objects (no classes). Update functions mutate the state passed in and
  **return an array of event objects** (`{ type: 'hit' | 'block' | 'whiff' | 'jump' | 'land' | 'ko' | 'roundStart' | 'fight' | 'timeUp' | 'select', ... }`)
  used by audio/rendering. Functions with nothing to report return `[]` when they are documented to return events.
- Simulation runs at a fixed 60 steps/second; all durations are in **frames**, velocities in pixels/frame.
- Coordinates: logical canvas 384×216, origin top-left, y grows downward. A fighter's `(x, y)` is the
  **center of its feet**; `y === GROUND_Y` means standing on the ground.
- `facing` is `1` (looking right) or `-1` (looking left).
- Local boxes `{ x, y, w, h }` are relative to the fighter's feet; `x` is measured in the facing direction.
- Named exports only. Keep each file focused; import constants from `constants.js` rather than hardcoding.
- Every task must leave `npm test --silent` green. Do not modify tests from earlier tasks unless the task says so.

### Controls (event.code values)
| Action | Player 1 | Player 2 |
|---|---|---|
| left / right | `KeyA` / `KeyD` | `ArrowLeft` / `ArrowRight` |
| jump (up) | `KeyW` | `ArrowUp` |
| crouch (down) | `KeyS` | `ArrowDown` |
| punch | `KeyF` | `Comma` |
| kick | `KeyG` | `Period` |
| block | `KeyH` | `Slash` |

Menus: `Enter` or `Space` = start/confirm, `Escape` = back to title, `KeyM` = toggle mute.

---

## Task 1: Project skeleton, Vite/Vitest config, constants

Files to create/modify:
- `package.json` (as described in overview; name `pixel-fighter`, `"private": true`)
- `vite.config.js`: `import { defineConfig } from 'vite'`; `server: { host: '0.0.0.0', port: 5173, allowedHosts: ['.app.github.dev'] }`,
  `preview` same host/port; `test: { environment: 'node', include: ['tests/**/*.test.js'] }`.
- `index.html`: `<html lang="vi">`, title `Pixel Fighter`, black body background, a centered `<canvas id="game" width="384" height="216">`
  scaled up with CSS (`width: min(100vw, 1152px)`, `image-rendering: pixelated`), `<script type="module" src="/src/main.js">`.
- `src/main.js`: placeholder that fills the canvas black and writes "Pixel Fighter" (will be replaced in Task 15).
- `src/game/constants.js` exporting exactly:
  `WIDTH = 384, HEIGHT = 216, FPS = 60, GROUND_Y = 184, STAGE_LEFT = 16, STAGE_RIGHT = 368,
  GRAVITY = 0.5, JUMP_VELOCITY = -9, WALK_SPEED = 2, AIR_SPEED = 2.5, FRICTION = 0.8,
  MAX_HEALTH = 100, ROUND_TIME = 60 (seconds), ROUNDS_TO_WIN = 2,
  FIGHTER_WIDTH = 24, FIGHTER_HEIGHT = 56, CROUCH_HEIGHT = 36,
  P1_START_X = 128, P2_START_X = 256, INTRO_FRAMES = 90, ROUND_END_FRAMES = 150`.
- `.gitignore`: keep existing lines, append `node_modules/` and `dist/`.
- `tests/constants.test.js`.

Acceptance criteria:
- `npm install` succeeds; `npm test --silent` runs and passes.
- Test asserts `WIDTH === 384`, `HEIGHT === 216`, `FPS === 60`, `STAGE_LEFT < P1_START_X < P2_START_X < STAGE_RIGHT`,
  `CROUCH_HEIGHT < FIGHTER_HEIGHT`, `GROUND_Y < HEIGHT`.
- Test imports `vite.config.js` and asserts `server.host === '0.0.0.0'` and `test.environment === 'node'`.
- `npm run dev` starts Vite listening on 0.0.0.0:5173 (manual check, not tested).

## Task 2: Box geometry helpers

Files: `src/game/rect.js`, `tests/rect.test.js`.

Implement:
- `rectsOverlap(a, b)` for world rects `{x, y, w, h}` (x/y = top-left). Touching edges (`a.x + a.w === b.x`) is **not** overlap.
- `toWorldBox(fighter, box)`: fighter has `{x, y, facing}`; returns world rect.
  If `facing === 1`: `left = fighter.x + box.x`; if `facing === -1`: `left = fighter.x - box.x - box.w`. `top = fighter.y + box.y`. Same `w`, `h`.
- `overlapX(a, b)`: horizontal overlap amount in pixels (0 if none).

Acceptance criteria (tests):
- Overlap true for intersecting rects, false for separated and edge-touching rects, true for containment.
- `toWorldBox({x:100,y:184,facing:1},{x:10,y:-40,w:20,h:10})` → `{x:110,y:144,w:20,h:10}`;
  same with `facing:-1` → `{x:70,y:144,w:20,h:10}`.
- `overlapX` returns 5 for `{x:0,w:10}` vs `{x:5,w:10}` (with overlapping y), 0 when separated.

## Task 3: Input mapping

Files: `src/game/input.js`, `src/input/keyboard.js`, `tests/input.test.js`.

Implement in `src/game/input.js` (pure):
- `KEY_BINDINGS = { p1: {left,right,up,down,punch,kick,block}, p2: {...} }` using the codes from the Controls table.
- `MENU_KEYS = { start: ['Enter','Space'], back: ['Escape'], mute: ['KeyM'] }`.
- `neutralInput()` → `{ left:false, right:false, up:false, down:false, punch:false, kick:false, block:false, punchPressed:false, kickPressed:false }`.
- `readPlayerInput(held, prevHeld, bindings)`: `held`/`prevHeld` are `Set`s of codes. Held booleans for each action;
  `punchPressed`/`kickPressed` true only if the key is in `held` and not in `prevHeld`.
  If both left and right are held, both are reported false.
- `readMenuInput(held, prevHeld)` → `{ startPressed, backPressed, mutePressed }` (edge-triggered).
- `ALL_BOUND_CODES`: array of every code above (used to `preventDefault`).

Implement in `src/input/keyboard.js` (DOM adapter, no tests):
- `createKeyboard(target = window)` → `{ held: Set, snapshot() }`. Listens to `keydown`/`keyup` (uses `event.code`),
  calls `preventDefault()` for codes in `ALL_BOUND_CODES`, clears `held` on `blur`.
  `snapshot()` returns `{ held: new Set(held), prevHeld }` and stores the current set as next `prevHeld`.

Acceptance criteria (tests, only `src/game/input.js` is imported):
- P1 holding `KeyD` → `right:true`; P2 bindings ignore `KeyD`.
- `punchPressed` true on first frame `KeyF` is held, false on the next frame while still held; `punch` stays true.
- Left+right together → both false.
- `readMenuInput` detects `Space` press edge and `Escape` press edge.
- `ALL_BOUND_CODES` contains `Slash`, `Enter`, and has no duplicates.

## Task 4: Fighter state and movement

Files: `src/game/fighter.js`, `tests/fighter-movement.test.js`.

Implement:
- `createFighter(playerIndex, x, facing)` → `{ playerIndex, x, y: GROUND_Y, vx: 0, vy: 0, facing, health: MAX_HEALTH,
  state: 'idle', stateFrame: 0, onGround: true, crouching: false, attack: null, usedAirAttack: false, stun: 0 }`.
  `state` ∈ `'idle' | 'walk' | 'crouch' | 'jump' | 'attack' | 'block' | 'hitstun' | 'blockstun' | 'ko'`.
- `updateFighter(f, input)` → events array. This task handles only non-attack behaviour (attacks come in Task 5; ignore `punchPressed`/`kickPressed` for now):
  - Grounded & actionable (`idle`/`walk`/`crouch`/`block`): priority `block` (sets `state:'block'`, `crouching = input.down`, `vx = 0`)
    → `up` (jump: `vy = JUMP_VELOCITY`, `vx = dir * AIR_SPEED` where dir is -1/0/1 from left/right, `onGround=false`, `state:'jump'`, emit `{type:'jump', player}`)
    → `down` (`state:'crouch'`, `crouching:true`, `vx = 0`) → left/right (`state:'walk'`, `vx = ±WALK_SPEED`) → `idle` (`vx = 0`).
  - `hitstun`/`blockstun`: decrement `stun`; `vx *= FRICTION`; when `stun` reaches 0 → `idle` (or `jump` if airborne).
  - `ko`: ignore input, `vx *= FRICTION`.
  - Integration every frame: `x += vx`; if airborne `vy += GRAVITY; y += vy`; when `y >= GROUND_Y` while airborne:
    `y = GROUND_Y`, `vy = 0`, `onGround = true`, `usedAirAttack = false`, state `jump` → `idle`, emit `{type:'land', player}`.
  - Clamp `x` to `[STAGE_LEFT + FIGHTER_WIDTH/2, STAGE_RIGHT - FIGHTER_WIDTH/2]`.
  - `stateFrame` resets to 0 on state change, else increments.
- `setState(f, state)` helper (exported) implementing the `stateFrame` rule.

Acceptance criteria (tests):
- Holding right for 10 frames moves x by `+20`; holding left near the left wall never goes below `STAGE_LEFT + 12`.
- Jump: after pressing up, fighter leaves ground, reaches apex (vy crosses 0), lands back at exactly `GROUND_Y` within 60 frames,
  emits one `jump` and one `land` event, and state returns to `idle`.
- Crouch sets `crouching:true`, `vx:0`; releasing down returns to `idle` with `crouching:false`.
- Block held while also holding right → `state:'block'`, `vx:0`.
- Fighter in `hitstun` with `stun:3` ignores input and becomes `idle` after 3 updates.

## Task 5: Move data and attack states

Files: `src/game/moves.js`, modify `src/game/fighter.js`, `tests/moves.test.js`.

Implement `MOVES` in `moves.js` (object keyed by id; each move: `{ id, startup, active, recovery, damage, hitstun, blockstun, knockback, level, hitbox }`,
`level` ∈ `'high' | 'mid' | 'low'`, `hitbox` local box):
| id | startup | active | recovery | damage | hitstun | blockstun | knockback | level | hitbox {x,y,w,h} |
|---|---|---|---|---|---|---|---|---|---|
| standPunch | 4 | 3 | 8 | 6 | 14 | 8 | 3 | mid | 10,-46,22,10 |
| standKick | 7 | 4 | 14 | 10 | 18 | 10 | 5 | mid | 8,-30,30,12 |
| crouchPunch | 4 | 3 | 8 | 5 | 12 | 7 | 2 | mid | 10,-28,20,8 |
| crouchKick | 8 | 4 | 16 | 9 | 18 | 10 | 4 | low | 6,-10,32,10 |
| airPunch | 4 | 6 | 6 | 7 | 14 | 8 | 3 | high | 8,-42,20,12 |
| airKick | 5 | 8 | 6 | 9 | 16 | 9 | 4 | high | 6,-26,26,14 |

Also export `moveTotalFrames(move)`, `attackPhase(attack)` → `'startup' | 'active' | 'recovery' | 'done'` based on `attack.frame`
(frames `0..startup-1` startup, next `active` frames active, next `recovery` frames recovery, then done),
and `selectMove(button, crouching, airborne)` (`button` = `'punch'|'kick'`).

Extend `updateFighter`:
- Grounded & actionable: `punchPressed`/`kickPressed` (punch wins if both) have priority **over** block/jump/crouch/walk:
  start `attack = { moveId, frame: 0, hasHit: false }`, `state:'attack'`, `vx = 0`, `crouching` kept if `down` held.
- Airborne in `jump` state with `usedAirAttack === false`: press starts an air move, sets `usedAirAttack = true`; horizontal velocity is kept.
- In `attack`: `attack.frame++` each update; when phase is `done` → `attack = null`, state `idle` (grounded, `crouch` if `down` held) or `jump` (airborne).
  Landing during an air attack cancels it (`attack = null`, `idle`).
- Emit `{type:'whiff', player, moveId}` on the frame an attack starts (sound of swinging).

Acceptance criteria (tests):
- `MOVES` has exactly the 6 ids above; every numeric field is a positive integer (hitbox x/w/h positive, y negative).
- `attackPhase` for standPunch: frame 0..3 startup, 4..6 active, 7..14 recovery, 15 done.
- Pressing punch while standing → `standPunch`; with down held → `crouchPunch`; while airborne kick → `airKick`.
- After the update that starts a standPunch (frame 0), exactly `moveTotalFrames(standPunch)` (15) further updates return the fighter to `idle`; input is ignored meanwhile (holding right doesn't move).
- Only one air attack per jump; `usedAirAttack` resets on landing.

## Task 6: Pushboxes and facing

Files: `src/game/physics.js`, `tests/physics.test.js`.

Implement:
- `hurtbox(f)`: local box `{x:-12, y:-FIGHTER_HEIGHT, w:24, h:FIGHTER_HEIGHT}` or when `crouching` `{x:-12, y:-CROUCH_HEIGHT, w:24, h:CROUCH_HEIGHT}`; export also `worldHurtbox(f)` (uses `toWorldBox`).
- `separateFighters(a, b)`: pushbox = world hurtbox. If they overlap (use `rectsOverlap`), push apart along x by the overlap amount,
  half each; if one would exceed the stage clamp, the other takes the remainder. If `a.x === b.x`, push `a` left and `b` right.
  Result must not overlap and both stay within the clamp range from Task 4.
- `updateFacing(a, b)`: for each fighter that is `onGround` and in `idle`, `walk`, `crouch` or `block`, set `facing` toward the other
  (`1` if other.x > self.x, `-1` if smaller, unchanged if equal).

Acceptance criteria (tests):
- Two fighters at x=100 and x=110 end up non-overlapping, centered around 105.
- One fighter pinned at left wall clamp and other overlapping: wall fighter doesn't move, other is pushed fully.
- A jumping fighter directly above the other (vertical boxes not overlapping) is not pushed.
- `updateFacing` flips an idle fighter after crossing sides but does not flip one in `attack` or airborne.

## Task 7: Combat resolution (hits, blocks, KO)

Files: `src/game/combat.js`, `tests/combat.test.js`.

Implement:
- `activeHitbox(f)`: world rect of the current move's hitbox if `attackPhase === 'active'` and `!attack.hasHit`, else `null`.
- `canBlock(defender, level)`: defender `state` is `'block'` or `'blockstun'`; standing (`crouching:false`) blocks `high`/`mid`,
  crouching blocks `mid`/`low`.
- `resolveHits(a, b)` → events. Compute both directions against the state **before** applying either result (trades allowed).
  For attacker→defender where hitbox overlaps `worldHurtbox(defender)` and defender is not `ko`:
  - Set `attacker.attack.hasHit = true`.
  - Blocked: `state:'blockstun'`, `stun = move.blockstun`, `vx = attacker.facing * move.knockback / 2`, no damage;
    event `{type:'block', attacker, defender, moveId}` (player indices).
  - Hit: `health = max(0, health - damage)`, `attack = null`, `state:'hitstun'`, `stun = move.hitstun`,
    `vx = attacker.facing * move.knockback`; event `{type:'hit', attacker, defender, moveId, damage}`.
    If health reaches 0: `state:'ko'`, event `{type:'ko', player: defender}`; if airborne keeps falling.

Acceptance criteria (tests; build fighters with `createFighter` and set fields directly):
- standPunch at active frame 4 with fighters 30px apart hits: defender health 94, `hitstun` 14, pushed away from attacker.
- Same attack during startup frame 2 or at 80px apart → no events.
- A move hits only once even if active for multiple frames.
- Standing block stops `standKick` (mid) and `airKick` (high) but not `crouchKick` (low); crouch block stops `crouchKick` but not `airKick`.
- Both fighters in active standPunch facing each other in range → both take damage (trade), two `hit` events.
- Health 5 hit by standKick → health 0, state `ko`, `ko` event emitted.

## Task 8: Round and match logic

Files: `src/game/match.js`, `tests/match.test.js`.

Implement:
- `createMatch()` → `{ round: 1, wins: [0, 0], phase: 'intro', phaseFrame: 0, timer: ROUND_TIME * FPS, fighters: [f1, f2],
  roundWinner: null, matchWinner: null }` with `f1 = createFighter(0, P1_START_X, 1)`, `f2 = createFighter(1, P2_START_X, -1)`.
  `roundWinner`/`matchWinner` ∈ `null | 0 | 1 | 'draw'`. `phase` ∈ `'intro' | 'fight' | 'roundEnd' | 'over'`.
- `timerSeconds(match)` → `Math.ceil(timer / FPS)`.
- `stepMatch(match, inputs)` (`inputs = [p1Input, p2Input]`) → events. Per frame:
  - `intro`: emit `{type:'roundStart', round}` at phaseFrame 0; fighters updated with `neutralInput()`; after `INTRO_FRAMES` → `fight`, emit `{type:'fight'}`.
  - `fight`: `updateFighter` both with their inputs → `separateFighters` → `resolveHits` → `updateFacing`; `timer--`.
    Round ends if any fighter is `ko` (winner = the other; both KO → `'draw'`) or `timer` hits 0
    (emit `{type:'timeUp'}`; higher health wins, equal → `'draw'`). On end: set `roundWinner`, increment `wins` of the winner
    (on `'draw'` increment **both**), phase `roundEnd`, add `{type:'roundEnd', winner, reason: 'ko' | 'time'}`.
  - `roundEnd`: fighters updated with neutral input (KO'd ones settle); after `ROUND_END_FRAMES`: if any `wins >= ROUNDS_TO_WIN` →
    phase `over`, `matchWinner` = the player with `ROUNDS_TO_WIN` wins (both → `'draw'`), emit `{type:'matchOver', winner}`;
    else `round++`, reset fighters/timer (`resetRound(match)` exported), phase `intro`.
  - `over`: no-op.
  - `phaseFrame` resets on each phase change.

Acceptance criteria (tests; drive by calling `stepMatch` in loops, setting fighter health directly where needed):
- Starts in `intro`; after `INTRO_FRAMES - 1` calls it is still `intro`, after the `INTRO_FRAMES`-th call it is `fight`; inputs are ignored during intro. The same counting rule applies to `ROUND_END_FRAMES`.
- Timer counts down only in `fight`; `timerSeconds` is 60 at fight start.
- Setting P2 health to 0 via a hit (or setting state `ko`) ends round with `roundWinner === 0`, `wins [1,0]`.
- Time-over with P1 health 50, P2 40 → P1 wins round; equal health → draw, `wins [1,1]`.
- After two P1 round wins the match reaches `over` with `matchWinner === 0`; after round 1 fighters are reset to full health and start positions, `round === 2`.
- Draw when score is 1–1 → both reach 2 → `matchWinner === 'draw'`.

## Task 9: Game scene state machine

Files: `src/game/game.js`, `tests/game.test.js`.

Implement:
- `createGame()` → `{ scene: 'title', sceneFrame: 0, match: null, muted: false }`.
- `stepGame(game, frameInput)` where `frameInput = { p1, p2, menu }` (`menu` from `readMenuInput`) → events.
  - Any scene: `menu.mutePressed` toggles `muted`.
  - `title`: `menu.startPressed` → `match = createMatch()`, scene `fight`, emit `{type:'select'}`.
  - `fight`: `menu.backPressed` → scene `title`, `match = null`. Otherwise `stepMatch(match, [p1, p2])` and return its events;
    when `match.phase === 'over'` → scene `victory`.
  - `victory`: ignore start for the first 60 frames; afterwards `startPressed` → scene `title`, emit `{type:'select'}`.
  - `sceneFrame` resets on scene change, else increments.

Acceptance criteria (tests):
- Title ignores player inputs; `startPressed` goes to `fight` with a fresh match.
- In `fight`, events from `stepMatch` are returned (e.g. `roundStart` on first step).
- Forcing `match.phase = 'over'` then stepping → scene `victory`; start within 60 frames is ignored, after 60 returns to `title`.
- `mutePressed` toggles `muted` in every scene; Escape during fight returns to title.

## Task 10: Fixed-timestep loop

Files: `src/game/loop.js`, `tests/loop.test.js`.

Implement `createFixedStepper(step, { stepMs = 1000 / FPS, maxSteps = 5 } = {})` → `{ advance(elapsedMs) }`.
`advance` adds `elapsedMs` to an accumulator and calls `step()` while accumulator ≥ `stepMs`, at most `maxSteps` times
(excess accumulated time beyond that is discarded); returns number of steps run. Negative or NaN elapsed counts as 0.

Acceptance criteria (tests):
- `advance(1000/60)` runs 1 step; `advance(8)` twice runs 0 then 1.
- `advance(1000)` runs exactly 5 steps and the following `advance(0)` runs 0 (backlog discarded).
- `advance(-5)` and `advance(NaN)` run 0 steps.

## Task 11: Procedural pixel sprites

Files: `src/render/sprites.js`, `tests/sprites.test.js`.

Implement (pure, no canvas):
- `SPRITE_W = 48`, `SPRITE_H = 64`; anchor = feet center at `(24, 63)`.
- `FIGHTER_STYLES`: two palettes, index 0 = transparent. Player 0 "Rồng": red gi, black hair, white headband, skin, dark outline.
  Player 1 "Hổ": blue gi, brown hair, yellow headband, skin, dark outline. Each style: `{ name, palette: [null, '#rrggbb', ...] }` (same palette length/order of roles:
  `[transparent, outline, skin, hair, headband, gi, giShadow, belt, shoes]`).
- `POSES = ['idle0','idle1','walk0','walk1','crouch','jump','punch','kick','crouchPunch','crouchKick','airPunch','airKick','block','crouchBlock','hit','ko']`.
- `generateSprite(pose)` → `{ w, h, data: Uint8Array(w*h) }` of palette role indices, drawn facing right by filling rectangles
  for head, hair/headband, torso, belt, arms, legs, shoes with pose-specific limb offsets (punch: arm extended right; kick: leg extended right;
  crouch poses: body ≤ 38px tall; ko: body lying horizontally near the bottom; hit: leaning back). Add a 1px outline pass
  (transparent pixels 4-adjacent to body pixels become outline).
- `spriteToRuns(sprite)` → array of `{ x, y, len, c }` horizontal runs of equal non-zero index (for fast `fillRect`), cached per pose.
- `poseForFighter(f)`: `ko`→`ko`, `hitstun`→`hit`, `block`/`blockstun`→`block` or `crouchBlock`, `attack`→ move-to-pose
  (`standPunch`→`punch`, `standKick`→`kick`, others same name), airborne→`jump`, `crouch`→`crouch`,
  `walk`→`walk0`/`walk1` alternating every 8 frames of `stateFrame`, else `idle0`/`idle1` alternating every 20 frames.

Acceptance criteria (tests):
- Every pose generates a 48×64 sprite with at least 200 non-zero pixels and indices < palette length.
- Both styles have 9 palette entries, valid hex colors, and differ in the gi color.
- Rightmost non-zero column of `punch` > that of `idle0` by ≥ 8; `kick` likewise.
- Topmost non-zero row of `crouch` is ≥ 18 rows lower than `idle0`; `ko` height (rows with pixels) ≤ 20.
- `spriteToRuns` total `len` equals non-zero pixel count.
- `poseForFighter` returns expected poses for representative fighter states.

## Task 12: HUD layout and fight renderer

Files: `src/render/hud.js`, `src/render/renderer.js`, `tests/helpers/mockCtx.js`, `tests/hud.test.js`, `tests/renderer.test.js`.

Implement `hud.js` (pure):
- `HEALTH_BAR = { y: 12, h: 10, w: 144, p1x: 16, p2x: 224 }`.
- `healthBarFill(playerIndex, health)` → `{x, y, w, h}` of the filled part: `w = Math.round(144 * health / MAX_HEALTH)`;
  P1 fill is right-aligned (drains toward the left edge), P2 fill left-aligned.
- `timerText(match)` → two-digit string of `timerSeconds` (`'60'`, `'05'`).
- `roundPips(playerIndex, wins)` → array of `ROUNDS_TO_WIN` `{x, y, filled}` placed under that player's bar.

Implement `renderer.js`:
- `drawFight(ctx, match)`: sky/background gradient-free flat colors, pixel floor at `GROUND_Y`, simple procedural backdrop
  (e.g. rooftop silhouettes via `fillRect`), fighters via `spriteToRuns` (mirror horizontally when `facing === -1`; draw at `Math.round`ed positions),
  health bars (dark back, yellow/red fill), timer, round pips, player names from `FIGHTER_STYLES`, and phase overlays
  using `strings.js` placeholders: import text from `src/game/strings.js` — create that file in this task with at least
  `STRINGS.round(n)` → `` `HIỆP ${n}` ``, `STRINGS.fight` = `'ĐÁNH!'`, `STRINGS.ko` = `'K.O.'`, `STRINGS.timeUp` = `'HẾT GIỜ!'`, `STRINGS.draw` = `'HÒA!'`.
- Only uses ctx methods: `fillStyle`, `fillRect`, `font`, `textAlign`, `textBaseline`, `fillText`, `save`, `restore`, `globalAlpha`.

`tests/helpers/mockCtx.js`: `createMockCtx()` returning an object with those methods/properties that records calls in `ctx.calls` (`[name, ...args]`).

Acceptance criteria (tests):
- `healthBarFill(0, 100)` → `{x:16,y:12,w:144,h:10}`; `healthBarFill(0, 50)` → `x:88,w:72`; `healthBarFill(1, 50)` → `x:224,w:72`; health 0 → `w:0`.
- `timerText` returns `'60'` at round start and `'05'` when 5 seconds remain.
- `roundPips(0, 1)` has 2 pips, first filled.
- `drawFight(mockCtx, createMatch())` runs without throwing, calls `fillRect` > 50 times and `fillText` with `'HIỆP 1'` during intro.
- With P1 facing -1 the fighter's drawn runs are mirrored (min x of fighter fillRects differs vs facing 1).

## Task 13: Title and victory screens + Vietnamese strings

Files: modify `src/game/strings.js`, create `src/render/screens.js`, modify `src/render/renderer.js`, `tests/screens.test.js`.

Add to `STRINGS`: `title: 'PIXEL FIGHTER'`, `subtitle: 'Đối kháng 2 người'`, `pressStart: 'Nhấn ENTER để bắt đầu'`,
`controlsP1: 'P1: W A S D  ·  F đấm  ·  G đá  ·  H đỡ'`, `controlsP2: 'P2: Phím mũi tên  ·  , đấm  ·  . đá  ·  / đỡ'`,
`muteHint: 'M: tắt/bật âm thanh  ·  ESC: về menu'`, `wins(name)` → `` `${name} CHIẾN THẮNG!` ``, `backToTitle: 'Nhấn ENTER để về màn hình chính'`.

Implement:
- `drawTitle(ctx, game)`: dark background, big title, subtitle, both fighters' `idle` sprites facing each other,
  blinking `pressStart` (visible when `Math.floor(game.sceneFrame / 30) % 2 === 0`), controls and mute hint.
- `drawVictory(ctx, game)`: winner name (from `FIGHTER_STYLES`) with `STRINGS.wins`, or `STRINGS.draw`; final score `wins[0] - wins[1]`;
  winner sprite in `idle0`; `backToTitle` shown after 60 frames.
- `render(ctx, game)` in `renderer.js`: dispatches on `game.scene` to `drawTitle` / `drawFight` / `drawVictory`;
  draws the text marker `'TẮT TIẾNG'` in a corner when `game.muted`.

Acceptance criteria (tests, with the mock ctx):
- `render` on a title game calls `fillText` with `'PIXEL FIGHTER'`; `pressStart` appears at sceneFrame 0 and not at 30.
- Victory with `matchWinner: 1` draws `'Hổ CHIẾN THẮNG!'`; with `'draw'` draws `'HÒA!'`.
- `render` on a fight scene delegates to `drawFight` (e.g. draws the timer text `'60'` after intro).
- Muted game draws `'TẮT TIẾNG'`.

## Task 14: Sound effects (Web Audio)

Files: `src/audio/sfx.js`, `tests/sfx.test.js`.

Implement:
- `SFX`: map event type → synth recipe `{ wave: 'square'|'triangle'|'sawtooth'|'noise', freqStart, freqEnd, duration, gain }` for
  `hit`, `block`, `whiff`, `jump`, `land`, `ko`, `roundStart`, `fight`, `timeUp`, `select`. `ko` may be an array of recipes played in sequence (offset by duration).
- `createAudio(AudioCtor)`: lazily constructs the context on first `resume()` (browsers require a user gesture);
  `play(type)` does nothing if context missing, muted, or type unknown; otherwise creates an oscillator (or a noise
  `AudioBufferSourceNode` built once from a deterministic LCG, not `Math.random`) → `GainNode` with exponential/linear ramp
  from `gain` to ~0 over `duration`, frequency ramp `freqStart → freqEnd`, connected to `destination`, started/stopped.
- `playEvents(audio, events)` plays each event's type. `setMuted(bool)`.

Acceptance criteria (tests, with a fake `AudioContext` class in the test recording `createOscillator`, `createGain`, `createBuffer`, `createBufferSource` calls; fake nodes have `connect`, `start`, `stop`, and `frequency`/`gain` params with `setValueAtTime`, `linearRampToValueAtTime`, `exponentialRampToValueAtTime`):
- Every event type listed has a recipe with positive duration ≤ 1 and gain in (0, 1].
- Before `resume()`, `play('hit')` creates no nodes; after, it creates and starts a node.
- Muted → no nodes created; unknown type → no nodes, no throw.
- `playEvents` with `[{type:'jump'},{type:'land'}]` starts 2 sources.
- The noise buffer is created at most once across multiple plays.

## Task 15: Browser wiring and README

Files: replace `src/main.js`, create `README.md`, `tests/main-imports.test.js`.

Implement `src/main.js`:
- Get `#game` canvas, `ctx.imageSmoothingEnabled = false`.
- `keyboard = createKeyboard(window)`, `game = createGame()`, `audio = createAudio(window.AudioContext || window.webkitAudioContext)`.
- On first `keydown`/`pointerdown`, call `audio.resume()`.
- `stepper = createFixedStepper(() => { const { held, prevHeld } = keyboard.snapshot(); const frameInput = { p1: readPlayerInput(held, prevHeld, KEY_BINDINGS.p1), p2: readPlayerInput(held, prevHeld, KEY_BINDINGS.p2), menu: readMenuInput(held, prevHeld) }; const events = stepGame(game, frameInput); audio.setMuted(game.muted); playEvents(audio, events); })`.
- `requestAnimationFrame` loop: `stepper.advance(now - last)`, then `render(ctx, game)`.
- Keep `main.js` free of game rules (only wiring).

`README.md` (English, short): what it is, `npm install`, `npm run dev` (open forwarded port 5173 in Codespaces), `npm test`, controls table, project layout summary.

Acceptance criteria:
- `tests/main-imports.test.js` imports every module under `src/game/`, `src/render/` and `src/audio/` in the node environment
  without errors (proves no DOM access at import time), and simulates a full headless match: `createGame()`, start pressed,
  then P1 repeatedly pressing punch (alternate pressed/not-pressed frames) while walking right, P2 idle, for up to 60 × 60 × 3 frames
  → game reaches scene `victory` with `match.matchWinner === 0`. Also calls `render(createMockCtx(), game)` every 100 frames without throwing.
- `npm run build` succeeds (manual/CI check).
- Manual: `npm run dev`, open the forwarded port — title screen shows, Enter starts a fight, both players can move/attack/block, sounds play, match ends on victory screen.
