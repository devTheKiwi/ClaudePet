/**
 * TokenTracker.swift 포팅
 *
 * %USERPROFILE%\.claude\projects\<encoded-cwd>\<sessionId>.jsonl 을 파싱해
 * 세션별 / 오늘 전체 토큰 사용량을 계산.
 */

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { StringDecoder } from 'string_decoder';

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

/**
 * JSONL 한 줄의 usage 를 더한다. sinceMs 를 주면 해당 시각 이후 timestamp 를 가진 줄만.
 * (세션 파일 하나가 여러 날에 걸쳐 누적되므로, "오늘" 집계 시 줄 단위로 걸러야 정확하다.)
 */
function addLineUsage(usage: TokenUsage, line: string, sinceMs?: number): void {
  if (!line.trim()) return;
  try {
    const json = JSON.parse(line);
    const u = json?.message?.usage;
    if (!u) return;

    // sinceMs 필터: 줄별 timestamp 가 기준 시각 이후인 줄만 (UTC↔로컬은 절대시각 비교라 안전)
    if (sinceMs !== undefined) {
      const t = json?.timestamp ? new Date(json.timestamp).getTime() : NaN;
      if (isNaN(t) || t < sinceMs) return;
    }

    usage.inputTokens += u.input_tokens || 0;
    usage.outputTokens += u.output_tokens || 0;
    usage.cacheCreationTokens += u.cache_creation_input_tokens || 0;
    usage.cacheReadTokens += u.cache_read_input_tokens || 0;
  } catch {
    // 깨진 줄은 건너뜀
  }
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

  /**
   * 오늘 전체 토큰 사용량 — 메인 프로세스에서 2초마다 불린다.
   * 오늘 JSONL 전체를 읽는 건 수십 MB라, 동기로 하면 그동안 메인 프로세스가 멈춰 펫 이동이 끊긴다.
   * 그래서 마지막 값을 바로 돌려주고, 30초 지났으면 비동기로 다시 계산한다.
   */
  private todayCache: TokenUsage = { ...EMPTY_USAGE };
  private todayCacheTime = 0;
  private todayRefreshing = false;

  todayUsage(): TokenUsage {
    if (!this.todayRefreshing && Date.now() - this.todayCacheTime >= 30000) {
      this.todayRefreshing = true;
      this.computeTodayUsage()
        .then((usage) => { this.todayCache = usage; })
        .catch(() => {})
        .finally(() => {
          this.todayCacheTime = Date.now();
          this.todayRefreshing = false;
        });
    }
    return this.todayCache;
  }

  private async computeTodayUsage(): Promise<TokenUsage> {
    const total: TokenUsage = { ...EMPTY_USAGE };
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);
    const startMs = startOfToday.getTime();

    let projectDirs: string[];
    try {
      projectDirs = await fs.promises.readdir(this.projectsDir);
    } catch {
      return total;
    }

    for (const dir of projectDirs) {
      const projectPath = path.join(this.projectsDir, dir);
      let files: string[];
      try {
        files = await fs.promises.readdir(projectPath);
      } catch {
        continue;
      }

      for (const file of files) {
        if (!file.endsWith('.jsonl')) continue;
        const filePath = path.join(projectPath, file);
        try {
          const stat = await fs.promises.stat(filePath);
          if (stat.mtimeMs < startMs) continue;                         // 1차 필터(성능): 오늘 수정된 파일만
          const usage = await this.parseJSONLChunked(filePath, startMs); // 2차 필터(정확성): 오늘 줄만
          total.inputTokens += usage.inputTokens;
          total.outputTokens += usage.outputTokens;
          total.cacheCreationTokens += usage.cacheCreationTokens;
          total.cacheReadTokens += usage.cacheReadTokens;
        } catch {
          continue;
        }
      }
    }

    return total;
  }

  /** JSONL 파싱 (동기 — 세션 하나 분량일 때만 쓴다) */
  private parseJSONL(filePath: string, sinceMs?: number): TokenUsage {
    const usage: TokenUsage = { ...EMPTY_USAGE };
    let content: string;
    try {
      content = fs.readFileSync(filePath, 'utf8');
    } catch {
      return usage;
    }

    for (const line of content.split('\n')) addLineUsage(usage, line, sinceMs);
    return usage;
  }

  /** JSONL 파싱 (비동기) — 1MB 씩 읽고 그 사이 이벤트 루프에 양보해서, 큰 파일도 메인 프로세스를 오래 붙잡지 않는다 */
  private async parseJSONLChunked(filePath: string, sinceMs?: number): Promise<TokenUsage> {
    const usage: TokenUsage = { ...EMPTY_USAGE };
    const fh = await fs.promises.open(filePath, 'r');
    try {
      const buf = Buffer.alloc(1024 * 1024);
      const decoder = new StringDecoder('utf8');
      let rest = '';
      for (;;) {
        const { bytesRead } = await fh.read(buf, 0, buf.length, null);
        if (bytesRead === 0) break;
        const lines = (rest + decoder.write(buf.subarray(0, bytesRead))).split('\n');
        rest = lines.pop() ?? '';
        for (const line of lines) addLineUsage(usage, line, sinceMs);
      }
      addLineUsage(usage, rest + decoder.end(), sinceMs);
    } finally {
      await fh.close();
    }
    return usage;
  }

  /** 세션의 모델명 감지 (JSONL에서 마지막 model 필드) */
  modelForSession(sessionId: string): string | null {
    if (!fs.existsSync(this.projectsDir)) return null;

    let projectDirs: string[];
    try {
      projectDirs = fs.readdirSync(this.projectsDir);
    } catch {
      return null;
    }

    for (const dir of projectDirs) {
      const jsonlPath = path.join(this.projectsDir, dir, `${sessionId}.jsonl`);
      if (!fs.existsSync(jsonlPath)) continue;

      let content: string;
      try {
        content = fs.readFileSync(jsonlPath, 'utf8');
      } catch {
        continue;
      }

      // 마지막부터 역순으로 model 필드 찾기
      const lines = content.split('\n').reverse();
      for (const line of lines) {
        if (!line.includes('"model"')) continue;
        try {
          const json = JSON.parse(line);
          const model = json?.message?.model;
          if (typeof model === 'string') return model;
        } catch {
          continue;
        }
      }
    }
    return null;
  }
}
