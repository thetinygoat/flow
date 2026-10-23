import Foundation
import Observation
import SwiftUI

/// The Settings window's view of the config file. Changes show at once and are
/// written shortly after, so dragging a slider saves once rather than at every
/// step.
@Observable
final class SettingsStore {
    let file: URL
    private(set) var document: ConfigDocument
    /// What libghostty could not make sense of in the file, after the last load.
    private(set) var problems: [String] = []
    /// Why the last save failed, until one succeeds.
    private(set) var saveError: String?
    /// Settings this window shows that an included file overrides, so a
    /// change made here would not take effect.
    private(set) var overrides: [String] = []

    /// Set while the file exists but cannot be read as text. Settings then
    /// leaves it alone, since writing would replace whatever is in it.
    private(set) var readError: String?

    /// Runs after each write, to load the new file into the terminals.
    @ObservationIgnored var onSave: () -> Void = {}
    @ObservationIgnored private var savedText = ""
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    /// The changes not yet written, kept until a write succeeds and replayed
    /// onto the file whenever it is found changed on disk.
    @ObservationIgnored private var pendingChanges: [(inout ConfigDocument) -> Void] = []
    @ObservationIgnored private var themeCache: (theme: String?, documents: [ConfigDocument]) = (nil, [])

    init(file: URL = ConfigFile.url) {
        self.file = file
        document = ConfigDocument("")
        refreshFromDisk()
        findOverrides()
    }

    /// The reason the file is not being saved, if any.
    var fileError: String? {
        if let readError { return "Could not read the config file, so Settings leaves it unchanged: \(readError)" }
        return saveError.map { "Could not save the config file: \($0)" }
    }

    func value<Value>(_ setting: ConfigSetting<Value>) -> Value {
        document[setting.key].flatMap(setting.parse) ?? inherited(setting)
    }

    /// What applies when the file leaves an option out: the theme's value,
    /// since a theme file can set any option, or else Ghostty's default.
    private func inherited<Value>(_ setting: ConfigSetting<Value>) -> Value {
        themeDocuments.lazy.compactMap { $0[setting.key].flatMap(setting.parse) }.first ?? setting.defaultValue
    }

    /// The files of the light and dark themes, which Ghostty loads before
    /// this file, so a line here wins over them.
    private var themeDocuments: [ConfigDocument] {
        let theme = document[Option.theme]
        if themeCache.theme != theme {
            let choice = ThemeChoice(theme)
            let names = Array(Set([choice.light, choice.dark].compactMap { $0 })).sorted()
            let documents = names.compactMap(Themes.file(named:)).compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).map(ConfigDocument.init)
            }
            themeCache = (theme, documents)
        }
        return themeCache.documents
    }

    /// True when the file sets the option to something this window cannot
    /// show, which a change here would replace.
    func hasUnknownValue<Value>(_ setting: ConfigSetting<Value>) -> Bool {
        document[setting.key].map { setting.parse($0) == nil } ?? false
    }

    /// Setting an option to what applies without it removes it from the file;
    /// anything else is written, even Ghostty's default when a theme sets
    /// another value.
    func set<Value>(_ setting: ConfigSetting<Value>, _ value: Value) {
        let removable = value == inherited(setting)
        update { $0[setting.key] = removable ? nil : setting.format(value) }
    }

    func binding<Value>(_ setting: ConfigSetting<Value>) -> Binding<Value> {
        Binding(get: { self.value(setting) }, set: { self.set(setting, $0) })
    }

    func values(for key: String) -> [String] {
        document.values(for: key)
    }

    func setValues(_ values: [String], for key: String) {
        update { $0.setValues(values, for: key) }
    }

    /// Picks up edits made to the file elsewhere, unless a change made here is
    /// about to be written.
    func reload(problems: [String]) {
        self.problems = problems
        guard pendingSave == nil else { return }
        refreshFromDisk()
        // A change held back by a file that could not be read or written
        // goes out once the file is usable again.
        if readError == nil, !pendingChanges.isEmpty {
            scheduleSave()
        }
    }

    /// Writes any unsaved change now, retrying one that failed. True when the
    /// file was written, which has also reloaded it.
    @discardableResult
    func saveNow() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard !pendingChanges.isEmpty else { return false }
        return save()
    }

    private func update(_ change: @escaping (inout ConfigDocument) -> Void) {
        if pendingSave == nil {
            refreshFromDisk()
        }
        change(&document)
        pendingChanges.append(change)
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.save()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Shows the file as it is on disk, with the unsaved changes on top.
    private func refreshFromDisk() {
        let text: String
        do {
            text = try Self.read(file)
            readError = nil
        } catch {
            readError = error.localizedDescription
            return
        }
        guard text != savedText else { return }
        savedText = text
        var latest = ConfigDocument(text)
        pendingChanges.forEach { $0(&latest) }
        document = latest
        findOverrides()
    }

    @discardableResult
    private func save() -> Bool {
        refreshFromDisk()
        guard readError == nil else { return false }
        let text = document.text
        guard text != savedText else {
            pendingChanges = []
            saveError = nil
            return false
        }
        do {
            try ConfigFile.write(text, to: file)
        } catch {
            saveError = error.localizedDescription
            logger.error("could not save \(self.file.path, privacy: .public): \(error, privacy: .public)")
            return false
        }
        savedText = text
        pendingChanges = []
        saveError = nil
        findOverrides()
        onSave()
        return true
    }

    /// Included font families are added as fallbacks rather than replacing
    /// the ones set here, so they are not reported.
    private func findOverrides() {
        overrides = ConfigFile.includes(of: document, at: file).flatMap { include in
            Option.keys.filter { $0 != Option.fontFamily && !include.document.values(for: $0).isEmpty }.map { key in
                "\(key) is set in \(include.url.path.abbreviatingHome), which overrides the value in this window"
            }
        }
    }

    /// A missing file reads as a new one, so a change recreates it with the
    /// header. One that exists but is not UTF-8 text, or cannot be opened, is
    /// an error rather than an empty file.
    private static func read(_ file: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: file.path) else { return ConfigFile.header }
        return try String(contentsOf: file, encoding: .utf8)
    }
}
