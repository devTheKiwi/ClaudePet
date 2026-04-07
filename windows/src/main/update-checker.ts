/**
 * UpdateChecker.swift 포팅
 *
 * GitHub Releases API 로 새 버전 체크.
 * Windows 에선 자동 업데이트 대신 GitHub Releases 페이지로 이동.
 */

import { shell } from 'electron';

const REPO_API = 'https://api.github.com/repos/devTheKiwi/ClaudePet/releases/latest';
const RELEASES_PAGE = 'https://github.com/devTheKiwi/ClaudePet/releases/latest';

export class UpdateChecker {
  public readonly currentVersion = '2.3.1';
  public latestVersion: string | null = null;
  public updateAvailable = false;
  public onResult: ((message: string) => void) | null = null;

  checkOnLaunch(): void {
    setTimeout(() => this.check(), 5000);
  }

  checkNow(): void {
    this.check();
  }

  private async check(): Promise<void> {
    try {
      const res = await fetch(REPO_API, {
        headers: { 'User-Agent': 'ClaudePet-Windows' },
      });
      if (!res.ok) {
        this.onResult?.('업데이트 확인 실패');
        return;
      }
      const json = (await res.json()) as { tag_name?: string };
      const tag = json.tag_name;
      if (!tag) {
        this.onResult?.('업데이트 확인 실패');
        return;
      }
      const latest = tag.replace(/^v/, '');
      this.latestVersion = latest;

      if (this.isNewer(latest, this.currentVersion)) {
        this.updateAvailable = true;
        this.onResult?.(`새 버전 v${latest} 나왔어! 우클릭→업데이트!`);
      } else {
        this.updateAvailable = false;
        this.onResult?.(`최신 버전이에요! (v${this.currentVersion})`);
      }
    } catch {
      this.onResult?.('업데이트 확인 실패');
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
