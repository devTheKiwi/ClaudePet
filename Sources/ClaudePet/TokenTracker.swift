import Foundation

struct TokenUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    static func formatTokens(_ count: Int) -> String {
        if count < 1000 {
            return "\(count)"
        } else if count < 1_000_000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fK", k)
        } else {
            let m = Double(count) / 1_000_000.0
            return String(format: "%.1fM", m)
        }
    }
}

class TokenTracker {
    private let claudeProjectsDir: String

    init() {
        claudeProjectsDir = NSHomeDirectory() + "/.claude/projects"
    }

    /// 특정 세션의 토큰 사용량
    func usageForSession(_ sessionId: String) -> TokenUsage {
        // 세션 ID로 JSONL 파일 찾기
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: claudeProjectsDir) else {
            return TokenUsage()
        }

        for dir in projectDirs {
            let jsonlPath = "\(claudeProjectsDir)/\(dir)/\(sessionId).jsonl"
            if fm.fileExists(atPath: jsonlPath) {
                return parseJSONL(at: jsonlPath)
            }
        }

        return TokenUsage()
    }

    /// 세션의 모델명 감지
    func modelForSession(_ sessionId: String) -> String? {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: claudeProjectsDir) else { return nil }

        for dir in projectDirs {
            let jsonlPath = "\(claudeProjectsDir)/\(dir)/\(sessionId).jsonl"
            if fm.fileExists(atPath: jsonlPath),
               let data = fm.contents(atPath: jsonlPath),
               let content = String(data: data, encoding: .utf8) {
                // 마지막부터 역순으로 model 필드 찾기
                for line in content.components(separatedBy: "\n").reversed() {
                    if line.contains("\"model\""),
                       let lineData = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                       let message = json["message"] as? [String: Any],
                       let model = message["model"] as? String {
                        return model
                    }
                }
            }
        }
        return nil
    }

    /// 오늘 전체 토큰 사용량
    func todayUsage() -> TokenUsage {
        let fm = FileManager.default
        var total = TokenUsage()

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: claudeProjectsDir) else {
            return total
        }

        let today = Calendar.current.startOfDay(for: Date())

        for dir in projectDirs {
            let projectPath = "\(claudeProjectsDir)/\(dir)"
            guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }

            for file in files {
                guard file.hasSuffix(".jsonl") else { continue }
                let filePath = "\(projectPath)/\(file)"

                // 1차 필터(성능): 오늘 수정된 파일만 — 그 외 파일엔 오늘 기록이 있을 수 없음
                if let attrs = try? fm.attributesOfItem(atPath: filePath),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate >= today {
                    // 2차 필터(정확성): 세션 파일은 여러 날에 걸쳐 누적되므로 줄별 timestamp로 오늘 것만 합산
                    let usage = parseJSONL(at: filePath, since: today)
                    total.inputTokens += usage.inputTokens
                    total.outputTokens += usage.outputTokens
                    total.cacheCreationTokens += usage.cacheCreationTokens
                    total.cacheReadTokens += usage.cacheReadTokens
                }
            }
        }

        return total
    }

    // MARK: - JSONL Parsing

    /// JSONL 파싱. `since`를 주면 해당 시각 이후 timestamp를 가진 줄만 합산한다.
    /// (세션 파일 하나가 여러 날에 걸쳐 누적되므로, "오늘" 집계 시 줄 단위로 걸러야 정확하다.)
    private func parseJSONL(at path: String, since: Date? = nil) -> TokenUsage {
        var usage = TokenUsage()

        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return usage
        }

        for line in content.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // message.usage 찾기
            guard let message = json["message"] as? [String: Any],
                  let usageData = message["usage"] as? [String: Any] else {
                continue
            }

            // since 필터: 줄별 timestamp가 기준 시각 이후인 줄만 (UTC ↔ 로컬은 절대시각 비교라 안전)
            if let since = since {
                guard let ts = json["timestamp"] as? String,
                      let date = TokenTracker.parseTimestamp(ts),
                      date >= since else {
                    continue
                }
            }

            usage.inputTokens += usageData["input_tokens"] as? Int ?? 0
            usage.outputTokens += usageData["output_tokens"] as? Int ?? 0
            usage.cacheCreationTokens += usageData["cache_creation_input_tokens"] as? Int ?? 0
            usage.cacheReadTokens += usageData["cache_read_input_tokens"] as? Int ?? 0
        }

        return usage
    }

    // MARK: - Timestamp

    /// ISO8601 timestamp 파싱 — 소수점 초가 있는 형식("…:17.206Z")과 없는 형식 모두 지원
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static func parseTimestamp(_ s: String) -> Date? {
        return iso8601WithFractional.date(from: s) ?? iso8601Plain.date(from: s)
    }
}
