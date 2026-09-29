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
