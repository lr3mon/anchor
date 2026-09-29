import Foundation

/// 태그 문자열 파서.
/// 저장 포맷은 콤마로 이��지만, 사용자는 "--tags '#swift, ios'" 처럼 공백이나 # 를 섞어 준다.
/// 세 구분자를 모두 받아야 하므로 한 곳에 모아둔다.
public enum TagParser {
    /// 콤마/공백/# 로 구분하고, 빈 항목과 중복을 제거한다.
    public static func parse(_ s: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in s.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "#" }) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return out
    }

    /// 저장용 직렬화.
    public static func join(_ tags: [String]) -> String {
        tags.joined(separator: ",")
    }
}
