import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Esc leads home
//
// On iPhone and iPad, each press closes what's on top, then steps back, and a
// few presses from anywhere reach Triage. `EscapeStack` decides; this file gets
// the key to it. The Mac has its own Esc and these modifiers leave it alone.
//
// A key command is only heard along the responder chain from the first
// responder, and SwiftUI gives a plain screen none. So `EscapeCatcher`, a
// zero-size view controller, takes first responder whenever nothing is being
// typed in. A full-screen cover takes the presenter's views out of the window, so
// the root's catcher goes with them: each sheet and cover has its own.
//
// A focused field is first responder, the catcher (its sibling) drops out of the
// chain, and a SwiftUI TextField, TextEditor or .searchable keeps Esc for itself.
// So every field is an `EscapingField` or `EscapingEditor`, which claim Esc ahead
// of the text system: it lets go of the field and keeps the text. ⌘. goes every
// way Esc does, for keyboards with no Esc: nothing in iOS makes it Esc.
//
// With a monitor connected the catcher also takes every other key for
// `MonitorDesk`, the only one holding first responder here, so there's one catcher,
// not two to trade it. With no monitor it hears Esc and nothing else.

private struct EscapeStackKey: EnvironmentKey {
    @MainActor static let defaultValue = EscapeStack()
}

extension EnvironmentValues {
    var escapeStack: EscapeStack {
        get { self[EscapeStackKey.self] }
        set { self[EscapeStackKey.self] = newValue }
    }
}

extension View {
    /// The root of a window: `home` runs when nothing is left on top.
    @ViewBuilder
    func escapeRoot(_ stack: EscapeStack, home: @escaping () -> Void) -> some View {
        #if os(iOS)
        background(EscapeCatcherHost().frame(width: 0, height: 0).allowsHitTesting(false))
            .environment(\.escapeStack, stack)
            .onAppear {
                stack.base = home
                stack.monitorStep = { MonitorDisplay.shared.desk?.stepBackFromEscape() ?? false }
                stack.onSheets = { MonitorDisplay.shared.desk?.phoneSheetUp = $0 }
            }
        #else
        self
        #endif
    }

    /// Something shown over the screen that isn't a sheet of ours: Esc runs
    /// `close` while `active`.
    @ViewBuilder
    func escapeCloses(when active: Bool = true, _ close: @escaping () -> Void) -> some View {
        #if os(iOS)
        modifier(EscapeLayer(active: active, close: close))
        #else
        self
        #endif
    }

    /// The content of a sheet or full-screen cover.
    @ViewBuilder
    func escapeScreen(_ close: @escaping () -> Void) -> some View {
        #if os(iOS)
        modifier(EscapeLayer(active: true, isSheet: true, close: close))
            .background(EscapeCatcherHost().frame(width: 0, height: 0).allowsHitTesting(false))
        #else
        self
        #endif
    }

    /// The search field. On iOS not .searchable, whose field keeps Esc for itself.
    @ViewBuilder
    func mediaSearch(text: Binding<String>, prompt: String, shown: Bool = true) -> some View {
        #if os(iOS)
        safeAreaInset(edge: .top, spacing: 0) {
            if shown { HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                EscapingField(placeholder: prompt, text: text)
                if !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 6) }
        }
        #else
        if shown { searchable(text: text, prompt: prompt) } else { self }
        #endif
    }
}

// MARK: - Fields

/// One line of text Esc can leave. A plain TextField on the Mac.
struct EscapingField: View {
    let placeholder: String
    @Binding var text: String
    var bordered = false
    var autofocus = false
    var onSubmit: () -> Void = {}

    var body: some View {
        #if os(iOS)
        EscapingFieldRepresentable(placeholder: placeholder, text: $text, bordered: bordered,
                                   autofocus: autofocus, onSubmit: onSubmit)
        #else
        if bordered {
            TextField(placeholder, text: $text).textFieldStyle(.roundedBorder).onSubmit(onSubmit)
        } else {
            TextField(placeholder, text: $text).onSubmit(onSubmit)
        }
        #endif
    }
}

/// Several lines Esc can leave. A plain TextEditor on the Mac.
struct EscapingEditor: View {
    var placeholder = ""
    @Binding var text: String

    var body: some View {
        #if os(iOS)
        EscapingEditorRepresentable(text: $text)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
        #else
        TextEditor(text: $text)
        #endif
    }
}

#if os(iOS)

// MARK: - Layers and the catcher

private struct EscapeLayer: ViewModifier {
    @Environment(\.escapeStack) private var stack
    let active: Bool
    var isSheet = false
    let close: () -> Void

    @State private var id = UUID()
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onAppear { visible = true; sync(visible: true) }
            .onDisappear { visible = false; sync(visible: false) }
            .onChange(of: active) { sync(visible: visible) }
    }

    private func sync(visible: Bool) {
        if visible && active { stack.push(id, isSheet: isSheet, close: close) } else { stack.remove(id) }
    }
}

private struct EscapeCatcherHost: View {
    @Environment(\.escapeStack) private var stack

    var body: some View {
        EscapeCatcher(onEscape: stack.press)
    }
}

private struct EscapeCatcher: UIViewControllerRepresentable {
    let onEscape: () -> Void

    func makeUIViewController(context: Context) -> EscapeCatcherController {
        EscapeCatcherController()
    }

    func updateUIViewController(_ controller: EscapeCatcherController, context: Context) {
        controller.onEscape = onEscape
    }
}

final class EscapeCatcherController: UIViewController {
    var onEscape: () -> Void = {}
    private var reclaim: Timer?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let escape = EscapeChord.escape.keyCommand(action: #selector(escapePressed))
        // The monitor's own chords include ⌘.
        guard monitorDesk != nil else {
            return [escape, EscapeChord.commandPeriod.keyCommand(action: #selector(escapePressed))]
        }
        return [escape] + MonitorChords.commands(action: #selector(chord(_:)))
    }

    @objc private func escapePressed() { onEscape() }

    // MARK: The monitor's keys

    private var repeater = MonitorKeyRepeater()

    /// Only with a monitor there: without one, this catcher is only for Esc.
    private var monitorDesk: MonitorDesk? {
        MonitorDisplay.shared.desk.flatMap { $0.isConnected ? $0 : nil }
    }

    @objc private func chord(_ command: UIKeyCommand) {
        guard let press = MonitorChords.press(for: command) else { return }
        if press.matches(.escape) { onEscape() } else { monitorDesk?.handle(press) }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let desk = monitorDesk else {
            super.pressesBegan(presses, with: event)
            return
        }
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, !MonitorChords.comesAsCommand(key), let keyPress = MonitorPress(key),
                  desk.handle(keyPress) else {
                unhandled.insert(press)
                continue
            }
            repeater.start(keyPress, code: key.keyCode, desk: desk)
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == repeater.code }) { repeater.stop() }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        repeater.stop()
        super.pressesCancelled(presses, with: event)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Straight back from a field, so the next press isn't lost to the timer.
        for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(fieldEnded), name: name, object: nil)
        }
    }

    @objc private func fieldEnded() {
        DispatchQueue.main.async { [weak self] in self?.takeKeysIfFree() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        takeKeysIfFree()
        // A sheet going, or a video player or alert taking first responder,
        // leaves the keys somewhere that won't hand them on.
        reclaim?.invalidate()
        reclaim = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.takeKeysIfFree() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        reclaim?.invalidate()
        reclaim = nil
        repeater.stop()
    }

    /// Never from a field being typed in, nor from another catcher: a sheet's and
    /// the root's would trade it.
    private func takeKeysIfFree() {
        guard let window = view.window else { return }
        // First responder means nothing in a window that isn't key, and a monitor
        // coming and going can leave the phone's window that way.
        if monitorDesk != nil, !window.isKeyWindow { window.makeKey() }
        guard !isFirstResponder else { return }
        let holder = UIResponder.bestShotCurrentFirst()
        if !(holder is UIKeyInput), !(holder is EscapeCatcherController) { becomeFirstResponder() }
    }
}

extension UIResponder {
    private static weak var bestShotFound: UIResponder?
    @objc private func bestShotCapture() { UIResponder.bestShotFound = self }

    /// The window's first responder, found the only public way there is.
    static func bestShotCurrentFirst() -> UIResponder? {
        bestShotFound = nil
        UIApplication.shared.sendAction(#selector(bestShotCapture), to: nil, from: nil, for: nil)
        return bestShotFound
    }
}

// MARK: - UIKit fields

extension EscapeChord {
    /// With priority over the text system, and a held key is one press: it mustn't
    /// run on through what's behind.
    func keyCommand(action: Selector) -> UIKeyCommand {
        let c = UIKeyCommand(input: self == .escape ? UIKeyCommand.inputEscape : input,
                             modifierFlags: command ? .command : [], action: action)
        c.wantsPriorityOverSystemBehavior = true
        c.repeatBehavior = .nonRepeatable
        return c
    }
}

private struct EscapingFieldRepresentable: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let bordered: Bool
    let autofocus: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EscapingTextField {
        let field = EscapingTextField()
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = bordered ? .roundedRect : .none
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // One line tall, always: a wrapped UIKit field otherwise takes every point offered.
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        if autofocus { DispatchQueue.main.async { field.becomeFirstResponder() } }
        return field
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: EscapingTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: field.intrinsicContentSize.height)
    }

    func updateUIView(_ field: EscapingTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EscapingFieldRepresentable
        init(_ parent: EscapingFieldRepresentable) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            parent.onSubmit()
            return false
        }
    }
}

/// Declares Esc and ⌘. on the field itself, ahead of the text system.
final class EscapingTextField: UITextField {
    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + EscapeChord.declared(composing: markedTextRange != nil)
            .map { $0.keyCommand(action: #selector(letGo)) }
    }

    @objc private func letGo() { resignFirstResponder() }
}

private struct EscapingEditorRepresentable: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> EscapingTextView {
        let view = EscapingTextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: EscapingTextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text { view.text = text }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textViewDidChange(_ view: UITextView) { text.wrappedValue = view.text }
    }
}

final class EscapingTextView: UITextView {
    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + EscapeChord.declared(composing: markedTextRange != nil)
            .map { $0.keyCommand(action: #selector(letGo)) }
    }

    @objc private func letGo() { resignFirstResponder() }
}

#endif

// MARK: - Asking for a word

/// A name or tag. A sheet rather than an alert: an alert's field can't claim Esc.
/// Esc keeps what's typed for next time; Cancel clears it.
struct TextPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    let action: String
    @Binding var text: String
    let onCommit: () -> Void

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                EscapingField(placeholder: placeholder, text: $text, autofocus: true) {
                    if !isEmpty { commit() }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { text = ""; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action, action: commit).disabled(isEmpty)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 160)
        .presentationDetents([.height(180)])
        .escapeScreen { dismiss() }
    }

    private func commit() {
        onCommit()
        dismiss()
    }
}
