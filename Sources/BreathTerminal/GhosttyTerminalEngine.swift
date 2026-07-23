import AppKit
import BreathCore
import CoreText
import Foundation

#if BREATH_HAS_GHOSTTY && canImport(GhosttyKit)
import GhosttyKit

enum GhosttyScrollInput {
    static func modifiers(
        hasPreciseScrollingDeltas: Bool,
        momentumPhase: NSEvent.Phase
    ) -> ghostty_input_scroll_mods_t {
        let precision = hasPreciseScrollingDeltas ? 1 : 0
        let momentum: Int
        if momentumPhase.contains(.began) {
            momentum = Int(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
        } else if momentumPhase.contains(.stationary) {
            momentum = Int(GHOSTTY_MOUSE_MOMENTUM_STATIONARY.rawValue)
        } else if momentumPhase.contains(.changed) {
            momentum = Int(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
        } else if momentumPhase.contains(.ended) {
            momentum = Int(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
        } else if momentumPhase.contains(.cancelled) {
            momentum = Int(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
        } else if momentumPhase.contains(.mayBegin) {
            momentum = Int(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue)
        } else {
            momentum = Int(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
        }
        // ghostty_input_scroll_mods_t packs precision into bit 0 and
        // the three-bit momentum value into bits 1...3.
        return ghostty_input_scroll_mods_t(precision | (momentum << 1))
    }
}

@MainActor
private func requestPasteConfirmation(for value: String, in window: NSWindow?) -> Bool {
    let alert = NSAlert()
    alert.messageText = "粘贴多行或控制字符？"
    alert.informativeText = "这段内容可能一次执行多条命令。请确认内容可信后再粘贴。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "粘贴")
    alert.addButton(withTitle: "取消")
    alert.window.appearance = window?.effectiveAppearance
        ?? NSApp.keyWindow?.effectiveAppearance
    if let window {
        // A synchronous sheet would deadlock the libghostty completion callback;
        // use the native modal confirmation while keeping the callback on MainActor.
        window.makeKeyAndOrderFront(nil)
    }
    return alert.runModal() == .alertFirstButtonReturn
}

private func ghosttyRuntimeWakeup(_ userdata: UnsafeMutableRawPointer?) {
    guard let userdata else { return }
    let retainedHost = Unmanaged<GhosttyRuntimeHost>
        .fromOpaque(userdata)
        .retain()
    let address = UInt(bitPattern: retainedHost.toOpaque())
    DispatchQueue.main.async {
        guard let userdata = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let host = Unmanaged<GhosttyRuntimeHost>.fromOpaque(userdata).takeRetainedValue()
        ghostty_app_tick(host.app)
    }
}

public enum GhosttyTerminalError: Error, Equatable {
    case initializationFailed
    case configurationFailed
    case surfaceCreationFailed
}

@MainActor
public final class GhosttyTerminalEngine: TerminalEngine, TerminalViewProviding, @unchecked Sendable {
    private let configurationURL: URL
    private let agentSocketURL: URL
    private let host: GhosttyRuntimeHost
    private let synchronizeRendering: Bool
    private var settings: TerminalSettings
    private var views: [TerminalPaneID: GhosttySurfaceView] = [:]
    private var processExitHandler: (@Sendable (TerminalPaneID) -> Void)?
    public let usesLibghostty = true

    public init(
        configurationDirectory: URL,
        agentSocketURL: URL,
        settings: TerminalSettings = TerminalSettings(),
        synchronizeRendering: Bool = true
    ) throws {
        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        configurationURL = configurationDirectory.appendingPathComponent("terminal.ghostty")
        self.agentSocketURL = agentSocketURL
        self.synchronizeRendering = synchronizeRendering
        self.settings = settings
        try Self.writeConfiguration(
            settings,
            synchronizeRendering: synchronizeRendering,
            to: configurationURL
        )
        host = try GhosttyRuntimeHost(configurationURL: configurationURL)
    }

    public func open(_ launch: TerminalLaunch) async throws {
        if views[launch.paneID] != nil { return }
        let view = try GhosttySurfaceView(
            app: host.app,
            launch: launch,
            fontSize: Float(settings.fontSize),
            agentSocketURL: agentSocketURL
        )
        view.processExitHandler = { [weak self, weak view] in
            guard let self, let view,
                  self.views[launch.paneID] === view
            else { return }
            view.processExitHandler = nil
            self.views.removeValue(forKey: launch.paneID)
            view.closeSurface()
            self.processExitHandler?(launch.paneID)
        }
        views[launch.paneID] = view
    }

    public func close(_ paneID: TerminalPaneID) async {
        guard let view = views.removeValue(forKey: paneID) else { return }
        view.processExitHandler = nil
        view.closeSurface()
    }

    public func apply(settings: TerminalSettings) async {
        do {
            try Self.writeConfiguration(
                settings,
                synchronizeRendering: synchronizeRendering,
                to: configurationURL
            )
            try host.updateConfiguration(at: configurationURL)
            self.settings = settings
        } catch {
            return
        }
    }

    public func view(for paneID: TerminalPaneID) -> NSView? {
        views[paneID]
    }

    public func handleShortcutKeyDown(
        _ event: NSEvent,
        for paneID: TerminalPaneID
    ) -> Bool {
        views[paneID]?.handleShortcutKeyDown(event) ?? false
    }

    public func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async {
        processExitHandler = handler
    }

    static func writeConfiguration(
        _ settings: TerminalSettings,
        synchronizeRendering: Bool,
        to url: URL
    ) throws {
        let requestedFontFamily = settings.fontFamily
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let availableFontFamilies = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        let fontFamily = availableFontFamilies
            .contains(requestedFontFamily)
            ? requestedFontFamily
            : "Menlo"
        let colors = settings.colorTheme.palette
        let cursor = switch settings.cursorStyle {
        case .block: "block"
        case .bar: "bar"
        case .underline: "underline"
        }
        let palette = colors.ansiColors.enumerated()
            .map { "palette = \($0.offset)=\($0.element.ghosttyHex)" }
            .joined(separator: "\n")
        let shortcutUnbinds = BreathShortcut.registeredByBreath
            .flatMap(\.ghosttyUnbindConfigurationLines)
            .joined(separator: "\n")
        let contents = """
        font-family = \(fontFamily)
        font-size = \(settings.fontSize)
        \(palette)
        background = \(colors.background.ghosttyHex)
        foreground = \(colors.foreground.ghosttyHex)
        cursor-color = \(colors.cursor.ghosttyHex)
        cursor-text = \(colors.cursorText.ghosttyHex)
        selection-background = \(colors.selectionBackground.ghosttyHex)
        selection-foreground = \(colors.selectionForeground.ghosttyHex)
        cursor-style = \(cursor)
        window-vsync = \(synchronizeRendering)
        window-decoration = false
        confirm-close-surface = false
        # Breath routes these shortcuts; Ghostty host actions must not consume them.
        \(shortcutUnbinds)
        """
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

private extension TerminalRGBColor {
    var ghosttyHex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private extension BreathShortcut {
    var ghosttyUnbindConfigurationLines: [String] {
        var modifierNames: [String] = []
        if modifiers.contains(.command) { modifierNames.append("super") }
        if modifiers.contains(.control) { modifierNames.append("ctrl") }
        if modifiers.contains(.option) { modifierNames.append("alt") }
        if modifiers.contains(.shift) { modifierNames.append("shift") }

        var keys = [String(character)]
        if let digit = character.wholeNumberValue {
            // Ghostty registers numbered tabs as Unicode and physical keys.
            keys.append("digit_\(digit)")
        }
        return keys.map { key in
            "keybind = \((modifierNames + [key]).joined(separator: "+"))=unbind"
        }
    }
}

@MainActor
private final class GhosttyRuntimeHost {
    private static var initialized = false

    nonisolated(unsafe) private var appStorage: ghostty_app_t?
    nonisolated(unsafe) private var config: ghostty_config_t
    var app: ghostty_app_t { appStorage! }

    init(configurationURL: URL) throws {
        if !Self.initialized {
            guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
                throw GhosttyTerminalError.initializationFailed
            }
            Self.initialized = true
        }
        guard let config = Self.loadConfiguration(at: configurationURL) else {
            throw GhosttyTerminalError.configurationFailed
        }
        self.config = config
        appStorage = nil

        var runtime = ghostty_runtime_config_s(
            userdata: nil,
            supports_selection_clipboard: false,
            wakeup_cb: ghosttyRuntimeWakeup,
            action_cb: { app, target, action in
                guard let app else { return false }
                return GhosttyRuntimeHost.handleAction(app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, _, state in
                GhosttyRuntimeHost.readClipboard(userdata, state: state)
            },
            confirm_read_clipboard_cb: { userdata, value, state, request in
                GhosttyRuntimeHost.confirmClipboard(
                    userdata,
                    value: value,
                    state: state,
                    request: request
                )
            },
            write_clipboard_cb: { userdata, _, content, count, confirm in
                GhosttyRuntimeHost.writeClipboard(
                    userdata,
                    content: content,
                    count: count,
                    confirm: confirm
                )
            },
            close_surface_cb: { userdata, processAlive in
                GhosttyRuntimeHost.closeSurface(userdata, processAlive: processAlive)
            }
        )
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        guard let app = ghostty_app_new(&runtime, config) else {
            ghostty_config_free(config)
            throw GhosttyTerminalError.initializationFailed
        }
        appStorage = app
        ghostty_app_set_focus(app, NSApp.isActive)
    }

    deinit {
        if let appStorage { ghostty_app_free(appStorage) }
        ghostty_config_free(config)
    }

    func updateConfiguration(at url: URL) throws {
        guard let newConfig = Self.loadConfiguration(at: url) else {
            throw GhosttyTerminalError.configurationFailed
        }
        ghostty_app_update_config(app, newConfig)
        let oldConfig = config
        config = newConfig
        ghostty_config_free(oldConfig)
    }

    private static func loadConfiguration(at url: URL) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        ghostty_config_load_file(config, url.path)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
        return config
    }

    private static func handleAction(
        _ app: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let view = view(for: target.target.surface)
        else {
            return false
        }
        switch action.tag {
        case GHOSTTY_ACTION_RENDER:
            ghostty_surface_draw(target.target.surface)
        case GHOSTTY_ACTION_SET_TITLE:
            if let title = action.action.set_title.title {
                view.terminalTitle = String(cString: title)
            }
        case GHOSTTY_ACTION_PWD:
            if let path = action.action.pwd.pwd {
                view.workingDirectory = String(cString: path)
            }
        case GHOSTTY_ACTION_CELL_SIZE:
            view.cellSize = CGSize(
                width: Double(action.action.cell_size.width),
                height: Double(action.action.cell_size.height)
            )
        case GHOSTTY_ACTION_SELECTION_CHANGED:
            view.needsDisplay = true
        default:
            return false
        }
        return true
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let view = view(from: userdata),
              let surface = view.surface,
              let value = NSPasteboard.general.string(forType: .string)
        else {
            return false
        }
        value.withCString { pointer in
            ghostty_surface_complete_clipboard_request(surface, pointer, state, false)
        }
        return true
    }

    private static func confirmClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        value: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard request == GHOSTTY_CLIPBOARD_REQUEST_PASTE,
              let view = view(from: userdata),
              view.surface != nil,
              let value
        else {
            return
        }
        let paste = String(cString: value)
        DispatchQueue.main.async { [weak view] in
            guard let view, let surface = view.surface else { return }
            let confirmed = requestPasteConfirmation(for: paste, in: view.window)
            paste.withCString { pointer in
                ghostty_surface_complete_clipboard_request(
                    surface,
                    pointer,
                    state,
                    confirmed
                )
            }
        }
    }

    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int,
        confirm: Bool
    ) {
        guard !confirm, content != nil else { return }
        for index in 0..<count {
            let item = content![index]
            guard String(cString: item.mime) == "text/plain" else { continue }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(cString: item.data), forType: .string)
            return
        }
    }

    private static func closeSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        guard let view = view(from: userdata) else { return }
        DispatchQueue.main.async {
            view.processExited = !processAlive
            if !processAlive {
                view.processExitHandler?()
            }
        }
    }

    private static func view(from userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func view(for surface: ghostty_surface_t?) -> GhosttySurfaceView? {
        guard let surface, let userdata = ghostty_surface_userdata(surface) else { return nil }
        return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }
}

@MainActor
private final class GhosttySurfaceView: NSView, @preconcurrency NSTextInputClient {
    nonisolated(unsafe) fileprivate var surface: ghostty_surface_t?
    fileprivate var terminalTitle = ""
    fileprivate var workingDirectory: String?
    fileprivate var cellSize = CGSize(width: 8, height: 16)
    fileprivate var processExited = false
    fileprivate var processExitHandler: (() -> Void)?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    init(
        app: ghostty_app_t,
        launch: TerminalLaunch,
        fontSize: Float,
        agentSocketURL: URL
    ) throws {
        // libghostty allocates its initial Metal surface during construction;
        // a zero-sized host view causes that allocation to fail.
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.workingDirectory = launch.workingDirectory

        var environment = launch.environment
        environment["BREATH_AGENT_SOCKET"] = agentSocketURL.path
        let command = ([launch.executable] + launch.arguments)
            .map(Self.shellQuote)
            .joined(separator: " ")
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(self).toOpaque()
            )
        )
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        config.font_size = fontSize
        config.wait_after_command = false
        // Breath splits independent terminal surfaces in SwiftUI. They are not
        // children of a libghostty surface, so each one uses window context.
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        let created: ghostty_surface_t? = launch.workingDirectory.withCString { workingDirectory in
            config.working_directory = workingDirectory
            return command.withCString { command in
                config.command = command
                return Self.withEnvironment(environment) { variables in
                    config.env_vars = variables.baseAddress
                    config.env_var_count = variables.count
                    return ghostty_surface_new(app, &config)
                }
            }
        }
        guard let created else {
            throw GhosttyTerminalError.surfaceCreationFailed
        }
        surface = created
        setSurfaceFocused(false)
        updateSurfaceGeometry()
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    func closeSurface() {
        guard let surface else { return }
        ghostty_surface_free(surface)
        self.surface = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        setSurfaceFocused(window?.firstResponder === self)
        updateSurfaceGeometry()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceGeometry()
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        setSurfaceFocused(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        setSurfaceFocused(false)
        return super.resignFirstResponder()
    }

    private func setSurfaceFocused(_ isFocused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, isFocused)
    }

    private func updateSurfaceGeometry() {
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let backing = convertToBacking(bounds)
        let xScale = backing.width / bounds.width
        let yScale = backing.height / bounds.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)
        ghostty_surface_set_size(
            surface,
            UInt32(max(1, backing.width)),
            UInt32(max(1, backing.height))
        )
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    override func rightMouseDown(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(
            surface,
            point.x,
            bounds.height - point.y,
            ghosttyModifiers(event.modifierFlags)
        )
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(
            surface,
            event.scrollingDeltaX,
            event.scrollingDeltaY,
            GhosttyScrollInput.modifiers(
                hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
                momentumPhase: event.momentumPhase
            )
        )
    }

    private func sendMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) {
        guard let surface else { return }
        ghostty_surface_mouse_button(
            surface,
            state,
            button,
            ghosttyModifiers(event.modifierFlags)
        )
    }

    override func keyDown(with event: NSEvent) {
        guard surface != nil else { return }
        let hadMarkedText = hasMarkedText()
        keyTextAccumulator = []
        interpretKeyEvents([event])
        let committed = keyTextAccumulator ?? []
        keyTextAccumulator = nil
        syncPreedit(clearIfNeeded: hadMarkedText)

        if committed.isEmpty {
            _ = sendKey(
                event,
                action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS,
                text: event.terminalCharacters,
                composing: hasMarkedText() || hadMarkedText
            )
        } else {
            for text in committed {
                _ = sendKey(
                    event,
                    action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS,
                    text: text,
                    composing: false
                )
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = sendKey(event, action: GHOSTTY_ACTION_RELEASE, text: nil, composing: false)
    }

    func handleShortcutKeyDown(_ event: NSEvent) -> Bool {
        guard surface != nil else { return false }
        return sendKey(
            event,
            action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS,
            text: event.terminalCharacters,
            composing: false
        )
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased()
        else {
            return false
        }
        if characters == "c" {
            copy(nil)
            return true
        }
        if characters == "v" {
            paste(nil)
            return true
        }
        return false
    }

    @objc func copy(_ sender: Any?) {
        guard let surface else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text else { return }
        let bytes = UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len))
        let value = String(decoding: bytes, as: UTF8.self)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard let surface,
              let value = NSPasteboard.general.string(forType: .string)
        else {
            return
        }
        guard !TerminalPasteSafety.requiresConfirmation(value)
                || requestPasteConfirmation(for: value, in: window)
        else { return }
        value.withCString { pointer in
            ghostty_surface_text(surface, pointer, UInt(value.lengthOfBytes(using: .utf8)))
        }
    }

    private func sendKey(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        text: String?,
        composing: Bool
    ) -> Bool {
        guard let surface else { return false }
        var key = event.terminalKey(action: action)
        key.composing = composing
        guard let text, !text.isEmpty,
              !(text.count == 1 && (text.utf8.first ?? 0) < 0x20)
        else {
            return ghostty_surface_key(surface, key)
        }
        return text.withCString { pointer in
            key.text = pointer
            return ghostty_surface_key(surface, key)
        }
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        hasMarkedText()
            ? NSRange(location: 0, length: markedText.length)
            : NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        NSRange(location: 0, length: 0)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attributed = string as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: attributed)
        } else if let string = string as? String {
            markedText = NSMutableAttributedString(string: string)
        }
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func unmarkText() {
        markedText.mutableString.setString("")
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        nil
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = Double(cellSize.height)
        if let surface {
            ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        }
        let local = NSRect(
            x: CGFloat(x),
            y: bounds.height - CGFloat(y),
            width: CGFloat(width),
            height: max(CGFloat(height), cellSize.height)
        )
        guard let window else { return convert(local, to: nil) }
        return window.convertToScreen(convert(local, to: nil))
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let value: String
        if let attributed = string as? NSAttributedString {
            value = attributed.string
        } else if let string = string as? String {
            value = string
        } else {
            return
        }
        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(value)
        } else if let surface {
            value.withCString { pointer in
                ghostty_surface_text(surface, pointer, UInt(value.lengthOfBytes(using: .utf8)))
            }
        }
    }

    override func doCommand(by selector: Selector) {}

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if hasMarkedText() {
            let value = markedText.string
            value.withCString { pointer in
                ghostty_surface_preedit(surface, pointer, UInt(value.lengthOfBytes(using: .utf8)))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func withEnvironment<T>(
        _ environment: [String: String],
        body: (inout UnsafeMutableBufferPointer<ghostty_env_var_s>) throws -> T
    ) rethrows -> T {
        let pairs = environment.sorted { $0.key < $1.key }
        let keys = pairs.map { strdup($0.key)! }
        let values = pairs.map { strdup($0.value)! }
        defer {
            keys.forEach { free($0) }
            values.forEach { free($0) }
        }
        var variables = zip(keys, values).map {
            ghostty_env_var_s(key: UnsafePointer($0.0), value: UnsafePointer($0.1))
        }
        return try variables.withUnsafeMutableBufferPointer { buffer in
            var buffer = buffer
            return try body(&buffer)
        }
    }
}

private func ghosttyModifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var raw = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
    return ghostty_input_mods_e(raw)
}

private extension NSEvent {
    func terminalKey(action: ghostty_input_action_e) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.mods = ghosttyModifiers(modifierFlags)
        key.consumed_mods = ghosttyModifiers(
            modifierFlags.subtracting([.control, .command])
        )
        key.keycode = UInt32(keyCode)
        key.text = nil
        key.composing = false
        key.unshifted_codepoint = characters(byApplyingModifiers: [])?
            .unicodeScalars.first?.value ?? 0
        return key
    }

    var terminalCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(
                    byApplyingModifiers: modifierFlags.subtracting(.control)
                )
            }
            if (0xF700...0xF8FF).contains(scalar.value) { return nil }
        }
        return characters
    }
}

#else

public enum GhosttyTerminalError: Error, Equatable {
    case frameworkUnavailable
}

@MainActor
public final class GhosttyTerminalEngine: TerminalEngine, TerminalViewProviding, @unchecked Sendable {
    private var views: [TerminalPaneID: NSView] = [:]
    public let usesLibghostty = false

    public init(
        configurationDirectory: URL,
        agentSocketURL: URL,
        settings: TerminalSettings = TerminalSettings(),
        synchronizeRendering: Bool = true
    ) throws {}

    public func open(_ launch: TerminalLaunch) async throws {
        let label = NSTextField(labelWithString: "请先运行 scripts/build-libghostty.sh")
        label.alignment = .center
        views[launch.paneID] = label
    }

    public func close(_ paneID: TerminalPaneID) async {
        views.removeValue(forKey: paneID)
    }

    public func apply(settings: TerminalSettings) async {}

    public func view(for paneID: TerminalPaneID) -> NSView? {
        views[paneID]
    }
}

#endif
