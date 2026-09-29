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
