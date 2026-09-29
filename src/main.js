import { WIDTH, HEIGHT } from './game/constants.js';

const canvas = document.getElementById('game');
const context = canvas.getContext('2d');

context.fillStyle = 'black';
context.fillRect(0, 0, WIDTH, HEIGHT);
context.fillStyle = 'white';
context.font = '24px monospace';
context.textAlign = 'center';
context.textBaseline = 'middle';
context.fillText('Pixel Fighter', WIDTH / 2, HEIGHT / 2);
