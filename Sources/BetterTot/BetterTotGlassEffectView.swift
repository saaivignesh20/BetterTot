import AppKit

#if compiler(>=6.2)
@available(macOS 26.0, *)
final class BetterTotGlassEffectView: NSGlassEffectView {
    init(content: NSView, cornerRadius: CGFloat) {
        super.init(frame: .zero)
        style = .regular
        self.cornerRadius = cornerRadius
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]
        content.frame = bounds
        contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        contentView?.intrinsicContentSize ?? super.intrinsicContentSize
    }

    override func layout() {
        super.layout()
        contentView?.frame = bounds
    }
}
#endif
