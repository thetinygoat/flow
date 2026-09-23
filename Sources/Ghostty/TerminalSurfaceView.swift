import AppKit
import GhosttyKit

protocol TerminalSurfaceViewDelegate: AnyObject {
    /// Title or working directory changed.
    func surfaceDidChange(_ surface: TerminalSurfaceView)
    func surfaceDidFocus(_ surface: TerminalSurfaceView)
}

struct TerminalSurfaceConfiguration {
    var workingDirectory: String?
    var command: String?
    var fontSize: Float = 0

    func withCValue<T>(view: NSView, _ body: (inout ghostty_surface_config_s) -> T) -> T {
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(view).toOpaque()))
        config.userdata = Unmanaged.passUnretained(view).toOpaque()
        config.scale_factor = Double(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        config.font_size = fontSize
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        return workingDirectory.withCString { cwd in
            config.working_directory = cwd
            return command.withCString { cmd in
                config.command = cmd
                return body(&config)
            }
        }
    }
}

/// One terminal. Ghostty renders into this view with its own Metal layer and
/// runs the shell on its own threads. This class forwards AppKit events to
/// libghostty and exposes the state Ghostty reports back (title, pwd, cell size).
///
/// Input handling is adapted from Ghostty's SurfaceView_AppKit.swift.
final class TerminalSurfaceView: NSView {
    let id = UUID()
    weak var delegate: TerminalSurfaceViewDelegate?
    private(set) weak var runtime: GhosttyRuntime?
    private(set) var surface: ghostty_surface_t?
    /// The directory the shell was started in, until the shell reports its own.
    let initialWorkingDirectory: String?

    private(set) var title = "" {
        didSet { if title != oldValue { delegate?.surfaceDidChange(self) } }
    }
    var pwd: String? {
        didSet { if pwd != oldValue { delegate?.surfaceDidChange(self) } }
    }

    var workingDirectory: String? {
        pwd ?? initialWorkingDirectory
    }

    var needsAttention = false {
        didSet { if needsAttention != oldValue { delegate?.surfaceDidChange(self) } }
    }
    private var titleTimer: Timer?
    var cellSizeInPixels = NSSize.zero {
        didSet { scrollbar.cellHeight = cellSize.height }
    }

    /// Ghostty reports cells in pixels. Converting on read keeps the value right
    /// for surfaces that were sized before they had a window, and across moves
    /// between displays with different scales.
    var cellSize: NSSize {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return NSSize(width: cellSizeInPixels.width / scale, height: cellSizeInPixels.height / scale)
    }
    private(set) var focused = false

    private var cursor: NSCursor = .iBeam
    private let dimOverlay = PassthroughView()
    private let scrollbar = TerminalScrollbar()
    private let secureInputBadge = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure keyboard entry is on")!)
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var lastPerformKeyEvent: TimeInterval?
    private var leftButtonPressed = false
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var searchBar: SearchBarView?
    private var searchDebounce: Timer?

    override var acceptsFirstResponder: Bool { true }

    init(runtime: GhosttyRuntime, configuration: TerminalSurfaceConfiguration = .init()) {
        self.runtime = runtime
        self.initialWorkingDirectory = configuration.workingDirectory
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Command key-ups never reach the responder chain, and a click on an
        // unfocused surface should move focus without also reaching the shell.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handleLocalEvent(event) ?? event
        }
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, let window = self.window, notification.object as? NSWindow === window else { return }
                self.updateDisplay()
            },
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, let window = self.window, notification.object as? NSWindow === window else { return }
                self.updateOcclusion()
            },
            center.addObserver(forName: SecureInput.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateSecureInputBadge()
            },
        ]

        surface = configuration.withCValue(view: self) { config in
            ghostty_surface_new(runtime.app, &config)
        }
        if let surface {
            ghostty_surface_set_focus(surface, false)
        }
        runtime.register(self)
        updateTrackingAreas()

        dimOverlay.wantsLayer = true
        dimOverlay.isHidden = true
        dimOverlay.frame = bounds
        dimOverlay.autoresizingMask = [.width, .height]
        addSubview(dimOverlay)

        scrollbar.frame = bounds
        scrollbar.autoresizingMask = [.width, .height]
        scrollbar.isHidden = !runtime.config.showsScrollbar
        scrollbar.onScrollToRow = { [weak self] row in self?.perform(action: "scroll_to_row:\(row)") }
        addSubview(scrollbar)

        secureInputBadge.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        secureInputBadge.contentTintColor = .secondaryLabelColor
        secureInputBadge.isHidden = true
        secureInputBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secureInputBadge)
        NSLayoutConstraint.activate([
            secureInputBadge.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            secureInputBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    /// Set while the shell is reading a password, detected by Ghostty from the
    /// terminal's echo mode.
    var passwordInput = false {
        didSet {
            guard passwordInput != oldValue else { return }
            if passwordInput {
                SecureInput.shared.setScoped(ObjectIdentifier(self), focused: focused)
            } else {
                SecureInput.shared.removeScoped(ObjectIdentifier(self))
            }
        }
    }

    private func updateSecureInputBadge() {
        let indicate = runtime?.config.secureInputIndication ?? true
        secureInputBadge.isHidden = !(indicate && focused && SecureInput.shared.enabled)
    }

    /// Tints the pane to show it is not the focused split. Pass nil to clear.
    func setDimColor(_ color: NSColor?) {
        dimOverlay.layer?.backgroundColor = color?.cgColor
        dimOverlay.isHidden = color == nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        titleTimer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        searchDebounce?.invalidate()
        if passwordInput { SecureInput.shared.removeScoped(ObjectIdentifier(self)) }
        if let surface { ghostty_surface_free(surface) }
    }

    static func from(userdata: UnsafeMutableRawPointer?) -> TerminalSurfaceView {
        Unmanaged<TerminalSurfaceView>.fromOpaque(userdata!).takeUnretainedValue()
    }

    static func from(surface: ghostty_surface_t) -> TerminalSurfaceView? {
        ghostty_surface_userdata(surface).map { Unmanaged<TerminalSurfaceView>.fromOpaque($0).takeUnretainedValue() }
    }

    /// Shells often set the title several times in a row while starting up, so
    /// rapid changes are coalesced to avoid flicker.
    func setTitle(_ newTitle: String) {
        titleTimer?.invalidate()
        titleTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: false) { [weak self] _ in
            self?.title = newTitle
        }
    }

    var needsConfirmQuit: Bool {
        guard let surface else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    func updateConfig(_ config: GhosttyConfig) {
        scrollbar.isHidden = !config.showsScrollbar
        guard let surface else { return }
        ghostty_surface_update_config(surface, config.cValue)
    }

    /// Runs a keybinding action by name, e.g. `copy_to_clipboard` or `scroll_to_top`.
    @discardableResult
    func perform(action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count)) }
    }

    // MARK: Layout and focus

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateOcclusion()
        // Being detached while first responder loses focus without a
        // resignFirstResponder call, so the state is re-derived here.
        focusDidChange(window?.firstResponder === self)
        guard window != nil else { return }
        updateDisplay()
    }

    /// Hidden surfaces (other tabs, other workspaces, covered windows) tell
    /// Ghostty to stop rendering until they are visible again.
    private func updateOcclusion() {
        guard let surface else { return }
        let visible = window?.occlusionState.contains(.visible) ?? false
        ghostty_surface_set_occlusion(surface, visible)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sendSize(newSize)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        scrollbar.cellHeight = cellSize.height
        updateDisplay()
    }

    private func updateDisplay() {
        guard let window, let surface else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = window.backingScaleFactor
        CATransaction.commit()

        ghostty_surface_set_display_id(surface, window.screen?.displayID ?? 0)
        ghostty_surface_set_content_scale(surface, window.backingScaleFactor, window.backingScaleFactor)
        sendSize(frame.size)
    }

    private func sendSize(_ size: NSSize) {
        guard let surface, size.width > 0, size.height > 0 else { return }
        let backing = convertToBacking(size)
        ghostty_surface_set_size(surface, UInt32(backing.width), UInt32(backing.height))
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusDidChange(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusDidChange(false) }
        return accepted
    }

    private func focusDidChange(_ focused: Bool) {
        guard let surface, self.focused != focused else { return }
        self.focused = focused
        ghostty_surface_set_focus(surface, focused)
        if passwordInput {
            SecureInput.shared.setScoped(ObjectIdentifier(self), focused: focused)
        }
        updateSecureInputBadge()
        if focused { delegate?.surfaceDidFocus(self) }
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        // activeAlways so mouse reports keep flowing to unfocused surfaces.
        addTrackingArea(NSTrackingArea(
            rect: frame,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil))
    }

    // MARK: Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    func setMouseShape(_ shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT: cursor = .arrow
        case GHOSTTY_MOUSE_SHAPE_TEXT: cursor = .iBeam
        case GHOSTTY_MOUSE_SHAPE_GRAB: cursor = .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING: cursor = .closedHand
        case GHOSTTY_MOUSE_SHAPE_POINTER: cursor = .pointingHand
        case GHOSTTY_MOUSE_SHAPE_W_RESIZE: cursor = .resizeLeft
        case GHOSTTY_MOUSE_SHAPE_E_RESIZE: cursor = .resizeRight
        case GHOSTTY_MOUSE_SHAPE_N_RESIZE: cursor = .resizeUp
        case GHOSTTY_MOUSE_SHAPE_S_RESIZE: cursor = .resizeDown
        case GHOSTTY_MOUSE_SHAPE_NS_RESIZE: cursor = .resizeUpDown
        case GHOSTTY_MOUSE_SHAPE_EW_RESIZE: cursor = .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: cursor = .iBeamCursorForVerticalLayout
        case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU: cursor = .contextualMenu
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: cursor = .crosshair
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: cursor = .operationNotAllowed
        default: return
        }
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Local events

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyUp: return localEventKeyUp(event)
        case .leftMouseDown: return localEventLeftMouseDown(event)
        case .leftMouseUp: return localEventLeftMouseUp(event)
        default: return event
        }
    }

    private func isUnderMouse(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, let superview else { return false }
        return hitTest(superview.convert(event.locationInWindow, from: nil)) === self
    }

    private func localEventLeftMouseDown(_ event: NSEvent) -> NSEvent? {
        guard isUnderMouse(event), let window, window.firstResponder !== self else { return event }

        // The click only moves focus between surfaces, so the shell must not see it.
        if NSApp.isActive && window.isKeyWindow {
            window.makeFirstResponder(self)
            return nil
        }

        // The window itself is not key yet. AppKit still needs the event to
        // activate it, so it is passed on.
        window.makeFirstResponder(self)
        return event
    }

    /// Releases are matched to presses here rather than in mouseUp, because
    /// AppKit can deliver the release elsewhere when focus changed mid-click,
    /// and a press without a release leaves the terminal dragging a selection.
    private func localEventLeftMouseUp(_ event: NSEvent) -> NSEvent? {
        guard leftButtonPressed, let surface else { return event }
        leftButtonPressed = false
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, Ghostty.ghosttyMods(event.modifierFlags))
        ghostty_surface_mouse_pressure(surface, 0, 0)
        return event
    }

    private func localEventKeyUp(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.command), focused else { return event }
        keyUp(with: event)
        return nil
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        leftButtonPressed = true
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, Ghostty.ghosttyMods(event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        // Handled by the local event monitor.
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let button = Ghostty.mouseButton(fromNSEventButtonNumber: event.buttonNumber)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, button, Ghostty.ghosttyMods(event.modifierFlags))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let button = Ghostty.mouseButton(fromNSEventButtonNumber: event.buttonNumber)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, button, Ghostty.ghosttyMods(event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface,
              ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, Ghostty.ghosttyMods(event.modifierFlags))
        else { return super.rightMouseDown(with: event) }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface,
              ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, Ghostty.ghosttyMods(event.modifierFlags))
        else { return super.rightMouseUp(with: event) }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        sendMousePosition(event)
    }

    override func mouseExited(with event: NSEvent) {
        // While dragging, drag events keep reporting the position past the edge.
        guard let surface, NSEvent.pressedMouseButtons == 0 else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, Ghostty.ghosttyMods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, Ghostty.ghosttyMods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas
        if precision {
            x *= 2
            y *= 2
        }
        let mods = Ghostty.scrollMods(precision: precision, momentum: Ghostty.momentum(event.momentumPhase))
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    override func pressureChange(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard event.type == .rightMouseDown else { return nil }
        let menu = NSMenu()
        if let surface, ghostty_surface_has_selection(surface) {
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        return menu
    }

    @IBAction func copy(_ sender: Any?) {
        perform(action: "copy_to_clipboard")
    }

    @IBAction func paste(_ sender: Any?) {
        perform(action: "paste_from_clipboard")
    }

    @IBAction override func selectAll(_ sender: Any?) {
        perform(action: "select_all")
    }

    @IBAction func increaseFontSize(_ sender: Any?) {
        perform(action: "increase_font_size:1")
    }

    @IBAction func decreaseFontSize(_ sender: Any?) {
        perform(action: "decrease_font_size:1")
    }

    @IBAction func resetFontSize(_ sender: Any?) {
        perform(action: "reset_font_size")
    }

    @IBAction func toggleSplitZoom(_ sender: Any?) {
        perform(action: "toggle_split_zoom")
    }

    @IBAction func findInScrollback(_ sender: Any?) {
        perform(action: "start_search")
    }

    @IBAction func findNext(_ sender: Any?) {
        perform(action: "navigate_search:next")
    }

    @IBAction func findPrevious(_ sender: Any?) {
        perform(action: "navigate_search:previous")
    }

    @IBAction func useSelectionForFind(_ sender: Any?) {
        perform(action: "search_selection")
    }

    // MARK: Search

    /// Opens the find bar, or refocuses it when already open. A needle comes
    /// with `search_selection` and replaces whatever was typed.
    func startSearch(needle: String?) {
        let bar = searchBar ?? makeSearchBar()
        if let needle, !needle.isEmpty {
            bar.needle = needle
        }
        bar.focusField()
    }

    func endSearch() {
        guard let bar = searchBar else { return }
        searchDebounce?.invalidate()
        searchBar = nil
        let barHadFocus = (window?.firstResponder as? NSView)?.isDescendant(of: bar) == true
        bar.removeFromSuperview()
        if barHadFocus { window?.makeFirstResponder(self) }
    }

    func setScrollbar(total: Int, offset: Int, visibleRows: Int) {
        scrollbar.update(total: total, offset: offset, visibleRows: visibleRows)
    }

    func setSearchTotal(_ total: Int?) {
        searchBar?.total = total
    }

    func setSearchSelected(_ selected: Int?) {
        searchBar?.selected = selected
    }

    private func makeSearchBar() -> SearchBarView {
        let bar = SearchBarView()
        bar.onChange = { [weak self] needle in self?.searchChanged(needle) }
        bar.onNext = { [weak self] in self?.perform(action: "navigate_search:next") }
        bar.onPrevious = { [weak self] in self?.perform(action: "navigate_search:previous") }
        bar.onClose = { [weak self] in self?.perform(action: "end_search") }
        bar.onReturnToTerminal = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
        searchBar = bar
        return bar
    }

    /// Very short needles match nearly everything, so they wait for a pause in
    /// typing before searching the whole scrollback.
    private func searchChanged(_ needle: String) {
        searchDebounce?.invalidate()
        let search = { [weak self] in _ = self?.perform(action: "search:\(needle)") }
        if needle.isEmpty || needle.count >= 3 {
            search()
        } else {
            searchDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in search() }
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // Ghostty may want different modifiers for text translation (option-as-alt).
        let translationModsGhostty = Ghostty.eventModifierFlags(
            mods: ghostty_surface_key_translation_mods(surface, Ghostty.ghosttyMods(event.modifierFlags)))
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        // The original event object must be reused when nothing changed, or
        // Korean input breaks. AppKit appears to compare event identity somewhere.
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // interpretKeyEvents drives the input method. insertText collects into
        // the accumulator while it is non-nil, so composed text is sent once.
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedTextBefore = markedText.length > 0
        let keyboardIdBefore: String? = markedTextBefore ? nil : KeyboardLayout.id

        lastPerformKeyEvent = nil
        interpretKeyEvents([translationEvent])

        // A keyboard layout switch was consumed by the input method.
        if !markedTextBefore && keyboardIdBefore != KeyboardLayout.id {
            return
        }

        syncPreedit(clearIfNeeded: markedTextBefore)

        if let texts = keyTextAccumulator, !texts.isEmpty {
            for text in texts {
                _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            // Still composing if preedit is showing, or if this key just cleared
            // it (e.g. backspace during Japanese input cancels but must not delete).
            _ = keyAction(
                action,
                event: event,
                translationEvent: translationEvent,
                text: translationEvent.ghosttyCharacters,
                composing: markedText.length > 0 || markedTextBefore)
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    /// Command-key combinations arrive here before keyDown. Bindings are handled
    /// directly. Other command/control events are let through the responder chain
    /// once, and if they come back via doCommand they are sent to keyDown so
    /// Ghostty can encode them for the shell.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, focused, let surface else { return false }

        var flags = ghostty_binding_flags_e(0)
        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        let isBinding = (event.characters ?? "").withCString { ptr -> Bool in
            keyEvent.text = ptr
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }
        if isBinding {
            keyDown(with: event)
            return true
        }

        let equivalent: String
        switch event.charactersIgnoringModifiers {
        case "\r":
            guard event.modifierFlags.contains(.control) else { return false }
            equivalent = "\r"

        case "/":
            // Control-/ beeps in AppKit, so it is treated as control-_.
            guard event.modifierFlags.contains(.control),
                  event.modifierFlags.isDisjoint(with: [.shift, .command, .option]) else { return false }
            equivalent = "_"

        default:
            // Synthetic events (e.g. the escape AppKit makes from cmd+.) have a zero timestamp.
            if event.timestamp == 0 { return false }

            if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
                lastPerformKeyEvent = nil
                return false
            }

            if let lastPerformKeyEvent {
                self.lastPerformKeyEvent = nil
                if lastPerformKeyEvent == event.timestamp {
                    equivalent = event.characters ?? ""
                    break
                }
            }

            lastPerformKeyEvent = event.timestamp
            return false
        }

        let finalEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: equivalent,
            charactersIgnoringModifiers: equivalent,
            isARepeat: event.isARepeat,
            keyCode: event.keyCode)
        keyDown(with: finalEvent!)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        if hasMarkedText() { return }

        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        var action = GHOSTTY_ACTION_RELEASE
        if mods.rawValue & mod != 0 {
            // With the modifier held, this is a press only if the side that
            // changed is the side still down.
            let sidePressed: Bool
            switch event.keyCode {
            case 0x3C: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
            default: sidePressed = true
            }
            if sidePressed { action = GHOSTTY_ACTION_PRESS }
        }

        _ = keyAction(action, event: event)
    }

    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing

        // Control characters are encoded by Ghostty itself, so only printable text is passed.
        if let text, let first = text.utf8.first, first >= 0x20 {
            return text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        }
        return ghostty_surface_key(surface, keyEvent)
    }

    // MARK: Clipboard callbacks

    func readClipboard(_ location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?) -> Bool {
        guard let surface,
              let pasteboard = NSPasteboard.ghostty(location),
              let text = pasteboard.getOpinionatedStringContents() else { return false }
        text.withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, false) }
        return true
    }

    func confirmReadClipboard(_ text: UnsafePointer<CChar>?, state: UnsafeMutableRawPointer?, request: ghostty_clipboard_request_e) {
        guard let surface, let text else { return }
        let string = String(cString: text)
        let message = request == GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ
            ? "An application in the terminal is trying to read the clipboard."
            : "The text contains characters that could run commands when pasted."
        let confirmed = Self.confirm(title: "Potentially Unsafe Paste", message: message, preview: string, button: "Paste", in: window)
        (confirmed ? string : "").withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, true) }
    }

    func writeClipboard(_ location: ghostty_clipboard_e, content: UnsafePointer<ghostty_clipboard_content_s>?, count: Int, confirm: Bool) {
        guard let pasteboard = NSPasteboard.ghostty(location), let content, count > 0 else { return }
        let items: [(NSPasteboard.PasteboardType, String)] = (0..<count).compactMap { index in
            let item = content[index]
            guard let mime = item.mime, let data = item.data,
                  let type = NSPasteboard.PasteboardType(mimeType: String(cString: mime)) else { return nil }
            return (type, String(cString: data))
        }
        guard !items.isEmpty else { return }

        if confirm {
            guard let text = items.first(where: { $0.0 == .string })?.1,
                  Self.confirm(
                    title: "Application Wants to Write to the Clipboard",
                    message: "An application in the terminal is trying to write to the clipboard.",
                    preview: text, button: "Allow", in: window) else { return }
        }

        pasteboard.declareTypes(items.map(\.0), owner: nil)
        for (type, data) in items {
            pasteboard.setString(data, forType: type)
        }
    }

    private static func confirm(title: String, message: String, preview: String, button: String, in window: NSWindow?) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")

        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        if let textView = scroll.documentView as? NSTextView {
            textView.string = preview
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        }
        alert.accessoryView = scroll
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - NSTextInputClient

extension TerminalSurfaceView: NSTextInputClient {
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange() }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        guard let surface else { return NSRange() }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return NSRange() }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attributed as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: attributed)
        case let plain as String:
            markedText = NSMutableAttributedString(string: plain)
        default:
            return
        }

        // Outside of keyDown (e.g. a layout switch while composing) the preedit
        // must be pushed right away.
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let surface, range.length > 0 else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSAttributedString(string: String(cString: text.text))
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return NSRect(origin: frame.origin, size: .zero) }

        var x: Double = 0
        var y: Double = 0
        var width: Double = cellSize.width
        var height: Double = cellSize.height
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        // Dictation's microphone indicator needs a zero-width rect at the cursor.
        if range.length == 0, width > 0 {
            width = 0
            x += cellSize.width * Double(range.location + range.length)
        }

        let viewRect = NSRect(x: x, y: frame.height - y, width: width, height: max(height, cellSize.height))
        let windowRect = convert(viewRect, to: nil)
        guard let window else { return windowRect }
        return window.convertToScreen(windowRect)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil, let surface else { return }

        let chars: String
        switch string {
        case let attributed as NSAttributedString: chars = attributed.string
        case let plain as String: chars = plain
        default: return
        }

        unmarkText()

        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(chars)
            return
        }

        chars.withCString { ghostty_surface_text(surface, $0, UInt(chars.utf8.count)) }
    }

    /// Exists to avoid the beep for unhandled selectors and to send back
    /// command-key events that performKeyEquivalent deferred.
    override func doCommand(by selector: Selector) {
        if let lastPerformKeyEvent, let current = NSApp.currentEvent, lastPerformKeyEvent == current.timestamp {
            NSApp.sendEvent(current)
            return
        }

        switch selector {
        case #selector(moveToBeginningOfDocument(_:)): perform(action: "scroll_to_top")
        case #selector(moveToEndOfDocument(_:)): perform(action: "scroll_to_bottom")
        default: break
        }
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let string = markedText.string
            string.withCString { ghostty_surface_preedit(surface, $0, UInt(string.utf8.count)) }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}

/// A view that never takes mouse events, so overlays don't block the terminal.
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
