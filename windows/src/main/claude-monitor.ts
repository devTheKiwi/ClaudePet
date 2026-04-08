/**
 * ClaudeMonitor.swift 포팅
 *
 * %TEMP%\claudepet-*.json 파일을 스캔해 세션 상태를 추적한다.
 * Hook 스크립트가 이 파일들을 작성한다.
 */

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

export type ClaudeStatus = 'notRunning' | 'idle' | 'working' | 'waitingForPermission';

export interface SessionInfo {
  sessionId: string;
  status: ClaudeStatus;
  cwd: string;
  tool: string;
  timestamp: number;
}

// Stale timeout — 비정상 종료된 세션 정리용.
// 정상 exit 시엔 SessionEnd hook 이 즉시 temp 파일을 지우므로 이 값과 무관.
// 강제 종료 / 크래시 / PC 종료 등 비정상 케이스만 이 timeout 으로 정리.
// 맥 버전(ClaudeMonitor.swift)과 동일하게 2시간으로 맞춤.
const STALE_TIMEOUT_SEC = 7200; // 2시간

export class ClaudeMonitor {
  private tmpDir: string;

  constructor() {
    this.tmpDir = os.tmpdir();
  }

  /** 현재 살아있는 세션 목록 반환 */
  checkSessions(): SessionInfo[] {
    const sessions: SessionInfo[] = [];

    let files: string[];
    try {
      files = fs.readdirSync(this.tmpDir);
    } catch {
      return sessions;
    }

    const now = Math.floor(Date.now() / 1000);

    for (const file of files) {
      if (!file.startsWith('claudepet-') || !file.endsWith('.json')) continue;

      const filePath = path.join(this.tmpDir, file);
      let data: any;
      try {
        let content = fs.readFileSync(filePath, 'utf8');
        // PowerShell 5.x 의 Out-File -Encoding utf8 은 BOM 을 붙임 → 제거
        if (content.charCodeAt(0) === 0xFEFF) {
          content = content.slice(1);
        }
        data = JSON.parse(content);
      } catch {
        continue;
      }

      const event: string = data.status || '';
      const sessionId: string = data.session_id || '';
      const ts: number = data.ts || 0;
      if (!sessionId || !ts) continue;

      // session_id 추출 실패한 케이스는 무시 + 정리
      if (sessionId === 'unknown') {
        try {
          fs.unlinkSync(filePath);
        } catch {}
        continue;
      }

      // 오래된 파일 정리 (Claude Code 가 SessionEnd 안 보내고 죽은 경우)
      if (now - ts > STALE_TIMEOUT_SEC) {
        try {
          fs.unlinkSync(filePath);
        } catch {}
        continue;
      }

      const cwd: string = data.cwd || '';
      const tool: string = data.tool || 'none';

      let status: ClaudeStatus;
      switch (event) {
        case 'UserPromptSubmit':
        case 'PreToolUse':
        case 'PostToolUse':
        case 'SubagentStop':
          status = 'working';
          break;
        case 'Stop':
          status = 'idle';
          break;
        case 'PermissionRequest':
          status = 'waitingForPermission';
          break;
        case 'SessionStart':
          status = 'idle';
          break;
        default:
          status = 'idle';
          break;
      }

      sessions.push({ sessionId, status, cwd, tool, timestamp: ts });
    }

    return sessions;
  }

  /**
   * Claude Desktop 프로세스가 실행 중인지 확인.
   *
   * 주의: Windows 에선 Claude Code CLI 도 `claude.exe` 라는 이름으로 떠있다.
   * 따라서 단순 프로세스 이름 매칭만으론 구분이 안 된다.
   *
   * 해결: PowerShell 로 ExecutablePath 까지 가져와서, 경로에
   * "AnthropicClaude" (Desktop 설치 경로) 가 포함된 프로세스만 카운트.
   *
   *   - Claude Code CLI:  C:\Users\...\npm\node_modules\@anthropic-ai\claude-code\...
   *   - Claude Desktop:   C:\Users\...\AppData\Local\AnthropicClaude\Claude.exe (또는 Program Files)
   */
  async isDesktopRunning(): Promise<boolean> {
    return new Promise((resolve) => {
      const { execFile } = require('child_process');
      const ps = `Get-CimInstance Win32_Process -Filter "name='claude.exe'" | ` +
                 `Where-Object { $_.ExecutablePath -like '*AnthropicClaude*' -or $_.ExecutablePath -like '*Anthropic Claude*' } | ` +
                 `Select-Object -First 1 -ExpandProperty ProcessId`;
      execFile(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ps],
        { windowsHide: true },
        (err: any, stdout: string) => {
          if (err) {
            resolve(false);
            return;
          }
          const trimmed = (stdout || '').trim();
          resolve(/^\d+/.test(trimmed));
        }
      );
    });
  }
}
