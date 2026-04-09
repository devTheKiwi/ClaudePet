/**
 * 시스템 트레이 아이콘 + 메뉴.
 * AppDelegate.swift 의 setupStatusBar / rebuildStatusMenu 포팅.
 */

import { Tray, Menu, MenuItem, nativeImage, app } from 'electron';
import { generateTrayIconPng } from './icon-gen';
import type { ClaudeStatus } from './claude-monitor';
import * as S from './strings';

export interface TraySessionEntry {
  sessionId: string;
  cwd: string;
  status: ClaudeStatus;
}

export class TrayManager {
  public readonly tray: Tray;
  public onQuit: (() => void) | null = null;

  constructor() {
    const iconBuffer = generateTrayIconPng();
    const icon = nativeImage.createFromBuffer(iconBuffer);
    this.tray = new Tray(icon);
    this.tray.setToolTip('ClaudePet');
    this.rebuildMenu([]);
  }

  rebuildMenu(sessions: TraySessionEntry[]): void {
    const menu = new Menu();
    menu.append(new MenuItem({ label: 'Claude Pet v2.4.0 (Windows)', enabled: false }));
    menu.append(new MenuItem({ type: 'separator' }));

    if (sessions.length === 0) {
      menu.append(new MenuItem({ label: S.menuNoSessions, enabled: false }));
    } else {
      const sorted = [...sessions].sort((a, b) => a.sessionId.localeCompare(b.sessionId));
      for (const s of sorted) {
        const dir = lastPathComponent(s.cwd);
        const icon = statusIcon(s.status);
        menu.append(new MenuItem({
          label: `${icon} ${dir || 'Claude'}`,
          enabled: false,
        }));
      }
    }

    menu.append(new MenuItem({ type: 'separator' }));
    menu.append(new MenuItem({
      label: S.menuQuit,
      click: () => {
        this.onQuit?.();
        app.quit();
      },
    }));

    this.tray.setContextMenu(menu);
  }

  destroy(): void {
    this.tray.destroy();
  }
}

function statusIcon(status: ClaudeStatus): string {
  switch (status) {
    case 'working': return '🔵';
    case 'waitingForPermission': return '🟡';
    case 'idle': return '🟢';
    case 'notRunning': return '⚫';
  }
}

function lastPathComponent(p: string): string {
  if (!p) return '';
  const norm = p.replace(/\\/g, '/');
  const parts = norm.split('/').filter(Boolean);
  return parts[parts.length - 1] || '';
}
