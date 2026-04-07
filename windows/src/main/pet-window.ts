/**
 * Pet 윈도우 — 투명 always-on-top BrowserWindow
 * PetWindow.swift 포팅
 */

import { BrowserWindow, screen } from 'electron';
import * as path from 'path';

export interface PetWindowOptions {
  sessionId: string;
  colorIndex: number;
  startX?: number;
}

const PET_WIDTH = 96;
const PET_HEIGHT = 64;

export class PetWindow {
  public readonly window: BrowserWindow;
  public readonly sessionId: string;
  public colorIndex: number;
  private ready: boolean = false;
  private pendingState: any = {};

  constructor(options: PetWindowOptions) {
    this.sessionId = options.sessionId;
    this.colorIndex = options.colorIndex;

    const display = screen.getPrimaryDisplay();
    const workArea = display.workArea; // 작업표시줄 제외 영역

    const x = options.startX !== undefined
      ? Math.round(options.startX)
      : Math.round(workArea.x + workArea.width / 2 - PET_WIDTH / 2);

    // 작업표시줄 바로 위 (workArea 가 작업표시줄을 제외하므로 maxY 가 펫 위)
    const y = workArea.y + workArea.height - PET_HEIGHT;

    this.window = new BrowserWindow({
      width: PET_WIDTH,
      height: PET_HEIGHT,
      x,
      y,
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
        preload: path.join(__dirname, '..', 'preload', 'pet-preload.js'),
        contextIsolation: true,
        nodeIntegration: false,
      },
    });

    this.window.setAlwaysOnTop(true, 'screen-saver');
    this.window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });

    this.window.loadFile(path.join(__dirname, '..', 'renderer', 'pet.html'));

    this.window.webContents.on('did-finish-load', () => {
      this.ready = true;
      // 초기 색상 전달
      this.sendState({ colorIndex: this.colorIndex, ...this.pendingState });
      this.pendingState = {};
      this.window.show();
    });
  }

  /** 상태를 렌더러로 전송 */
  sendState(data: any): void {
    if (!this.ready) {
      Object.assign(this.pendingState, data);
      return;
    }
    if (this.window.isDestroyed()) return;
    this.window.webContents.send('pet:state', data);
  }

  /** 펫 행동 상태 강제 변경 */
  setPetState(state: 'idle' | 'walkingLeft' | 'walkingRight' | 'jumping' | 'happy' | 'excited'): void {
    if (this.window.isDestroyed()) return;
    this.window.webContents.send('pet:set-state', state);
  }

  /** 위치 이동 (렌더러에서 dx 받았을 때) */
  moveBy(dx: number): void {
    if (this.window.isDestroyed()) return;
    const display = screen.getPrimaryDisplay();
    const workArea = display.workArea;
    const bounds = this.window.getBounds();

    let newX = bounds.x + Math.round(dx);
    const minX = workArea.x;
    const maxX = workArea.x + workArea.width - PET_WIDTH;

    let bumpedEdge: 'left' | 'right' | null = null;
    if (newX <= minX) {
      newX = minX;
      bumpedEdge = 'left';
    } else if (newX >= maxX) {
      newX = maxX;
      bumpedEdge = 'right';
    }

    const newY = workArea.y + workArea.height - PET_HEIGHT;
    this.window.setBounds({ x: newX, y: newY, width: PET_WIDTH, height: PET_HEIGHT });

    // 가장자리 부딪히면 반대 방향으로 전환
    if (bumpedEdge === 'left') this.setPetState('walkingRight');
    else if (bumpedEdge === 'right') this.setPetState('walkingLeft');
  }

  /**
   * 사용자 드래그 — y 도 자유롭게 (작업표시줄 고정 안 함).
   * 다음 자동 walking 사이클에 다시 작업표시줄 위로 떨어진다.
   */
  dragBy(dx: number, dy: number): void {
    if (this.window.isDestroyed()) return;
    const display = screen.getPrimaryDisplay();
    const workArea = display.workArea;
    const bounds = this.window.getBounds();

    let newX = bounds.x + Math.round(dx);
    let newY = bounds.y + Math.round(dy);

    // 화면 경계 제한
    const minX = workArea.x;
    const maxX = workArea.x + workArea.width - PET_WIDTH;
    const minY = workArea.y;
    const maxY = workArea.y + workArea.height - PET_HEIGHT;
    if (newX < minX) newX = minX;
    if (newX > maxX) newX = maxX;
    if (newY < minY) newY = minY;
    if (newY > maxY) newY = maxY;

    this.window.setBounds({ x: newX, y: newY, width: PET_WIDTH, height: PET_HEIGHT });
  }

  /** 펫 윈도우 위치 + 크기 */
  getCenter(): { x: number; y: number } {
    const b = this.window.getBounds();
    return { x: b.x + b.width / 2, y: b.y };
  }

  destroy(): void {
    if (!this.window.isDestroyed()) {
      this.window.close();
    }
  }
}
