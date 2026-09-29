import Foundation

/// 터미널 출력. ANSI 는 isatty 로 판단해 파이프/리다이렉트 시 깨지지 않게 한다.
/// Swift 6 Strict Concurrency 에서 전역 함수 저장소는 Sendable 이 아니라 컴파일 에러가 되므로
/// @Sendable 을 붙여 순수 함수임을 명시한다.
public enum Out {
    public static let tty: Bool = isatty(STDOUT_FILENO) == 1

    public static func c(_ code: String, _ s: String) -> String {
        tty ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }

    public static let bold   = { @Sendable (s: String) in c("1", s) }
    public static let dim    = { @Sendable (s: String) in c("2", s) }
    public static let red    = { @Sendable (s: String) in c("31", s) }
    public static let green  = { @Sendable (s: String) in c("32", s) }
    public static let yellow = { @Sendable (s: String) in c("33", s) }
    public static let blue   = { @Sendable (s: String) in c("34", s) }
    public static let cyan   = { @Sendable (s: String) in c("36", s) }

    public static func eprint(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    public static func print(_ s: String = "") { Swift.print(s) }

    /// 상태 배지 색.
    public static func badge(_ s: Decision.Status) -> String {
        switch s {
        case .accepted:   return green(s.badge)
        case .proposed:   return yellow(s.badge)
        case .superseded: return dim(s.badge)
        case .rejected:   return red(s.badge)
        }
    }
}

/// 간단한 플래그 파서.
/// 지원: `--key value`, `--key=value`, `--bool`, `-k value`.
/// 주의: 같은 키가 반복되면 마지막 값만 남는다. 반복 옵션(`--alt`)은 호출부에서 원본 argv 를 직접 본다.
public struct Args: Sendable {
    private var flags: [String: String] = [:]
    private var bools: Set<String> = []
    public let positional: [String]

    public init(_ argv: [String]) {
        var pos: [String] = []
        var i = 0
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--") {
                let body = String(a.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    flags[String(body[body.startIndex..<eq])] =
                        String(body[body.index(after: eq)...])
                } else if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") {
                    flags[body] = argv[i + 1]
                    i += 1
                } else {
                    bools.insert(body)
                }
            } else if a.hasPrefix("-"), a.count > 1, !a.dropFirst().allSatisfy(\.isNumber) {
                let body = String(a.dropFirst())
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("-") {
                    flags[body] = argv[i + 1]
                    i += 1
                } else {
                    bools.insert(body)
                }
            } else {
                pos.append(a)
            }
            i += 1
        }
        positional = pos
    }

    public func str(_ k: String) -> String? { flags[k] }
    public func str(_ k: String, default d: String) -> String { flags[k] ?? d }
    public func int(_ k: String, default d: Int) -> Int { flags[k].flatMap(Int.init) ?? d }
    public func bool(_ k: String) -> Bool { bools.contains(k) || flags[k] == "true" }
    public func has(_ k: String) -> Bool { flags[k] != nil || bools.contains(k) }
}
