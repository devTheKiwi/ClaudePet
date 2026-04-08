/**
 * TokenTracker.swift 포팅
 *
 * %USERPROFILE%\.claude\projects\<encoded-cwd>\<sessionId>.jsonl 을 파싱해
 * 세션별 / 오늘 전체 토큰 사용량을 계산.
 */

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens: number;
  cacheReadTokens: number;
}

export const EMPTY_USAGE: TokenUsage = {
  inputTokens: 0,
  outputTokens: 0,
  cacheCreationTokens: 0,
  cacheReadTokens: 0,
};

export function totalTokens(u: TokenUsage): number {
  return u.inputTokens + u.outputTokens + u.cacheCreationTokens + u.cacheReadTokens;
}

export function formatTokens(count: number): string {
  if (count < 1000) return String(count);
  if (count < 1_000_000) return (count / 1000).toFixed(1) + 'K';
  return (count / 1_000_000).toFixed(1) + 'M';
}

export class TokenTracker {
  private projectsDir: string;

  constructor() {
    this.projectsDir = path.join(os.homedir(), '.claude', 'projects');
  }

  /** 특정 세션의 토큰 사용량 */
  usageForSession(sessionId: string): TokenUsage {
    if (!fs.existsSync(this.projectsDir)) return { ...EMPTY_USAGE };

    let projectDirs: string[];
    try {
      projectDirs = fs.readdirSync(this.projectsDir);
    } catch {
      return { ...EMPTY_USAGE };
    }

    for (const dir of projectDirs) {
      const jsonlPath = path.join(this.projectsDir, dir, `${sessionId}.jsonl`);
      if (fs.existsSync(jsonlPath)) {
        return this.parseJSONL(jsonlPath);
      }
    }
    return { ...EMPTY_USAGE };
  }

  /** 오늘 전체 토큰 사용량 (30초 캐싱) */
  private todayCache: TokenUsage | null = null;
  private todayCacheTime = 0;

  todayUsage(): TokenUsage {
    const now = Date.now();
    if (this.todayCache && now - this.todayCacheTime < 30000) {
      return this.todayCache;
    }

    if (!fs.existsSync(this.projectsDir)) return { ...EMPTY_USAGE };

    const total: TokenUsage = { ...EMPTY_USAGE };
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);
    const startMs = startOfToday.getTime();

    let projectDirs: string[];
    try {
      projectDirs = fs.readdirSync(this.projectsDir);
    } catch {
      return total;
    }

    for (const dir of projectDirs) {
      const projectPath = path.join(this.projectsDir, dir);
      let files: string[];
      try {
        files = fs.readdirSync(projectPath);
      } catch {
        continue;
      }

      for (const file of files) {
        if (!file.endsWith('.jsonl')) continue;
        const filePath = path.join(projectPath, file);
        try {
          const stat = fs.statSync(filePath);
          if (stat.mtimeMs < startMs) continue;
          const usage = this.parseJSONL(filePath);
          total.inputTokens += usage.inputTokens;
          total.outputTokens += usage.outputTokens;
          total.cacheCreationTokens += usage.cacheCreationTokens;
          total.cacheReadTokens += usage.cacheReadTokens;
        } catch {
          continue;
        }
      }
    }

    this.todayCache = total;
    this.todayCacheTime = Date.now();
    return total;
  }

  private parseJSONL(filePath: string): TokenUsage {
    const usage: TokenUsage = { ...EMPTY_USAGE };
    let content: string;
    try {
      content = fs.readFileSync(filePath, 'utf8');
    } catch {
      return usage;
    }

    for (const line of content.split('\n')) {
      if (!line.trim()) continue;
      try {
        const json = JSON.parse(line);
        const u = json?.message?.usage;
        if (u) {
          usage.inputTokens += u.input_tokens || 0;
          usage.outputTokens += u.output_tokens || 0;
          usage.cacheCreationTokens += u.cache_creation_input_tokens || 0;
          usage.cacheReadTokens += u.cache_read_input_tokens || 0;
        }
      } catch {
        continue;
      }
    }

    return usage;
  }
}
