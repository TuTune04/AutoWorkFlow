# Progress Log

## Task 1: Project skeleton, Vite/Vitest config, constants
- Created the Vite/Vitest project skeleton with npm scripts and a dependency lockfile.
- Added the Vietnamese HTML page, pixelated canvas styling, and title placeholder.
- Exported all required game constants and added five constants/configuration tests.
- Preserved existing ignore rules and added node_modules/ and dist/.
- Verified npm test --silent, the production build, and the development server on port 5173.

## Task 2: Box geometry helpers
- Implemented pure rectangle overlap, local-to-world box conversion, and horizontal overlap helpers.
- Added tests for intersections, separation, edge contact, containment, and both facing directions.
- Kept all existing tests unchanged and limited implementation to Task 2.
- Verified npm test --silent passes: 19 tests across 2 test files.

## Task 3: Input mapping
- Added pure player and menu input mappings with all bound keyboard codes.
- Implemented neutral input, attack and menu press edges, and opposing-direction cancellation.
- Added the DOM keyboard adapter with default prevention, blur clearing, and independent frame snapshots.
- Added input acceptance tests; npm test --silent passes all 33 tests across 3 files.

## Task 4: Fighter state and movement
- Added fighter creation and state transitions with per-frame state counters.
- Implemented walking, jumping, crouching, blocking, gravity, landing, and stage boundary clamping.
- Added stun recovery and KO friction while leaving attack behavior for a later task.
- Added movement tests covering input priorities, landing events, stun recovery, and state transitions.
- Ran npm test --silent successfully: all 48 tests passed across 4 test files.

## Task 5: Move data and attack states
- Added all six moves with their specified frame data, damage, stun, levels, and hitboxes.
- Added move selection, total duration, and attack phase helpers.
- Implemented ground and air attacks, input priority, whiff events, recovery, and landing cancellation.
- Added attack tests and updated only the permitted opposing-direction movement test.
- Verified npm test --silent passes: 58 tests across 5 files.

## Task 6: Pushboxes and facing
- Added standing and crouching hurtboxes with local-to-world conversion.
- Implemented horizontal pushbox separation with shared displacement, wall constraints, and deterministic ties.
- Added facing updates for grounded idle, walking, crouching, and blocking fighters.
- Added physics tests covering separation, walls, vertical clearance, hurtboxes, and facing restrictions.
- Verified npm test --silent passes: 6 test files and 85 tests.

## Task 7: Combat resolution (hits, blocks, KO)
- Implemented active hitboxes and stance-based blocking in combat.js.
- Added simultaneous hit resolution with damage, stun, knockback, single-hit enforcement, and KO events.
- Added combat tests covering trades, block levels, misses, and continued falling after airborne KO.
- Ran npm test --silent successfully: all 110 tests across 7 test files passed.

## Task 8: Round and match logic
- Added pure round and match logic with intro, fight, round-end, and over phases.
- Integrated fighter updates, collision separation, combat, facing, and fight-only timer countdown.
- Added KO and time-over scoring, draw handling, round resets, and match winner events.
- Added tests for exact phase timing, input suppression, combat events, resets, and match outcomes.
- Verified npm test --silent passes: 8 test files and 124 tests.

## Task 9: Game scene state machine
- Implemented the title, fight, and victory scene state machine with scene frame tracking.
- Added fresh match creation, match event forwarding, and a 60-frame victory confirmation delay.
- Added mute toggling in every scene and Escape handling during fights.
- Added scene transition, input forwarding, timing boundary, and event preservation tests.
- Verified npm test --silent passes: 133 tests across 9 test files.
