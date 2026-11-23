import GhosttyKit
import XCTest

final class KeyBindingsTests: XCTestCase {
    private static let initialized = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)

    private func key(_ text: String) -> KeyTrigger {
        KeyTrigger(text)!
    }

    private func bindings(_ text: String, includes: [String] = []) -> KeyBindings {
        KeyBindings(document: ConfigDocument(text), includes: includes.map(ConfigDocument.init))
    }

    private func command(_ action: String) -> KeyboardShortcuts.Command {
        KeyboardShortcuts.command(for: action)!
    }

    func testReadsKeybindValuesTheWayGhosttyDoes() {
        XCTAssertEqual(Keybind("global:unconsumed:super+a=new_tab"), .bind(trigger: key("super+a"), triggerText: "super+a", action: "new_tab"))
        XCTAssertEqual(Keybind("ctrl+a>n=new_tab"), .bind(trigger: nil, triggerText: "ctrl+a>n", action: "new_tab"))
        XCTAssertEqual(Keybind(" clear "), .clear)
        XCTAssertNil(Keybind("super+a"))
    }

    func testALaterLineWins() {
        XCTAssertEqual(KeyBindings.defaults.shortcut(for: "toggle_workspace_palette"), key("super+p"))
        let moved = bindings("keybind = super+p=toggle_agent_palette\n")
        XCTAssertEqual(moved.shortcut(for: "toggle_agent_palette"), key("super+p"))
        XCTAssertNil(moved.shortcut(for: "toggle_workspace_palette"))
        XCTAssertNil(bindings("keybind = super+p=new_tab\n").shortcut(for: "toggle_workspace_palette"), "taken by another action")
        XCTAssertNil(bindings("keybind = shift+super+r=unbind\n").shortcut(for: "rename_workspace"))
        XCTAssertNil(bindings("keybind = clear\n").shortcut(for: "toggle_agent_palette"))
    }

    func testIncludedFilesCannotBindFlowsCommands() {
        let bindings = bindings("", includes: ["keybind = super+y=toggle_agent_palette\nkeybind = super+u=toggle_command_palette\n"])
        XCTAssertEqual(bindings.shortcut(for: "toggle_agent_palette"), key("super+i"))
        XCTAssertEqual(bindings.shortcut(for: "toggle_command_palette"), key("super+u"))
    }

    func testLibghosttyGetsFlowsKeysUnbound() {
        XCTAssertEqual(Keybind.ghosttyValues(for: "cmd+t=toggle_agent_palette"), ["cmd+t=unbind"])
        XCTAssertEqual(Keybind.ghosttyValues(for: "super+1=rename_workspace"), ["super+1=unbind", "super+digit_1=unbind"])
        XCTAssertNil(Keybind.ghosttyValues(for: "super+u=toggle_command_palette"), "Ghostty's own action")
    }

    // MARK: Settings

    func testFlowsCommandsGetOneLine() {
        var document = ConfigDocument("font-size = 13\n")
        document.setShortcut(key("ctrl+super+a"), for: command("toggle_agent_palette"))
        XCTAssertEqual(document.text, "font-size = 13\nkeybind = ctrl+super+a=toggle_agent_palette\n")
        document.setShortcut(key("super+i"), for: command("toggle_agent_palette"))
        XCTAssertEqual(document.text, "font-size = 13\n", "back to its default, so nothing to write")
        document.setShortcut(nil, for: command("rename_workspace"))
        XCTAssertEqual(document.text, "font-size = 13\nkeybind = shift+super+r=unbind\n")
        document.resetShortcut(for: command("rename_workspace"))
        XCTAssertEqual(document.text, "font-size = 13\n")
    }

    func testTheTabAndPanePaletteLosesGhosttysDefault() {
        var document = ConfigDocument("")
        document.setShortcut(key("alt+super+p"), for: command("toggle_command_palette"))
        XCTAssertEqual(document.text, "keybind = shift+super+p=unbind\nkeybind = alt+super+p=toggle_command_palette\n")
        XCTAssertTrue(document.hasShortcutLines(for: command("toggle_command_palette")))
        document.resetShortcut(for: command("toggle_command_palette"))
        XCTAssertEqual(document.text, "")
    }

    func testAKeyAnotherCommandHadMovesToThisOne() {
        var document = ConfigDocument("")
        document.setShortcut(key("super+p"), for: command("toggle_agent_palette"))
        let bindings = KeyBindings(document: document)
        XCTAssertEqual(bindings.command(using: key("super+p")), command("toggle_agent_palette"))
        XCTAssertNil(bindings.shortcut(for: "toggle_workspace_palette"))
    }

    // MARK: libghostty

    /// The tab and pane palette is Ghostty's, so its default has to be
    /// Ghostty's; the others' actions have to be unknown to Ghostty, or it
    /// would run them before Flow could.
    func testGhosttyAgreesOnWhichCommandsAreItsOwn() throws {
        XCTAssertEqual(Self.initialized, GHOSTTY_SUCCESS)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let flows = KeyboardShortcuts.changeable.filter(\.isFlows)
        try (["keybind = super+shift+p=unbind\n"] + flows.map { "keybind = super+f1=\($0.action)\n" }).joined()
            .write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let config = try XCTUnwrap(ghostty_config_new())
        defer { ghostty_config_free(config) }
        ghostty_config_load_file(config, file.path)
        ghostty_config_finalize(config)
        XCTAssertEqual(Int(ghostty_config_diagnostics_count(config)), flows.count)
        let trigger = ghostty_config_trigger(config, "toggle_command_palette", 22)
        XCTAssertTrue(trigger.tag == GHOSTTY_TRIGGER_PHYSICAL && trigger.key.physical == GHOSTTY_KEY_UNIDENTIFIED,
                      "⇧⌘P is Ghostty's only key for it")
    }
}
