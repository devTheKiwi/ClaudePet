// HTML 파일을 src/renderer/ → dist/renderer/ 로 복사
const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '..', 'src', 'renderer');
const dst = path.join(__dirname, '..', 'dist', 'renderer');

fs.mkdirSync(dst, { recursive: true });
for (const f of fs.readdirSync(src)) {
  if (f.endsWith('.html') || f.endsWith('.css')) {
    fs.copyFileSync(path.join(src, f), path.join(dst, f));
    console.log('  copied', f);
  }
}
