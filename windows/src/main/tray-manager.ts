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
  public onUpdate: (() => void) | null = null;
  private readonly version: string;
  private badgeOn = false;

  constructor(version = '') {
    this.version = version;
    const icon = nativeImage.createFromBuffer(generateTrayIconPng(false));
    this.tray = new Tray(icon);
    this.tray.setToolTip('ClaudePet');
    this.rebuildMenu([], null);
  }

  rebuildMenu(sessions: TraySessionEntry[], updateVersion: string | null): void {
    // 트레이 아이콘 배지 — 업데이트 있으면 우상단 점 (메뉴 안 열어도 항상 보임)
    const wantBadge = updateVersion !== null;
    if (wantBadge !== this.badgeOn) {
      this.badgeOn = wantBadge;
      this.tray.setImage(nativeImage.createFromBuffer(generateTrayIconPng(wantBadge)));
      this.tray.setToolTip(wantBadge ? `ClaudePet — ${S.menuUpdate} v${updateVersion}` : 'ClaudePet');
    }

    const menu = new Menu();
    menu.append(new MenuItem({ label: `Claude Pet v${this.version || '?'} (Windows)`, enabled: false }));
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

    // 업데이트 있으면 트레이 메뉴에도 실행 항목 (배지 보고 트레이 눌렀을 때 헤매지 않게)
    if (updateVersion !== null) {
      menu.append(new MenuItem({
        label: `🎉 v${updateVersion} ${S.menuUpdate}`,
        click: () => this.onUpdate?.(),
      }));
      menu.append(new MenuItem({ type: 'separator' }));
    }

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
