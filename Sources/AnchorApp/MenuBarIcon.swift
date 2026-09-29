import AppKit

/// 메뉴바에 그리는 닻 아이콘.
///
/// SF Symbol 로는 "앱이 뭔지"가 드러나지 않는다. RunFox 가 여우를 직접 그리듯
/// 여기서도 닻을 픽셀로 직접 그린다. Scripts/make_assets.py 의
/// anchor_sprite() 와 같은 12x14 격자를 쓴다.
///
/// 메뉴바 배경에 맞춰 색을 직접 고르므로 isTemplate = false 다.
enum MenuBarIcon {
    /// 메뉴바 높이 기준 아이콘 크기.
    private static let iconHeight: CGFloat = 15
    private static let gridW = 12
    private static let gridH = 14

    /// 닻을 이루는 픽셀 좌표 (gridW x gridH, y=0 이 맨 위).
    private static var pixels: [Set<Int>] {
        var rows: [Set<Int>] = Array(repeating: [], count: gridH)
        func add(_ x: Int, _ y: Int) { rows[y].insert(x) }

        // 위쪽 링
        for (x, y) in [(5, 0), (6, 0), (4, 1), (7, 1), (4, 2), (7, 2), (5, 3), (6, 3)] {
            add(x, y)
        }
        // 세로 축
        for y in 4..<gridH { add(5, y); add(6, y) }
        // 가로 빔
        for x in 1..<11 { add(x, 5) }
        // 양쪽 팔 (갈고리)
        let arms: [Int: (Int, Int)] = [
            6: (1, 10), 7: (0, 11), 8: (0, 11), 9: (1, 10),
            10: (1, 10), 11: (2, 9), 12: (2, 9), 13: (1, 10),
        ]
        for (y, (xl, xr)) in arms { add(xl, y); add(xr, y) }
        return rows
    }

    /// 오늘 기록했으면 강조색, 아니면 보통 라벨 색.
    private static func tint(active: Bool) -> NSColor {
        active ? .controlAccentColor : .labelColor
    }

    /// 오늘 기록 수만 표시.
    static func make(count: Int) -> NSImage {
        render(count: count > 0 ? "\(min(count, 99))" : nil,
               active: count > 0,
               width: count > 0 ? 34 : 22)
    }

    /// 연속 기록 일수를 표시. 3일 이상 연속이면 강조한다.
    static func makeStreak(_ streak: Int) -> NSImage {
        // 너무 높은 숫자는 메뉴바를 무겁게 하므로 3자리로 자른다.
        let text: String? = streak > 0 ? (streak > 99 ? "99+" : "\(streak)") : nil
        return render(count: text, active: streak >= 3, width: text == nil ? 22 : 34)
    }

    private static func render(count: String?, active: Bool, width: CGFloat) -> NSImage {
        let scale = iconHeight / CGFloat(gridH)
        let iconW = CGFloat(gridW) * scale
        let textW: CGFloat = count == nil ? 0 : 12
        let totalW = max(iconW, width - 2)

        let size = NSSize(width: totalW, height: iconHeight)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .none

        let color = tint(active: active)

        // 닻
        color.setFill()
        let rows = pixels
        for y in 0..<gridH {
            for x in rows[y] {
                NSRect(
                    x: CGFloat(x) * scale,
                    y: CGFloat(gridH - 1 - y) * scale,   // NSView 좌표는 y 가 아래로
                    width: scale,
                    height: scale
                ).fill()
            }
        }

        // 숫자
        if let count {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: color,
            ]
            let s = count as NSString
            let textSize = s.size(withAttributes: attrs)
            s.draw(
                at: NSPoint(x: iconW + 2, y: (iconHeight - textSize.height) / 2),
                withAttributes: attrs
            )
        }
        return image
    }
}
