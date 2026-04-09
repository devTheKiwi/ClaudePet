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

                // 오늘 수정된 파일만
                if let attrs = try? fm.attributesOfItem(atPath: filePath),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate >= today {
                    let usage = parseJSONL(at: filePath)
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

    private func parseJSONL(at path: String) -> TokenUsage {
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
            if let message = json["message"] as? [String: Any],
               let usageData = message["usage"] as? [String: Any] {
                usage.inputTokens += usageData["input_tokens"] as? Int ?? 0
                usage.outputTokens += usageData["output_tokens"] as? Int ?? 0
                usage.cacheCreationTokens += usageData["cache_creation_input_tokens"] as? Int ?? 0
                usage.cacheReadTokens += usageData["cache_read_input_tokens"] as? Int ?? 0
            }
        }

        return usage
    }
}
