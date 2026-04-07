/**
 * TimeTracker — AppDelegate.swift 의 TimeTracker 클래스 포팅.
 * 오늘 누적 작업 시간을 분 단위로 저장 (electron-store 대신 JSON 파일).
 */

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

interface TimeStorage {
  date: string;
  minutes: number;
}

const STORE_PATH = path.join(os.homedir(), '.claudepet-windows', 'time.json');

export class TimeTracker {
  private data: TimeStorage;

  constructor() {
    this.data = this.load();
    this.ensureToday();
  }

  todayTotalMinutes(): number {
    this.ensureToday();
    return this.data.minutes;
  }

  addMinute(): void {
    this.ensureToday();
    this.data.minutes += 1;
    this.save();
  }

  formatMinutes(mins: number): string {
    if (mins < 60) return `${mins}분`;
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return m > 0 ? `${h}시간 ${m}분` : `${h}시간`;
  }

  private ensureToday(): void {
    const today = this.dateString();
    if (this.data.date !== today) {
      this.data = { date: today, minutes: 0 };
      this.save();
    }
  }

  private dateString(): string {
    const d = new Date();
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  private load(): TimeStorage {
    try {
      if (fs.existsSync(STORE_PATH)) {
        return JSON.parse(fs.readFileSync(STORE_PATH, 'utf8'));
      }
    } catch {}
    return { date: this.dateString(), minutes: 0 };
  }

  private save(): void {
    try {
      fs.mkdirSync(path.dirname(STORE_PATH), { recursive: true });
      fs.writeFileSync(STORE_PATH, JSON.stringify(this.data), 'utf8');
    } catch {}
  }
}

/** 사용자 설정 (skin, showTimer 등) 저장 */
const SETTINGS_PATH = path.join(os.homedir(), '.claudepet-windows', 'settings.json');

export class UserSettings {
  private data: { skin?: string; showTimer?: boolean; autoLaunch?: boolean };

  constructor() {
    this.data = this.load();
  }

  get skin(): 'basic' | 'spring' {
    return (this.data.skin === 'spring' ? 'spring' : 'basic') as 'basic' | 'spring';
  }
  set skin(v: 'basic' | 'spring') {
    this.data.skin = v;
    this.save();
  }

  get showTimer(): boolean {
    return this.data.showTimer !== false;
  }
  set showTimer(v: boolean) {
    this.data.showTimer = v;
    this.save();
  }

  /** 첫 실행 시 기본 true */
  get autoLaunch(): boolean {
    return this.data.autoLaunch !== false;
  }
  set autoLaunch(v: boolean) {
    this.data.autoLaunch = v;
    this.save();
  }

  /** 설정 파일이 존재 했는지 — 첫 실행 판별용 */
  isFirstRun(): boolean {
    return Object.keys(this.data).length === 0;
  }

  private load(): any {
    try {
      if (fs.existsSync(SETTINGS_PATH)) {
        return JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf8'));
      }
    } catch {}
    return {};
  }

  private save(): void {
    try {
      fs.mkdirSync(path.dirname(SETTINGS_PATH), { recursive: true });
      fs.writeFileSync(SETTINGS_PATH, JSON.stringify(this.data), 'utf8');
    } catch {}
  }
}
