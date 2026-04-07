/**
 * 파일 로거 — Windows Electron 에선 stdout 이 안 잡혀서 디버깅이 어렵다.
 *
 * 정책: 평소엔 거의 안 쓰고, 에러/경고만 기록.
 * 일반 동작 (세션 추가/제거 등) 은 로그 안 남김 → 사용자 디스크에 부담 X.
 * 매 write 마다 사이즈 체크해서 256KB 넘으면 자동 truncate (무한 누적 방지).
 */

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

const LOG_DIR = path.join(os.homedir(), '.claudepet-windows');
const LOG_PATH = path.join(LOG_DIR, 'app.log');
const MAX_SIZE = 256 * 1024; // 256KB 넘으면 truncate

let initialized = false;

function init(): void {
  if (initialized) return;
  initialized = true;
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
  } catch {}
}

function rotateIfNeeded(): void {
  try {
    if (!fs.existsSync(LOG_PATH)) return;
    const stat = fs.statSync(LOG_PATH);
    if (stat.size > MAX_SIZE) {
      fs.truncateSync(LOG_PATH, 0);
    }
  } catch {}
}

function write(level: string, args: any[]): void {
  init();
  rotateIfNeeded();
  const ts = new Date().toISOString();
  const msg = args
    .map((a) => {
      if (a instanceof Error) return `${a.message}\n${a.stack}`;
      if (typeof a === 'object') {
        try { return JSON.stringify(a); } catch { return String(a); }
      }
      return String(a);
    })
    .join(' ');
  const line = `[${ts}] ${level} ${msg}\n`;
  try {
    fs.appendFileSync(LOG_PATH, line, 'utf8');
  } catch {}
}

export const log = {
  /** 거의 쓰지 않음 — 앱 시작/종료 같은 한 번만 일어나는 이벤트만 */
  info: (...args: any[]) => write('INFO ', args),
  warn: (...args: any[]) => write('WARN ', args),
  error: (...args: any[]) => write('ERROR', args),
  path: LOG_PATH,
};

/** uncaughtException / unhandledRejection 을 로그로 남기기 */
export function installCrashHandlers(): void {
  process.on('uncaughtException', (err) => {
    log.error('uncaughtException:', err);
  });
  process.on('unhandledRejection', (reason) => {
    log.error('unhandledRejection:', reason);
  });
}
