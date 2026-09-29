import { FPS } from './constants.js';
import { createMatch, stepMatch } from './match.js';

export function createGame() {
  return { scene: 'title', sceneFrame: 0, match: null, muted: false };
}

export function stepGame(game, { p1, p2, menu }) {
  const previousScene = game.scene;
  let events = [];

  if (menu.mutePressed) game.muted = !game.muted;

  switch (game.scene) {
    case 'title':
      if (menu.startPressed) {
        game.match = createMatch();
        game.scene = 'fight';
        events.push({ type: 'select' });
      }
      break;
    case 'fight':
      if (menu.backPressed) {
        game.scene = 'title';
        game.match = null;
      } else {
        events = stepMatch(game.match, [p1, p2]);
        if (game.match.phase === 'over') game.scene = 'victory';
      }
      break;
    case 'victory':
      // Allow confirmation after one second on the victory screen.
      if (game.sceneFrame >= FPS && menu.startPressed) {
        game.scene = 'title';
        events.push({ type: 'select' });
      }
      break;
  }

  game.sceneFrame = game.scene === previousScene ? game.sceneFrame + 1 : 0;
  return events;
}
