/**
 * UpdateChecker.swift 포팅
 *
 * GitHub Releases API 로 새 버전 체크.
 * Windows 에선 자동 업데이트 대신 GitHub Releases 페이지로 이동.
 */

import { shell } from 'electron';
import * as S from './strings';

const REPO_API = 'https://api.github.com/repos/devTheKiwi/ClaudePet/releases/latest';
const RELEASES_PAGE = 'https://github.com/devTheKiwi/ClaudePet/releases/latest';

export class UpdateChecker {
  public readonly currentVersion = '2.7.0';
  public latestVersion: string | null = null;
  public updateAvailable = false;
  public onResult: ((message: string) => void) | null = null;

  checkOnLaunch(): void {
    setTimeout(() => this.check(true), 5000);
  }

  private lastCheckAt = 0;

  /** 주기적/이벤트 재확인 — 새 버전일 때만 알림. 30분 쿨다운(깨어남·포커스 연타로 API 도배 방지) */
  checkPeriodic(): void {
    const now = Date.now();
    if (now - this.lastCheckAt < 30 * 60 * 1000) return;
    this.lastCheckAt = now;
    this.check(false);
  }

  private async check(announceWhenCurrent: boolean): Promise<void> {
    try {
      const res = await fetch(REPO_API, {
        headers: { 'User-Agent': 'ClaudePet-Windows' },
      });
      if (!res.ok) {
        if (announceWhenCurrent) this.onResult?.(S.updateFailed);
        return;
      }
      const json = (await res.json()) as { tag_name?: string };
      const tag = json.tag_name;
      if (!tag) {
        if (announceWhenCurrent) this.onResult?.(S.updateFailed);
        return;
      }
      const latest = tag.replace(/^v/, '');
      this.latestVersion = latest;

      if (this.isNewer(latest, this.currentVersion)) {
        this.updateAvailable = true;
        this.onResult?.(S.updateAvailable(latest));
      } else {
        this.updateAvailable = false;
        if (announceWhenCurrent) this.onResult?.(S.updateLatest(this.currentVersion));
      }
    } catch {
      if (announceWhenCurrent) this.onResult?.(S.updateFailed);
    }
  }

  private isNewer(latest: string, current: string): boolean {
    const l = latest.split('.').map((s) => parseInt(s, 10) || 0);
    const c = current.split('.').map((s) => parseInt(s, 10) || 0);
    const len = Math.max(l.length, c.length);
    for (let i = 0; i < len; i++) {
      const lv = l[i] ?? 0;
      const cv = c[i] ?? 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  /** Releases 페이지 열기 */
  runUpdate(): void {
    shell.openExternal(RELEASES_PAGE);
  }
}
