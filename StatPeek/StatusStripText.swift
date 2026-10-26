import AppKit
import CoreText

/// Native labels and width reservation share the system's monospaced design.
enum StatusStripText {
    static func nativeFont() -> NSFont {
        .monospacedSystemFont(ofSize: 9, weight: .regular)
    }

    static func makeFont() -> CTFont {
        let font = nativeFont()
        return CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
    }

    static func width(_ string: String) -> CGFloat {
        guard let line = line(string, font: makeFont(), color: CGColor(gray: 0, alpha: 1)) else { return 0 }
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func line(_ string: String, font: CTFont, color: CGColor) -> CTLine? {
        let attributes = [kCTFontAttributeName as String: font, kCTForegroundColorAttributeName as String: color] as CFDictionary
        guard let value = CFAttributedStringCreate(nil, string as CFString, attributes) else { return nil }
        return CTLineCreateWithAttributedString(value)
    }
}
