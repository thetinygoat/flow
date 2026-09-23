import AppKit
import GhosttyKit

/// The host-side decisions libghostty delegates to the app: anything that is
/// about windows, tabs, or splits rather than a single terminal surface.
protocol GhosttyRuntimeDelegate: AnyObject {
    func runtimeWantsNewWorkspace(_ runtime: GhosttyRuntime)
    func runtime(_ runtime: GhosttyRuntime, wantsNewTabFrom surface: TerminalSurfaceView?)
    func runtime(_ runtime: GhosttyRuntime, wantsSplit direction: SplitDirection, from surface: TerminalSurfaceView) -> Bool
    func runtime(_ runtime: GhosttyRuntime, wantsClose surface: TerminalSurfaceView)
    func runtime(_ runtime: GhosttyRuntime, wantsGotoTab target: ghostty_action_goto_tab_e)
    func runtime(_ runtime: GhosttyRuntime, wantsGotoSplit direction: PaneNavigation, from surface: TerminalSurfaceView)
    func runtime(_ runtime: GhosttyRuntime, wantsResizeSplit direction: ResizeDirection, amount: Int, from surface: TerminalSurfaceView)
    func runtime(_ runtime: GhosttyRuntime, wantsEqualizeSplitsFrom surface: TerminalSurfaceView)
    func runtime(_ runtime: GhosttyRuntime, wantsToggleZoomFrom surface: TerminalSurfaceView)
    func runtime(_ runtime: GhosttyRuntime, wantsSecureKeyboardEntry enabled: Bool)
    func runtimeWantsOpenConfig(_ runtime: GhosttyRuntime)
    func runtime(_ runtime: GhosttyRuntime, wantsNotification title: String, body: String, from surface: TerminalSurfaceView)
    func runtime(_ runtime: GhosttyRuntime, didFinish command: CommandFinish, in surface: TerminalSurfaceView)
}

/// Owns the single `ghostty_app_t` and receives its callbacks. Every libghostty
/// call must happen on the main thread. The wakeup callback is the only one
/// that arrives from other threads, so it hops to main before ticking.
final class GhosttyRuntime {
    weak var delegate: GhosttyRuntimeDelegate?
    var onConfigChange: (() -> Void)?
    private(set) var config: GhosttyConfig
    private(set) var app: ghostty_app_t!
    private let surfaces = NSHashTable<TerminalSurfaceView>.weakObjects()
    private var observers: [NSObjectProtocol] = []

    init() throws {
        config = try GhosttyConfig()

        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: { userdata in
                let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata!).takeUnretainedValue()
                DispatchQueue.main.async { ghostty_app_tick(runtime.app) }
            },
            action_cb: { app, target, action in
                GhosttyRuntime.dispatch(app: app!, target: target, action: action)
            },
            read_clipboard_cb: { userdata, location, state in
                TerminalSurfaceView.from(userdata: userdata).readClipboard(location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, text, state, request in
                TerminalSurfaceView.from(userdata: userdata).confirmReadClipboard(text, state: state, request: request)
            },
            write_clipboard_cb: { userdata, location, content, count, confirm in
                TerminalSurfaceView.from(userdata: userdata).writeClipboard(location, content: content, count: count, confirm: confirm)
            },
            close_surface_cb: { userdata, _ in
                let surface = TerminalSurfaceView.from(userdata: userdata)
                guard let runtime = surface.runtime else { return }
                runtime.delegate?.runtime(runtime, wantsClose: surface)
            })

        guard let app = ghostty_app_new(&runtimeConfig, config.cValue) else {
            throw GhosttyError.apiFailed
        }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                ghostty_app_keyboard_changed(self.app)
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                ghostty_app_set_focus(self.app, true)
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                ghostty_app_set_focus(self.app, false)
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        ghostty_app_free(app)
    }

    var needsConfirmQuit: Bool {
        ghostty_app_needs_confirm_quit(app)
    }

    func register(_ surface: TerminalSurfaceView) {
        surfaces.add(surface)
    }

    func reloadConfig() {
        guard let newConfig = try? GhosttyConfig() else { return }
        config = newConfig
        ghostty_app_update_config(app, newConfig.cValue)
        for surface in surfaces.allObjects {
            surface.updateConfig(newConfig)
        }
        onConfigChange?()
    }

    // MARK: Actions

    private static func dispatch(app: ghostty_app_t, target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(ghostty_app_userdata(app)!).takeUnretainedValue()
        let surface: TerminalSurfaceView? = target.tag == GHOSTTY_TARGET_SURFACE
            ? TerminalSurfaceView.from(surface: target.target.surface)
            : nil
        return runtime.handle(action, surface: surface)
    }

    private func handle(_ action: ghostty_action_s, surface: TerminalSurfaceView?) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_QUIT:
            NSApp.terminate(nil)

        case GHOSTTY_ACTION_NEW_WINDOW:
            delegate?.runtimeWantsNewWorkspace(self)

        case GHOSTTY_ACTION_NEW_TAB:
            delegate?.runtime(self, wantsNewTabFrom: surface)

        case GHOSTTY_ACTION_NEW_SPLIT:
            guard let surface, let delegate else { return false }
            return delegate.runtime(self, wantsSplit: SplitDirection(action.action.new_split), from: surface)

        case GHOSTTY_ACTION_CLOSE_TAB, GHOSTTY_ACTION_CLOSE_WINDOW:
            guard let surface else { return false }
            delegate?.runtime(self, wantsClose: surface)

        case GHOSTTY_ACTION_GOTO_TAB:
            delegate?.runtime(self, wantsGotoTab: action.action.goto_tab)

        case GHOSTTY_ACTION_GOTO_SPLIT:
            guard let surface else { return false }
            delegate?.runtime(self, wantsGotoSplit: PaneNavigation(action.action.goto_split), from: surface)

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            guard let surface else { return false }
            let resize = action.action.resize_split
            delegate?.runtime(self, wantsResizeSplit: ResizeDirection(resize.direction), amount: Int(resize.amount), from: surface)

        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            guard let surface else { return false }
            delegate?.runtime(self, wantsToggleZoomFrom: surface)

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            guard let surface else { return false }
            delegate?.runtime(self, wantsEqualizeSplitsFrom: surface)

        case GHOSTTY_ACTION_SET_TITLE:
            guard let surface else { return false }
            surface.setTitle(action.action.set_title.title.map { String(cString: $0) } ?? "")

        case GHOSTTY_ACTION_PWD:
            guard let surface else { return false }
            surface.pwd = action.action.pwd.pwd.map { String(cString: $0) }

        case GHOSTTY_ACTION_CELL_SIZE:
            guard let surface else { return false }
            surface.cellSizeInPixels = NSSize(
                width: Int(action.action.cell_size.width),
                height: Int(action.action.cell_size.height))

        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            guard let surface else { return false }
            let notification = action.action.desktop_notification
            delegate?.runtime(
                self,
                wantsNotification: notification.title.map { String(cString: $0) } ?? "",
                body: notification.body.map { String(cString: $0) } ?? "",
                from: surface)

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            guard let surface else { return false }
            let finished = action.action.command_finished
            delegate?.runtime(
                self,
                didFinish: CommandFinish(
                    exitCode: finished.exit_code < 0 ? nil : Int(finished.exit_code),
                    duration: .nanoseconds(Int64(clamping: finished.duration))),
                in: surface)

        case GHOSTTY_ACTION_SCROLLBAR:
            guard let surface else { return false }
            let scrollbar = action.action.scrollbar
            surface.setScrollbar(total: Int(scrollbar.total), offset: Int(scrollbar.offset), visibleRows: Int(scrollbar.len))

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            guard let surface else { return false }
            surface.setMouseShape(action.action.mouse_shape)

        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            NSCursor.setHiddenUntilMouseMoves(action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN)

        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()

        case GHOSTTY_ACTION_OPEN_URL:
            let openURL = action.action.open_url
            guard let bytes = openURL.url,
                  let string = String(data: Data(bytes: bytes, count: Int(openURL.len)), encoding: .utf8),
                  let url = URL(string: string) else { return false }
            NSWorkspace.shared.open(url)

        case GHOSTTY_ACTION_RELOAD_CONFIG:
            reloadConfig()

        case GHOSTTY_ACTION_OPEN_CONFIG:
            delegate?.runtimeWantsOpenConfig(self)

        case GHOSTTY_ACTION_SECURE_INPUT:
            let mode = action.action.secure_input
            if let surface {
                guard config.autoSecureInput else { return false }
                surface.passwordInput = mode.applied(to: surface.passwordInput)
            } else {
                delegate?.runtime(self, wantsSecureKeyboardEntry: mode.applied(to: SecureInput.shared.global))
            }

        // Search actions can arrive while a key event is still being handled,
        // so focus changes wait for the next turn of the run loop.
        case GHOSTTY_ACTION_START_SEARCH:
            guard let surface else { return false }
            let needle = action.action.start_search.needle.map { String(cString: $0) }
            DispatchQueue.main.async { surface.startSearch(needle: needle) }

        case GHOSTTY_ACTION_END_SEARCH:
            guard let surface else { return false }
            DispatchQueue.main.async { surface.endSearch() }

        case GHOSTTY_ACTION_SEARCH_TOTAL:
            guard let surface else { return false }
            let total = action.action.search_total.total
            surface.setSearchTotal(total >= 0 ? Int(total) : nil)

        case GHOSTTY_ACTION_SEARCH_SELECTED:
            guard let surface else { return false }
            let selected = action.action.search_selected.selected
            surface.setSearchSelected(selected >= 0 ? Int(selected) : nil)

        case GHOSTTY_ACTION_TOGGLE_FULLSCREEN:
            guard let window = surface?.window else { return false }
            window.toggleFullScreen(nil)

        case GHOSTTY_ACTION_TOGGLE_MAXIMIZE:
            guard let window = surface?.window else { return false }
            window.zoom(nil)

        case GHOSTTY_ACTION_CONFIG_CHANGE, GHOSTTY_ACTION_RENDERER_HEALTH, GHOSTTY_ACTION_COLOR_CHANGE:
            break

        default:
            logger.debug("unhandled action \(action.tag.rawValue)")
            return false
        }
        return true
    }
}

extension SplitDirection {
    init(_ c: ghostty_action_split_direction_e) {
        switch c {
        case GHOSTTY_SPLIT_DIRECTION_LEFT: self = .left
        case GHOSTTY_SPLIT_DIRECTION_DOWN: self = .down
        case GHOSTTY_SPLIT_DIRECTION_UP: self = .up
        default: self = .right
        }
    }
}

extension PaneNavigation {
    init(_ c: ghostty_action_goto_split_e) {
        switch c {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: self = .previous
        case GHOSTTY_GOTO_SPLIT_UP: self = .up
        case GHOSTTY_GOTO_SPLIT_LEFT: self = .left
        case GHOSTTY_GOTO_SPLIT_DOWN: self = .down
        case GHOSTTY_GOTO_SPLIT_RIGHT: self = .right
        default: self = .next
        }
    }
}

extension ResizeDirection {
    init(_ c: ghostty_action_resize_split_direction_e) {
        switch c {
        case GHOSTTY_RESIZE_SPLIT_UP: self = .up
        case GHOSTTY_RESIZE_SPLIT_DOWN: self = .down
        case GHOSTTY_RESIZE_SPLIT_LEFT: self = .left
        default: self = .right
        }
    }
}

extension ghostty_action_secure_input_e {
    func applied(to current: Bool) -> Bool {
        switch self {
        case GHOSTTY_SECURE_INPUT_ON: true
        case GHOSTTY_SECURE_INPUT_OFF: false
        default: !current
        }
    }
}
