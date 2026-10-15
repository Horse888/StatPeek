import AppKit
import CoreText

/// Core Text attributes contain concrete CTFont/CGColor values rather than AppKit drawing objects.
/// This avoids the Cocoa attribute-copy path that aborted status-item drawing on macOS 27.
enum StatusStripText {
    static func makeFont() -> CTFont {
        CTFontCreateWithName("Menlo-Bold" as CFString, 9, nil)
    }

    static func width(_ string: String) -> CGFloat {
        guard let line = line(string, font: makeFont(), color: CGColor(gray: 0, alpha: 1)) else { return 0 }
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    static func draw(_ string: String, at origin: NSPoint, font: CTFont, color: CGColor, in context: CGContext) {
        guard let line = line(string, font: font, color: color) else { return }
        context.saveGState()
        context.textMatrix = .identity
        // The strip is flipped; Core Text draws using an upright baseline coordinate system.
        context.translateBy(x: origin.x, y: origin.y + CTFontGetAscent(font))
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func line(_ string: String, font: CTFont, color: CGColor) -> CTLine? {
        let attributes = [kCTFontAttributeName as String: font, kCTForegroundColorAttributeName as String: color] as CFDictionary
        guard let value = CFAttributedStringCreate(nil, string as CFString, attributes) else { return nil }
        return CTLineCreateWithAttributedString(value)
    }
}
