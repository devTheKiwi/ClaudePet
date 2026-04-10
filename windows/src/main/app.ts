/**
 * App orchestration — AppDelegate.swift 의 핵심 로직 포팅.
 * 세션 관리 / 상태 동기화 / 클릭 핸들러 / 랜덤 말풍선 / 토큰 마일스톤 / Desktop 감지.
 */

import { app, ipcMain, Menu, MenuItem, screen } from 'electron';
import { PetWindow } from './pet-window';
import { BubbleWindow } from './bubble-window';
import { TrayManager, TraySessionEntry } from './tray-manager';
import { ClaudeMonitor, ClaudeStatus, SessionInfo } from './claude-monitor';
import { TokenTracker, formatTokens, totalTokens } from './token-tracker';
import { TimeTracker, UserSettings } from './time-tracker';
import { UpdateChecker } from './update-checker';
import { HookSetup } from './hook-setup';
import * as S from './strings';

interface PetSession {
  petWindow: PetWindow;
  bubble: BubbleWindow;
  colorIndex: number;
  lastStatus: ClaudeStatus;
  cwd: string;
  sessionStart: number;   // ms
  workingSeconds: number;
  lastTool: string;
  petMode: 'code' | 'desktop';
}

const PALETTE_NAMES = ['🟠', '🔵', '🟢', '🟣', '🩷', '🩵'];

export class App {
  private sessions = new Map<string, PetSession>();
  private monitor = new ClaudeMonitor();
  private tokenTracker = new TokenTracker();
  private timeTracker = new TimeTracker();
  private settings = new UserSettings();
  private updateChecker = new UpdateChecker();
  private tray!: TrayManager;
  private lastMinuteTrack = 0;
  private lastTokenMilestone = 0;
  private lastMilestoneDate = '';
  private desktopWasRunning = false;
  private desktopStartTime: number | null = null;

  async start(): Promise<void> {
    this.tray = new TrayManager();
    this.tray.onQuit = () => this.quit();

    // 첫 실행이면 자동 시작 기본 활성화
    if (this.settings.isFirstRun()) {
      this.settings.autoLaunch = true;
    }
    this.applyAutoLaunch();

    // 첫 실행 시 hook 설치 다이얼로그
    setTimeout(() => HookSetup.checkAndPrompt().catch(() => {}), 2000);

    // 기본 펫 (세션 없어도 항상 살아있음)
    this.spawnDefaultPet();

    // 업데이트 체크
    this.updateChecker.onResult = (msg) => {
      const first = this.sessions.values().next().value;
      if (first) this.showSpeech(first, msg);
    };
    this.updateChecker.checkOnLaunch();

    this.setupIpc();
    this.startMonitoring();
    this.scheduleRandomSpeech();
    this.startTimeTracking();
  }

  /** 자동 시작 설정을 OS 에 반영 (Windows: 레지스트리 Run 키) */
  private applyAutoLaunch(): void {
    try {
      app.setLoginItemSettings({
        openAtLogin: this.settings.autoLaunch,
        openAsHidden: false,
      });
    } catch (err) {
      console.error('setLoginItemSettings failed:', err);
    }
  }

  // ======================================================================
  // Pet spawning
  // ======================================================================

  private spawnDefaultPet(): void {
    const display = screen.getPrimaryDisplay();
    const startX = display.workArea.x + display.workArea.width / 2 - 32;

    const petWindow = new PetWindow({ sessionId: 'default', colorIndex: 0, startX });
    const bubble = new BubbleWindow();

    const session: PetSession = {
      petWindow,
      bubble,
      colorIndex: 0,
      lastStatus: 'notRunning',
      cwd: '',
      sessionStart: Date.now(),
      workingSeconds: 0,
      lastTool: '',
      petMode: 'code',
    };
    this.sessions.set('default', session);

    petWindow.sendState({
      colorIndex: 0,
      claudeStatus: 'notRunning',
      petMode: 'code',
      skin: this.settings.skin,
      showTimer: this.settings.showTimer,
    });

    setTimeout(() => {
      this.showSpeech(session, S.greeting);
    }, 1500);
  }

  private spawnPet(info: SessionInfo): void {
    const used = new Set(Array.from(this.sessions.values()).map((s) => s.colorIndex));
    const available: number[] = [];
    for (let i = 1; i < 6; i++) if (!used.has(i)) available.push(i);
    const colorIndex = available.length > 0
      ? available[Math.floor(Math.random() * available.length)]
      : 1 + Math.floor(Math.random() * 5);

    const petWindow = new PetWindow({ sessionId: info.sessionId, colorIndex });
    const bubble = new BubbleWindow();

    const session: PetSession = {
      petWindow,
      bubble,
      colorIndex,
      lastStatus: info.status,
      cwd: info.cwd,
      sessionStart: Date.now(),
      workingSeconds: 0,
      lastTool: '',
      petMode: 'code',
    };
    this.sessions.set(info.sessionId, session);

    petWindow.sendState({
      colorIndex,
      claudeStatus: info.status,
      petMode: 'code',
      skin: this.settings.skin,
      showTimer: this.settings.showTimer,
    });

    const dir = lastPathComponent(info.cwd);
    const colorName = PALETTE_NAMES[colorIndex] || '';
    this.showSpeech(session, `${colorName} ${dir || S.newSession} ${S.sessionStart}`);
  }

  // ======================================================================
  // Monitoring
  // ======================================================================

  private startMonitoring(): void {
    setInterval(() => this.syncSessions().catch(() => {}), 2000);
  }

  private async syncSessions(): Promise<void> {
    const liveInfos = this.monitor.checkSessions();
    const liveIds = new Set(liveInfos.map((i) => i.sessionId));

    // 사라진 세션 제거 (default / desktop 제외)
    for (const id of Array.from(this.sessions.keys())) {
      if (id === 'default' || id === 'desktop') continue;
      if (liveIds.has(id)) continue;

      const session = this.sessions.get(id)!;
      if (this.sessions.size <= 1) {
        // 마지막 하나 → notRunning 으로
        session.lastStatus = 'notRunning';
        session.petWindow.sendState({ claudeStatus: 'notRunning' });
        continue;
      }

      this.showSpeech(session, S.bye);
      this.sessions.delete(id);
      setTimeout(() => {
        session.petWindow.destroy();
        session.bubble.destroy();
      }, 2000);
    }

    // 세션 추가/업데이트
    for (const info of liveInfos) {
      const existing = this.sessions.get(info.sessionId);
      if (existing) {
        if (info.status !== existing.lastStatus) {
          this.handleStatusChange(existing.lastStatus, info.status, existing);
        }
        existing.lastStatus = info.status;
        existing.cwd = info.cwd;
        existing.petWindow.sendState({ claudeStatus: info.status });

        if (info.status === 'working' && info.tool !== 'none' && info.tool !== existing.lastTool) {
          existing.lastTool = info.tool;
          this.showSpeech(existing, S.toolMessage(info.tool));
        }
        if (info.status === 'waitingForPermission') {
          existing.petWindow.setPetState('jumping');
        }
      } else {
        // default 펫이 살아있으면 거기에 연결
        const def = this.sessions.get('default');
        if (def && this.sessions.size === 1) {
          this.sessions.delete('default');
          this.sessions.set(info.sessionId, def);
          def.lastStatus = info.status;
          def.cwd = info.cwd;
          def.petWindow.sendState({ claudeStatus: info.status });
          const dir = lastPathComponent(info.cwd);
          this.showSpeech(def, `${dir || S.newSession} ${S.sessionConnected}`);
        } else {
          this.spawnPet(info);
        }
      }
    }

    // 토큰 마일스톤
    this.checkTokenMilestones();

    // Desktop 감지
    await this.syncDesktop();

    // 트레이 갱신
    this.tray.rebuildMenu(this.snapshotForTray());
  }

  private snapshotForTray(): TraySessionEntry[] {
    return Array.from(this.sessions.entries()).map(([id, s]) => ({
      sessionId: id,
      cwd: s.cwd,
      status: s.lastStatus,
    }));
  }

  // ======================================================================
  // Status change → 펫 행동/말풍선
  // ======================================================================

  private handleStatusChange(oldS: ClaudeStatus, newS: ClaudeStatus, session: PetSession): void {
    if (oldS === 'waitingForPermission' && newS !== 'waitingForPermission') {
      session.bubble.forceDismiss();
    }

    switch (newS) {
      case 'working':
        if (oldS !== 'working') {
          this.showSpeech(session, S.workStarted);
          session.petWindow.setPetState('excited');
        }
        break;
      case 'waitingForPermission':
        this.showSpeech(session, S.permissionNeeded, true);
        session.petWindow.setPetState('jumping');
        break;
      case 'idle':
        if (oldS === 'working') {
          this.showSpeech(session, S.workDone);
          session.petWindow.setPetState('happy');
        }
        break;
      case 'notRunning':
        session.petWindow.setPetState('idle');
        break;
    }
  }

  // ======================================================================
  // Desktop process detection
  // ======================================================================

  private async syncDesktop(): Promise<void> {
    const isRunning = await this.monitor.isDesktopRunning();
    const desktopId = 'desktop';

    if (isRunning && !this.desktopWasRunning) {
      this.desktopStartTime = Date.now();
      if (!this.sessions.has(desktopId)) {
        const display = screen.getPrimaryDisplay();
        const startX = display.workArea.x + display.workArea.width / 2 + 60;
        const petWindow = new PetWindow({ sessionId: desktopId, colorIndex: 0, startX });
        const bubble = new BubbleWindow();
        petWindow.sendState({
          colorIndex: 0,
          claudeStatus: 'idle',
          petMode: 'desktop',
          skin: this.settings.skin,
          showTimer: this.settings.showTimer,
        });
        const session: PetSession = {
          petWindow,
          bubble,
          colorIndex: 0,
          lastStatus: 'idle',
          cwd: '',
          sessionStart: Date.now(),
          workingSeconds: 0,
          lastTool: '',
          petMode: 'desktop',
        };
        this.sessions.set(desktopId, session);
        this.showSpeech(session, S.desktopHello);
      }
    } else if (!isRunning && this.desktopWasRunning) {
      const session = this.sessions.get(desktopId);
      if (session) {
        const usedSecs = Math.floor((Date.now() - (this.desktopStartTime || Date.now())) / 1000);
        const mins = Math.floor(usedSecs / 60);
        const secs = usedSecs % 60;
        const timeText = S.formatDuration(mins, secs);
        this.showSpeech(session, S.desktopBye(timeText));

        this.sessions.delete(desktopId);
        setTimeout(() => {
          session.petWindow.destroy();
          session.bubble.destroy();
        }, 3000);
      }
      this.desktopStartTime = null;
    } else if (isRunning && this.desktopStartTime) {
      const session = this.sessions.get(desktopId);
      if (session) {
        const secs = Math.floor((Date.now() - this.desktopStartTime) / 1000);
        session.workingSeconds = secs;
        session.petWindow.sendState({ workingSeconds: secs });

        const mins = Math.floor(secs / 60);
        if (mins > 0 && mins % 30 === 0 && secs % 60 < 3) {
          const messages = S.desktopTimeAlert(mins);
          this.showSpeech(session, messages[Math.floor(Math.random() * messages.length)]);
        }
      }
    }

    this.desktopWasRunning = isRunning;
  }

  // ======================================================================
  // Token milestones
  // ======================================================================

  private checkTokenMilestones(): void {
    const today = this.tokenTracker.todayUsage();
    const totalK = Math.floor(totalTokens(today) / 1000);

    const milestones: [number, string][] = S.tokenMilestones;

    for (let i = milestones.length - 1; i >= 0; i--) {
      const [threshold, message] = milestones[i];
      if (totalK >= threshold && this.lastTokenMilestone < threshold) {
        this.lastTokenMilestone = threshold;
        const session =
          Array.from(this.sessions.values()).find((s) => s.petMode === 'code') ||
          this.sessions.values().next().value;
        if (session) this.showSpeech(session, message);
        break;
      }
    }

    // 날짜 바뀌면 리셋 (자정, 슬립 복귀 등 안전)
    const todayStr = new Date().toISOString().slice(0, 10);
    if (this.lastMilestoneDate !== todayStr) {
      this.lastTokenMilestone = 0;
      this.lastMilestoneDate = todayStr;
    }
  }

  // ======================================================================
  // Time tracking + bubble follow
  // ======================================================================

  private startTimeTracking(): void {
    setInterval(() => this.updateSessionTimes(), 1000);
    setInterval(() => this.updateBubblePositions(), 1000 / 15);
  }

  private updateSessionTimes(): void {
    for (const [id, session] of this.sessions) {
      if (id === 'desktop') continue; // syncDesktop 에서 처리

      if (session.lastStatus === 'working') {
        session.workingSeconds += 1;
        const totalMins = Math.floor(session.workingSeconds / 60);
        if (totalMins > this.lastMinuteTrack) {
          this.lastMinuteTrack = totalMins;
          this.timeTracker.addMinute();
        }
      }
      session.petWindow.sendState({
        workingSeconds: session.workingSeconds,
        showTimer: this.settings.showTimer,
      });
    }
  }

  private updateBubblePositions(): void {
    for (const session of this.sessions.values()) {
      if (!session.bubble.isVisible()) continue;
      const center = session.petWindow.getCenter();
      session.bubble.updatePosition(center.x, center.y - 4);
    }
  }

  // ======================================================================
  // Random speech
  // ======================================================================

  private scheduleRandomSpeech(): void {
    const interval = (45 + Math.random() * 45) * 1000;
    setTimeout(() => {
      this.triggerRandomSpeech();
      this.scheduleRandomSpeech();
    }, interval);
  }

  private triggerRandomSpeech(): void {
    if (this.sessions.size === 0) return;
    const arr = Array.from(this.sessions.values());
    const session = arr[Math.floor(Math.random() * arr.length)];
    if (!session.petWindow.window.isVisible()) return;

    const idleMessages = [...S.idleMessages, this.modelMessage()];
    const messages = session.lastStatus === 'working' ? S.workingMessages : idleMessages;
    this.showSpeech(session, messages[Math.floor(Math.random() * messages.length)]);
  }

  // ======================================================================
  // Model message (macOS modelMessage / formatModelName 포팅)
  // ======================================================================

  private modelMessage(): string {
    for (const [id] of this.sessions) {
      if (id === 'default' || id === 'desktop') continue;
      const model = this.tokenTracker.modelForSession(id);
      if (model) {
        const name = this.formatModelName(model);
        const reactions = S.modelReactions(name);
        return reactions[Math.floor(Math.random() * reactions.length)];
      }
    }
    const reactions = S.modelReactions('Claude');
    return reactions[Math.floor(Math.random() * reactions.length)];
  }

  private formatModelName(model: string): string {
    // "claude-opus-4-6" → "Opus 4.6"
    const parts = model.replace('claude-', '').split('-');
    if (parts.length >= 3) {
      const name = parts[0].charAt(0).toUpperCase() + parts[0].slice(1);
      return `${name} ${parts[1]}.${parts[2]}`;
    }
    const raw = model.replace('claude-', '');
    return raw.charAt(0).toUpperCase() + raw.slice(1);
  }

  // ======================================================================
  // Click handlers (IPC)
  // ======================================================================

  private setupIpc(): void {
    ipcMain.on('pet:move-by', (event, dx: number) => {
      const session = this.findSessionByWebContents(event.sender.id);
      if (session) session.petWindow.moveBy(dx);
    });

    ipcMain.on('pet:drag-by', (event, payload: { dx: number; dy: number }) => {
      const session = this.findSessionByWebContents(event.sender.id);
      if (session) {
        // 드래그 중엔 자동 행동 멈춤 (상태를 idle 로 강제)
        session.petWindow.setPetState('idle');
        session.petWindow.dragBy(payload.dx, payload.dy);
      }
    });

    ipcMain.on('pet:drag-end', (event) => {
      const session = this.findSessionByWebContents(event.sender.id);
      if (session) {
        // 드래그 끝 — 다시 자동 행동 사이클 재개를 위해 idle 한 번 보냄
        session.petWindow.setPetState('idle');
      }
    });

    ipcMain.on('pet:click', (event) => {
      const session = this.findSessionByWebContents(event.sender.id);
      if (session) this.handlePetClicked(session);
    });

    ipcMain.on('pet:double-click', (event) => {
      const session = this.findSessionByWebContents(event.sender.id);
      if (session) {
        this.showSpeech(session, S.doubleClick);
        session.petWindow.setPetState('jumping');
      }
    });

    ipcMain.on('pet:right-click', (event) => {
      const session = this.findSessionByWebContents(event.sender.id);
      if (session) this.showContextMenu(session);
    });
  }

  private findSessionByWebContents(wcId: number): PetSession | undefined {
    for (const session of this.sessions.values()) {
      if (session.petWindow.window.webContents.id === wcId) return session;
    }
    return undefined;
  }

  private handlePetClicked(session: PetSession): void {
    const dir = lastPathComponent(session.cwd);
    let messages: string[];
    switch (session.lastStatus) {
      case 'working':
        messages = [S.clickWorkingDir(dir), ...S.clickWorking.slice(1)];
        break;
      case 'waitingForPermission':
        messages = S.clickPermission;
        break;
      case 'idle':
        messages = [S.clickIdleDir(dir), ...S.clickIdle];
        break;
      case 'notRunning':
        messages = S.clickNotRunning;
        break;
    }
    this.showSpeech(session, messages[Math.floor(Math.random() * messages.length)]);
    session.petWindow.setPetState('happy');
  }

  private showContextMenu(session: PetSession): void {
    const menu = new Menu();
    const dir = lastPathComponent(session.cwd) || 'Claude';
    const statusText = (() => {
      switch (session.lastStatus) {
        case 'working': return S.menuWorking;
        case 'waitingForPermission': return S.menuPermission;
        case 'idle': return S.menuIdle;
        case 'notRunning': return S.menuOff;
      }
    })();
    menu.append(new MenuItem({ label: `${dir} - ${statusText}`, enabled: false }));

    const sessionSecs = Math.floor((Date.now() - session.sessionStart) / 1000);
    const sessionText = S.formatDuration(Math.floor(sessionSecs / 60), sessionSecs % 60);
    const workText = S.formatDuration(Math.floor(session.workingSeconds / 60), session.workingSeconds % 60);
    menu.append(new MenuItem({ label: S.menuSessionWork(sessionText, workText), enabled: false }));

    const totalMins = this.timeTracker.todayTotalMinutes();
    menu.append(new MenuItem({ label: S.menuTodayWork(this.timeTracker.formatMinutes(totalMins)), enabled: false }));

    menu.append(new MenuItem({ type: 'separator' }));

    const sessionUsage = this.tokenTracker.usageForSession(this.findSessionId(session) || '');
    const todayUsage = this.tokenTracker.todayUsage();
    if (totalTokens(sessionUsage) > 0) {
      const inp = sessionUsage.inputTokens + sessionUsage.cacheReadTokens;
      const out = sessionUsage.outputTokens;
      menu.append(new MenuItem({
        label: S.menuTokenSession(formatTokens(totalTokens(sessionUsage)), formatTokens(inp), formatTokens(out)),
        enabled: false,
      }));
    }
    if (totalTokens(todayUsage) > 0) {
      const total = todayUsage.cacheReadTokens + todayUsage.cacheCreationTokens + todayUsage.inputTokens;
      const cacheRate = total > 0 ? Math.floor((todayUsage.cacheReadTokens / total) * 100) : 0;
      menu.append(new MenuItem({
        label: S.menuTokenToday(formatTokens(totalTokens(todayUsage)), cacheRate),
        enabled: false,
      }));
    }

    menu.append(new MenuItem({ type: 'separator' }));

    menu.append(new MenuItem({
      label: S.menuWorkTime,
      type: 'checkbox',
      checked: this.settings.showTimer,
      click: () => {
        this.settings.showTimer = !this.settings.showTimer;
        for (const s of this.sessions.values()) {
          s.petWindow.sendState({ showTimer: this.settings.showTimer });
        }
      },
    }));

    menu.append(new MenuItem({
      label: S.menuAutoLaunch,
      type: 'checkbox',
      checked: this.settings.autoLaunch,
      click: () => {
        this.settings.autoLaunch = !this.settings.autoLaunch;
        this.applyAutoLaunch();
        const msg = this.settings.autoLaunch ? S.autoLaunchOn : S.autoLaunchOff;
        this.showSpeech(session, msg);
      },
    }));

    const skinSubmenu = new Menu();
    for (const [name, key] of [[S.skinBasic, 'basic'], [S.skinSpring, 'spring']] as const) {
      skinSubmenu.append(new MenuItem({
        label: name,
        type: 'radio',
        checked: this.settings.skin === key,
        click: () => {
          this.settings.skin = key;
          for (const s of this.sessions.values()) {
            s.petWindow.sendState({ skin: key });
          }
          const first = this.sessions.values().next().value;
          if (first) this.showSpeech(first, S.skinChanged(key === 'spring'));
        },
      }));
    }
    menu.append(new MenuItem({ label: S.menuSkin, submenu: skinSubmenu }));

    menu.append(new MenuItem({ type: 'separator' }));

    if (this.updateChecker.updateAvailable && this.updateChecker.latestVersion) {
      menu.append(new MenuItem({
        label: `🎉 v${this.updateChecker.latestVersion} ${S.menuUpdate}`,
        click: () => this.updateChecker.runUpdate(),
      }));
      menu.append(new MenuItem({ type: 'separator' }));
    }

    menu.append(new MenuItem({
      label: S.menuQuit,
      click: () => this.quit(),
    }));

    // 메뉴 외부 클릭으로 닫히게 하려면 펫 윈도우가 focus 를 받을 수 있어야 함.
    // 평소엔 focusable: false 라 메뉴가 안 닫히는 문제가 있었음.
    // → popup 직전에 임시로 focusable 로 만들고 focus 부여, 닫힐 때 복원.
    const win = session.petWindow.window;
    win.setFocusable(true);
    win.focus();

    menu.popup({
      window: win,
      callback: () => {
        if (!win.isDestroyed()) {
          win.setFocusable(false);
        }
      },
    });
  }

  private findSessionId(target: PetSession): string | null {
    for (const [id, s] of this.sessions) {
      if (s === target) return id;
    }
    return null;
  }

  // ======================================================================
  // Speech helper
  // ======================================================================

  private showSpeech(session: PetSession, text: string, persistent: boolean = false): void {
    const center = session.petWindow.getCenter();
    session.bubble.show(text, center.x, center.y - 4, this.settings.skin, persistent);
  }

  // ======================================================================
  // Quit
  // ======================================================================

  quit(): void {
    for (const s of this.sessions.values()) {
      s.petWindow.destroy();
      s.bubble.destroy();
    }
    this.sessions.clear();
    const { app } = require('electron');
    app.quit();
  }
}

// ======================================================================
// Helpers
// ======================================================================

function lastPathComponent(p: string): string {
  if (!p) return '';
  const norm = p.replace(/\\/g, '/');
  const parts = norm.split('/').filter(Boolean);
  return parts[parts.length - 1] || '';
}

