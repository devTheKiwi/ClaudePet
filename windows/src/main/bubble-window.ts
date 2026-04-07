/**
 * Speech bubble 윈도우 — SpeechBubble.swift 포팅
 */

import { BrowserWindow, screen } from 'electron';
import * as path from 'path';

const MIN_WIDTH = 80;
const MAX_WIDTH = 280;

export type PetSkin = 'basic' | 'spring';

export class BubbleWindow {
  public readonly window: BrowserWindow;
  private ready: boolean = false;
  private dismissTimer: NodeJS.Timeout | null = null;
  private currentText: string = '';
  private isPersistent: boolean = false;

  constructor() {
    this.window = new BrowserWindow({
      width: 200,
      height: 60,
      transparent: true,
      frame: false,
      resizable: false,
      movable: false,
      minimizable: false,
      maximizable: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      hasShadow: false,
      focusable: false,
      show: false,
      webPreferences: {
        preload: path.join(__dirname, '..', 'preload', 'bubble-preload.js'),
        contextIsolation: true,
        nodeIntegration: false,
      },
    });

    this.window.setAlwaysOnTop(true, 'screen-saver');
    this.window.setIgnoreMouseEvents(true);
    this.window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });

    this.window.loadFile(path.join(__dirname, '..', 'renderer', 'bubble.html'));
    this.window.webContents.on('did-finish-load', () => {
      this.ready = true;
    });
  }

  show(text: string, anchorX: number, anchorY: number, skin: PetSkin = 'basic', persistent: boolean = false): void {
    this.currentText = text;
    this.isPersistent = persistent;

    // 텍스트 크기 추정 (정확하진 않지만 합리적)
    const charWidth = 7.5; // 평균 (한글은 약간 더 큼)
    const lineHeight = 16;
    const padding = 24;
    const tailHeight = 10;

    let estimatedWidth = Math.min(text.length * charWidth + padding, MAX_WIDTH);
    estimatedWidth = Math.max(estimatedWidth, MIN_WIDTH);

    const lines = Math.max(1, Math.ceil((text.length * charWidth) / (estimatedWidth - padding)));
    const estimatedHeight = lines * lineHeight + padding + tailHeight;

    const w = Math.round(estimatedWidth);
    const h = Math.round(estimatedHeight);

    // 위치: 펫 머리 위에 정렬, 화면 경계 체크
    let x = Math.round(anchorX - w / 2);
    let y = Math.round(anchorY - h);

    const display = screen.getPrimaryDisplay();
    const workArea = display.workArea;
    if (x < workArea.x) x = workArea.x;
    if (x + w > workArea.x + workArea.width) x = workArea.x + workArea.width - w;
    if (y < workArea.y) y = workArea.y;

    this.window.setBounds({ x, y, width: w, height: h });
    this.sendShow(text, skin);

    this.window.setOpacity(0);
    this.window.showInactive();

    // 페이드인
    this.fadeTo(1, 300);

    // 자동 사라짐
    if (this.dismissTimer) clearTimeout(this.dismissTimer);
    if (!persistent) {
      this.dismissTimer = setTimeout(() => this.dismiss(), 4000);
    }
  }

  /** 펫 따라다니기 (위치만 갱신) */
  updatePosition(anchorX: number, anchorY: number): void {
    if (!this.window.isVisible()) return;
    const b = this.window.getBounds();
    let x = Math.round(anchorX - b.width / 2);
    const y = Math.round(anchorY - b.height);

    const display = screen.getPrimaryDisplay();
    const workArea = display.workArea;
    if (x < workArea.x) x = workArea.x;
    if (x + b.width > workArea.x + workArea.width) x = workArea.x + workArea.width - b.width;

    this.window.setBounds({ x, y, width: b.width, height: b.height });
  }

  forceDismiss(): void {
    if (this.dismissTimer) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = null;
    }
    this.dismiss();
  }

  isVisible(): boolean {
    return !this.window.isDestroyed() && this.window.isVisible();
  }

  private dismiss(): void {
    if (this.window.isDestroyed()) return;
    this.fadeTo(0, 500, () => {
      if (!this.window.isDestroyed()) this.window.hide();
    });
  }

  private fadeTo(target: number, duration: number, done?: () => void): void {
    if (this.window.isDestroyed()) return;
    let start: number;
    try {
      start = this.window.getOpacity();
    } catch {
      return;
    }
    const startTime = Date.now();
    const tick = () => {
      if (this.window.isDestroyed()) return;
      try {
        const t = Math.min(1, (Date.now() - startTime) / duration);
        const v = start + (target - start) * t;
        this.window.setOpacity(v);
        if (t < 1) {
          setTimeout(tick, 16);
        } else if (done) {
          done();
        }
      } catch {
        // 윈도우가 destroy 된 경우 무시
      }
    };
    tick();
  }

  private sendShow(text: string, skin: PetSkin): void {
    if (!this.ready) {
      // 살짝 기다렸다 다시 시도
      setTimeout(() => this.sendShow(text, skin), 50);
      return;
    }
    if (this.window.isDestroyed()) return;
    this.window.webContents.send('bubble:show', { text, skin });
  }

  destroy(): void {
    // pending dismiss 타이머 정리 — 안 그러면 destroy 후에 발동해서 에러
    if (this.dismissTimer) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = null;
    }
    if (!this.window.isDestroyed()) {
      this.window.close();
    }
  }
}
