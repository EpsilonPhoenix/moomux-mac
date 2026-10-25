import GhosttyTerminal
import UIKit

/// The bar over the phone's keyboard in an attached pane.
///
/// libghostty-spm draws one of its own, but its items are a closed enum and
/// its look is four colours — no room for Moomux's own buttons. The package
/// supports a host drawing its own (`+PublicSticky`, `sendKey`), so this is
/// that: one glass pill, text for the modifiers and icons for the rest, with
/// Ctrl and Alt riding the package's own sticky state so a tap still arms the
/// next key whatever the system keyboard sends.
///
/// Ceiling: there are no punctuation keys (`| ~ /`); they are one tap away on
/// the system keyboard.
@MainActor
final class PaneKeyBar: UIView {
    /// Pasted into the pane, then Return unless `submit` is false — a command
    /// that takes an argument is left open, with a trailing space, for the user
    /// to finish. Edit the list to change the menu; nothing else reads it.
    static let snippets: [(text: String, submit: Bool)] = [
        ("/clear", true), ("/compact", true), ("continue", true), ("y", true),
        ("/spawn ", false),
    ]

    weak var terminal: UITerminalView? {
        didSet {
            terminal?.setStickyModifierChangeHandler { [weak self] in self?.refresh() }
            refresh()
        }
    }
    var onNewSession: () -> Void = {}
    var onChanges: () -> Void = {}

    private var arrowPad: PaneArrowPad?
    private let height: CGFloat = 44
    private let pill = UIVisualEffectView(effect: PaneKeyBar.glass())
    private var modifiers: [(TerminalPublicStickyModifier, UIButton)] = []

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 52))
        autoresizingMask = .flexibleWidth
        backgroundColor = .clear
        // The pane is always dark whatever the system theme, so the bar is too.
        overrideUserInterfaceStyle = .dark
        build()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("not from a nib") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height + 8)
    }

    // MARK: Layout

    private func build() {
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.clipsToBounds = true
        pill.layer.cornerCurve = .continuous
        pill.layer.cornerRadius = height / 2
        addSubview(pill)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pill.topAnchor.constraint(equalTo: topAnchor),
            pill.heightAnchor.constraint(equalToConstant: height),
        ])

        let row = UIStackView(arrangedSubviews: [
            modifier("Ctrl", .ctrl),
            key("Esc") { $0.sendKey(.escape) },
            key("Tab") { $0.sendKey(.tab) },
            spacer(),
            icon("dpad", "Arrow Pad") { [weak self] view in self?.toggleArrowPad(in: view) },
            icon("doc.on.clipboard", "Paste") {
                // The package's own paste: text, or an image/file as a path,
                // and it commits an open IME composition first.
                $0.resetStickyModifiers()
                $0.paste(nil)
            },
            snippetMenu(),
            icon("plus.bubble", "New Session") { [weak self] _ in self?.onNewSession() },
            icon("plus.forwardslash.minus", "View Changes") { [weak self] _ in self?.onChanges() },
            spacer(),
            modifier("Alt", .alt),
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.alignment = .center
        row.spacing = 0

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        // Outside the scroller: hiding the keyboard must stay reachable
        // however far the row has been scrolled.
        let hide = icon("keyboard.chevron.compact.down", "Hide Keyboard") { $0.resignFirstResponder() }
        let outer = UIStackView(arrangedSubviews: [scroll, hide])
        outer.translatesAutoresizingMaskIntoConstraints = false
        outer.alignment = .fill
        outer.spacing = 0
        pill.contentView.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -6),
            outer.topAnchor.constraint(equalTo: pill.contentView.topAnchor),
            outer.bottomAnchor.constraint(equalTo: pill.contentView.bottomAnchor),
        ])
    }

    private func toggleArrowPad(in view: UITerminalView) {
        if let arrowPad {
            arrowPad.removeFromSuperview()
            self.arrowPad = nil
        } else {
            let pad = PaneArrowPad(terminal: view)
            pad.show(in: view)
            arrowPad = pad
        }
    }

    private static func glass() -> UIVisualEffect {
        if #available(iOS 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            // Glass takes its colour from what is behind it, which here is the
            // app's light background strip; tint it to the terminal's dark.
            effect.tintColor = UIColor.black.withAlphaComponent(0.7)
            return effect
        }
        return UIBlurEffect(style: .systemThickMaterial)
    }

    // MARK: Buttons

    private func spacer() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 10).isActive = true
        return view
    }

    private func base(_ label: String, _ action: @escaping () -> Void) -> UIButton {
        let button = UIButton(configuration: .plain())
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = label
        button.tintColor = .label
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: height).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func text(_ title: String, on button: UIButton) {
        var config = button.configuration ?? .plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 7, bottom: 0, trailing: 7)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
        ]))
        button.configuration = config
    }

    private func key(_ title: String, _ send: @escaping (UITerminalView) -> Void) -> UIButton {
        let button = base(title) { [weak self] in if let view = self?.terminal { send(view) } }
        text(title, on: button)
        return button
    }

    private func icon(_ symbol: String, _ label: String,
                      _ send: @escaping (UITerminalView) -> Void) -> UIButton {
        let button = base(label) { [weak self] in if let view = self?.terminal { send(view) } }
        var config = button.configuration ?? .plain()
        config.image = UIImage(systemName: symbol,
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17))
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        button.configuration = config
        return button
    }

    private func modifier(_ title: String, _ which: TerminalPublicStickyModifier) -> UIButton {
        let button = base(title) { [weak self] in self?.terminal?.toggleStickyModifier(which) }
        text(title, on: button)
        modifiers.append((which, button))
        return button
    }

    /// A menu rather than a button per snippet: the row is already as wide as
    /// a phone. Return is a keystroke, so it submits even to a program that
    /// treats pasted newlines as text.
    private func snippetMenu() -> UIButton {
        let button = icon("text.append", "Snippets") { _ in }
        button.menu = UIMenu(children: Self.snippets.map { snippet in
            UIAction(title: snippet.text.trimmingCharacters(in: .whitespaces) + (snippet.submit ? "" : "…")) { [weak self] _ in
                guard let view = self?.terminal else { return }
                // An armed Ctrl would otherwise turn the Return into Ctrl+Return.
                view.resetStickyModifiers()
                view.paste(text: snippet.text)
                if snippet.submit { view.sendKey(.enter) }
            }
        })
        button.showsMenuAsPrimaryAction = true
        return button
    }

    /// Ctrl and Alt wear a filled capsule while armed or locked, as the
    /// package's own bar does with its blue.
    private func refresh() {
        for (which, button) in modifiers {
            let state = terminal?.stickyActivation(for: which) ?? .inactive
            var config = button.configuration ?? .plain()
            config.background.backgroundColor = state == .inactive ? .clear : .systemBlue
            config.background.cornerRadius = 16
            config.background.backgroundInsets = NSDirectionalEdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2)
            config.baseForegroundColor = state == .inactive ? .label : .white
            button.configuration = config
        }
    }
}
