// 빌드 시 256x256 앱 아이콘을 생성해 assets/icon.png 에 저장
// (electron-builder 가 인스톨러 / 시작메뉴 / 작업표시줄 아이콘으로 사용)

const fs = require('fs');
const path = require('path');
const { generateAppIconPng } = require('../dist/main/icon-gen');

const outDir = path.join(__dirname, '..', 'assets');
const outFile = path.join(outDir, 'icon.png');

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(outFile, generateAppIconPng());
console.log('  generated', outFile, fs.statSync(outFile).size, 'bytes');
