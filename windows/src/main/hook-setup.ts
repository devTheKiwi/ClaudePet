/**
 * HookSetup.swift 포팅
 *
 * Windows 에서 Claude Code 와 연동하기 위해:
 *  1. %USERPROFILE%\.claude\hooks\claudepet-hook.ps1 (PowerShell 본체)
 *  2. %USERPROFILE%\.claude\hooks\claudepet-hook.cmd (cmd 래퍼)
 *  3. %USERPROFILE%\.claude\settings.json 에 hook 등록
 */

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { dialog } from 'electron';

const HOME = os.homedir();
const CLAUDE_DIR = path.join(HOME, '.claude');
const HOOK_DIR = path.join(CLAUDE_DIR, 'hooks');
const HOOK_PS1 = path.join(HOOK_DIR, 'claudepet-hook.ps1');
const HOOK_CMD = path.join(HOOK_DIR, 'claudepet-hook.cmd');
const SETTINGS_PATH = path.join(CLAUDE_DIR, 'settings.json');

// PowerShell 본체 — Claude Code 가 stdin 으로 JSON 을 넘겨주면
// 파싱해서 %TEMP%\claudepet-<sessionId>.json 에 상태를 기록한다.
//
// 주의: PowerShell 5.x 의 Out-File -Encoding utf8 은 BOM 을 붙임 →
// JSON.parse 가 실패하므로, [System.IO.File]::WriteAllText 로 BOM 없이 쓴다.
const HOOK_PS1_CONTENT = `param([string]$EventName)

$ErrorActionPreference = 'SilentlyContinue'

try {
    $jsonInput = [Console]::In.ReadToEnd()
    $data = $jsonInput | ConvertFrom-Json
} catch {
    $data = [pscustomobject]@{}
}

$sessionId = if ($data.session_id) { $data.session_id } else { '' }
# session_id 가 없으면 이상한 unknown 펫이 생기지 않게 그냥 종료
if ([string]::IsNullOrEmpty($sessionId)) { exit 0 }

$cwd = if ($data.cwd) { $data.cwd } else { '' }
$tool = if ($data.tool_name) { $data.tool_name } else { 'none' }
$ts = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())

$statusFile = Join-Path $env:TEMP ("claudepet-" + $sessionId + ".json")

if ($EventName -eq 'SessionEnd') {
    if (Test-Path $statusFile) {
        Remove-Item $statusFile -Force -ErrorAction SilentlyContinue
    }
} else {
    $status = [ordered]@{
        status     = $EventName
        tool       = $tool
        cwd        = $cwd
        session_id = $sessionId
        ts         = $ts
    }
    $json = $status | ConvertTo-Json -Compress
    # BOM 없는 UTF-8 로 작성 (Out-File -Encoding utf8 은 BOM 붙음)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($statusFile, $json, $utf8NoBom)
}
`;

// .cmd 래퍼 — settings.json 에 들어가는 진입점
const HOOK_CMD_CONTENT = `@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claudepet-hook.ps1" %*
`;

const EVENTS_WITH_MATCHER = ['PreToolUse', 'PostToolUse', 'PermissionRequest'];
const EVENTS_WITHOUT_MATCHER = ['SessionStart', 'SessionEnd', 'Stop', 'SubagentStop', 'UserPromptSubmit'];

export class HookSetup {
  /** 첫 실행 시 자동 설치 다이얼로그 */
  static async checkAndPrompt(): Promise<void> {
    if (fs.existsSync(HOOK_CMD)) return;
    if (!fs.existsSync(CLAUDE_DIR)) return;

    const response = await dialog.showMessageBox({
      type: 'info',
      title: 'Claude Code 연동',
      message: 'Claude Code 연동',
      detail:
        'Claude Code와 연동하면 작업 상태를 실시간으로 알려줘요!\n\n' +
        '- 작업 시작/완료 알림\n' +
        '- 권한 요청 알림\n' +
        '- 세션별 상태 표시\n\n' +
        '연동하시겠습니까?',
      buttons: ['연동하기', '나중에'],
      defaultId: 0,
      cancelId: 1,
    });

    if (response.response === 0) {
      const ok = HookSetup.installHooks();
      await dialog.showMessageBox({
        type: ok ? 'info' : 'warning',
        title: ok ? '연동 완료' : '연동 실패',
        message: ok ? '연동 완료!' : '연동 실패',
        detail: ok
          ? 'Claude Code와 연동되었습니다.\nClaude Code를 새로 시작하면 적용됩니다.'
          : 'Hook 설정 중 문제가 발생했습니다.',
        buttons: ['확인'],
      });
    }
  }

  /** Hook 파일 + settings.json 갱신 */
  static installHooks(): boolean {
    try {
      // 1. hook 디렉토리
      fs.mkdirSync(HOOK_DIR, { recursive: true });

      // 2. PowerShell + cmd 래퍼 작성
      fs.writeFileSync(HOOK_PS1, HOOK_PS1_CONTENT, { encoding: 'utf8' });
      fs.writeFileSync(HOOK_CMD, HOOK_CMD_CONTENT, { encoding: 'utf8' });

      // 3. settings.json 갱신
      return HookSetup.updateSettings();
    } catch (err) {
      console.error('installHooks failed:', err);
      return false;
    }
  }

  private static updateSettings(): boolean {
    try {
      let settings: any = {};
      if (fs.existsSync(SETTINGS_PATH)) {
        try {
          const raw = fs.readFileSync(SETTINGS_PATH, 'utf8');
          settings = JSON.parse(raw);
        } catch {
          settings = {};
        }
      } else {
        fs.mkdirSync(path.dirname(SETTINGS_PATH), { recursive: true });
      }

      const hooks = settings.hooks || {};
      // Windows 경로는 settings.json 안에선 escaped 백슬래시
      const cmdPath = HOOK_CMD;

      const upsertEvent = (event: string, withMatcher: boolean) => {
        const command = `"${cmdPath}" ${event}`;
        const hookEntry = { type: 'command', command };
        const existing = hooks[event];

        if (Array.isArray(existing)) {
          let added = false;
          for (const group of existing) {
            if (Array.isArray(group.hooks)) {
              const cmds = group.hooks.map((h: any) => h.command);
              if (!cmds.includes(command)) {
                group.hooks.push(hookEntry);
              }
              added = true;
              break;
            }
          }
          if (!added) {
            existing.push(withMatcher ? { matcher: '*', hooks: [hookEntry] } : { hooks: [hookEntry] });
          }
        } else {
          hooks[event] = withMatcher
            ? [{ matcher: '*', hooks: [hookEntry] }]
            : [{ hooks: [hookEntry] }];
        }
      };

      for (const event of EVENTS_WITH_MATCHER) upsertEvent(event, true);
      for (const event of EVENTS_WITHOUT_MATCHER) upsertEvent(event, false);

      settings.hooks = hooks;
      fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2), { encoding: 'utf8' });
      return true;
    } catch (err) {
      console.error('updateSettings failed:', err);
      return false;
    }
  }

  static isInstalled(): boolean {
    return fs.existsSync(HOOK_CMD);
  }
}
