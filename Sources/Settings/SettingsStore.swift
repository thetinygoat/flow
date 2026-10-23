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

    /// Runs after each write, to load the new file into the terminals.
    @ObservationIgnored var onSave: () -> Void = {}
    @ObservationIgnored private var savedText: String
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    /// The changes waiting to be saved, replayed onto the file if it was
    /// edited elsewhere in the meantime.
    @ObservationIgnored private var pendingChanges: [(inout ConfigDocument) -> Void] = []

    init(file: URL = ConfigFile.url) {
        self.file = file
        savedText = Self.read(file)
        document = ConfigDocument(savedText)
    }

    func value<Value>(_ setting: ConfigSetting<Value>) -> Value {
        document[setting.key].flatMap(setting.parse) ?? setting.defaultValue
    }

    /// Setting an option to its default removes it from the file.
    func set<Value>(_ setting: ConfigSetting<Value>, _ value: Value) {
        update { $0[setting.key] = value == setting.defaultValue ? nil : setting.format(value) }
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
    /// still waiting to be written.
    func reload(problems: [String]) {
        self.problems = problems
        guard pendingSave == nil else { return }
        let text = Self.read(file)
        guard text != savedText else { return }
        savedText = text
        document = ConfigDocument(text)
    }

    func saveNow() {
        guard let pendingSave else { return }
        pendingSave.cancel()
        self.pendingSave = nil
        save()
    }

    private func update(_ change: @escaping (inout ConfigDocument) -> Void) {
        if pendingSave == nil {
            let text = Self.read(file)
            if text != savedText {
                savedText = text
                document = ConfigDocument(text)
            }
        }
        change(&document)
        pendingChanges.append(change)
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.save()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func save() {
        let onDisk = Self.read(file)
        if onDisk != savedText {
            var latest = ConfigDocument(onDisk)
            pendingChanges.forEach { $0(&latest) }
            document = latest
            savedText = onDisk
        }
        pendingChanges = []
        let text = document.text
        guard text != savedText else { return }
        do {
            try ConfigFile.write(text, to: file)
            savedText = text
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            logger.error("could not save \(self.file.path, privacy: .public): \(error, privacy: .public)")
            return
        }
        onSave()
    }

    private static func read(_ file: URL) -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }
}
