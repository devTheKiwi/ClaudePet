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
      this.showSpeech(session, '안녕! 나는 Claude Pet이야!');
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
    this.showSpeech(session, `${colorName} ${dir || '새 세션'} 시작!`);
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

      this.showSpeech(session, '바이바이~');
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
          this.showSpeech(existing, toolMessage(info.tool));
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
          this.showSpeech(def, `${dir || '세션'} 연결됨!`);
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
          this.showSpeech(session, '작업 시작!');
          session.petWindow.setPetState('excited');
        }
        break;
      case 'waitingForPermission':
        this.showSpeech(session, '⚠️ 권한이 필요해! 확인해줘!', true);
        session.petWindow.setPetState('jumping');
        break;
      case 'idle':
        if (oldS === 'working') {
          this.showSpeech(session, '작업 완료!');
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
        this.showSpeech(session, 'Claude Desktop 왔다! 반가워!');
      }
    } else if (!isRunning && this.desktopWasRunning) {
      const session = this.sessions.get(desktopId);
      if (session) {
        const usedSecs = Math.floor((Date.now() - (this.desktopStartTime || Date.now())) / 1000);
        const mins = Math.floor(usedSecs / 60);
        const secs = usedSecs % 60;
        const timeText = `${String(mins).padStart(2, '0')}분${String(secs).padStart(2, '0')}초`;
        this.showSpeech(session, `${timeText} 사용했어! 수고했어~`);

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
          const messages = [
            `${mins}분 지났어!`,
            `${mins}분이야! 스트레칭 어때?`,
            `벌써 ${mins}분! 물 한잔 마셔!`,
          ];
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

    const milestones: [number, string][] = [
      [10, '오늘 10K 토큰 사용!'],
      [50, '오늘 50K 돌파!'],
      [100, '오늘 100K! 열심히 일하는 중!'],
      [200, '오늘 200K...많이 썼다!'],
      [500, '오늘 500K!! 대작업이었구나!'],
      [1000, '오늘 1M!!! 역대급이야!'],
    ];

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

    const idleMessages = [
      '오늘 코딩 많이 했어?',
      '잠깐 스트레칭 하는 건 어때?',
      '커피 한잔 어때요~',
      '버그 없는 하루 되길!',
      'git commit 했어?',
      '오늘도 화이팅!',
      '난 여기서 지켜보고 있을게~',
      '세미콜론 빼먹지 않았지?',
      '난 Opus 4.6이야, 최고지!',
    ];
    const workingMessages = ['열심히 작업 중이야!', '잘 되고 있어!', '곧 끝날 거야!'];
    const messages = session.lastStatus === 'working' ? workingMessages : idleMessages;
    this.showSpeech(session, messages[Math.floor(Math.random() * messages.length)]);
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
        this.showSpeech(session, '우왕! 신난다~!');
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
        messages = [
          `지금 ${dir}에서 열심히 일하는 중!`,
          '잠깐만, 거의 다 됐어!',
          'Claude가 코드 작성 중~',
        ];
        break;
      case 'waitingForPermission':
        messages = [
          '권한 승인이 필요해! 터미널 확인해줘!',
          '나 좀 도와줘~ 권한이 필요해!',
        ];
        break;
      case 'idle':
        messages = [
          `${dir} 대기 중~ 뭐 시킬 거야?`,
          '나 건드리지 마~ 간지러워!',
          '놀아줄 거야?',
          '왜왜왜~ 뭐 필요해?',
        ];
        break;
      case 'notRunning':
        messages = ['Claude Code가 꺼져있어~', '나 혼자 심심해...'];
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
        case 'working': return '🔵 작업 중';
        case 'waitingForPermission': return '🟡 권한 대기';
        case 'idle': return '🟢 대기 중';
        case 'notRunning': return '⚫ 꺼짐';
      }
    })();
    menu.append(new MenuItem({ label: `${dir} - ${statusText}`, enabled: false }));

    const sessionSecs = Math.floor((Date.now() - session.sessionStart) / 1000);
    const sessionText = `${String(Math.floor(sessionSecs / 60)).padStart(2, '0')}분${String(sessionSecs % 60).padStart(2, '0')}초`;
    const workText = `${String(Math.floor(session.workingSeconds / 60)).padStart(2, '0')}분${String(session.workingSeconds % 60).padStart(2, '0')}초`;
    menu.append(new MenuItem({ label: `📊 세션 ${sessionText} (작업 ${workText})`, enabled: false }));

    const totalMins = this.timeTracker.todayTotalMinutes();
    menu.append(new MenuItem({ label: `📊 오늘 총 작업: ${this.timeTracker.formatMinutes(totalMins)}`, enabled: false }));

    menu.append(new MenuItem({ type: 'separator' }));

    const sessionUsage = this.tokenTracker.usageForSession(this.findSessionId(session) || '');
    const todayUsage = this.tokenTracker.todayUsage();
    if (totalTokens(sessionUsage) > 0) {
      const inp = sessionUsage.inputTokens + sessionUsage.cacheReadTokens;
      const out = sessionUsage.outputTokens;
      menu.append(new MenuItem({
        label: `🪙 세션: ${formatTokens(totalTokens(sessionUsage))} (입력 ${formatTokens(inp)} / 출력 ${formatTokens(out)})`,
        enabled: false,
      }));
    }
    if (totalTokens(todayUsage) > 0) {
      const total = todayUsage.cacheReadTokens + todayUsage.cacheCreationTokens + todayUsage.inputTokens;
      const cacheRate = total > 0 ? Math.floor((todayUsage.cacheReadTokens / total) * 100) : 0;
      menu.append(new MenuItem({
        label: `🪙 오늘 총: ${formatTokens(totalTokens(todayUsage))} (캐시 ${cacheRate}%)`,
        enabled: false,
      }));
    }

    menu.append(new MenuItem({ type: 'separator' }));

    menu.append(new MenuItem({
      label: '작업시간 표시',
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
      label: 'PC 시작 시 자동 실행',
      type: 'checkbox',
      checked: this.settings.autoLaunch,
      click: () => {
        this.settings.autoLaunch = !this.settings.autoLaunch;
        this.applyAutoLaunch();
        const msg = this.settings.autoLaunch
          ? '이제 PC 켤 때마다 나타날게! 🚀'
          : '자동 실행 꺼졌어~ 다음엔 직접 켜줘!';
        this.showSpeech(session, msg);
      },
    }));

    const skinSubmenu = new Menu();
    for (const [name, key] of [['기본', 'basic'], ['봄 에디션 🌸', 'spring']] as const) {
      skinSubmenu.append(new MenuItem({
        label: name,
        type: 'radio',
        checked: this.settings.skin === key,
        click: () => {
          this.settings.skin = key;
          for (const s of this.sessions.values()) {
            s.petWindow.sendState({ skin: key });
          }
          const msg = key === 'spring' ? '봄이 왔어! 🌸' : '기본 스킨으로 돌아왔어!';
          const first = this.sessions.values().next().value;
          if (first) this.showSpeech(first, msg);
        },
      }));
    }
    menu.append(new MenuItem({ label: '스킨', submenu: skinSubmenu }));

    menu.append(new MenuItem({ type: 'separator' }));

    if (this.updateChecker.updateAvailable && this.updateChecker.latestVersion) {
      menu.append(new MenuItem({
        label: `🎉 v${this.updateChecker.latestVersion} 업데이트!`,
        click: () => this.updateChecker.runUpdate(),
      }));
      menu.append(new MenuItem({ type: 'separator' }));
    }

    menu.append(new MenuItem({
      label: '종료',
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

function toolMessage(tool: string): string {
  const t = tool.toLowerCase();
  if (t === 'bash') return '명령어 실행 중...';
  if (t === 'read') return '파일 읽는 중...';
  if (t === 'edit') return '코드 수정 중...';
  if (t === 'write') return '파일 작성 중...';
  if (t === 'grep') return '코드 검색 중...';
  if (t === 'glob') return '파일 찾는 중...';
  if (t === 'agent') return '에이전트 작업 중...';
  if (t.includes('webcrawl') || t.includes('webfetch') || t.includes('websearch')) return '웹 검색 중...';
  if (t.includes('notebookedit')) return '노트북 수정 중...';
  if (t.includes('task')) return '작업 관리 중...';
  if (t.includes('mcp')) return '플러그인 실행 중...';
  return '작업 중...';
}
