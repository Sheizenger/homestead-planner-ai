//
//  HomesteadApp.swift
//  Homestead
//
//  The store lives here rather than in ContentView so the File and Edit
//  menus can reach it — a plan you can't save or undo isn't a plan you'd
//  trust with an afternoon's work.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HomesteadCore

@main
struct HomesteadApp: App {
    @State private var store = PlanStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .defaultSize(width: 1280, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Plan") { newPlan() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { openPlan() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { savePlan(forcingPrompt: false) }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!store.hasUnsavedChanges && store.fileURL != nil)
                Button("Save As…") { savePlan(forcingPrompt: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("Redo") { store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
            }
        }
    }

    private func newPlan() {
        guard confirmDiscardingChanges() else { return }
        store.reset()
    }

    private func openPlan() {
        guard confirmDiscardingChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.open(from: url)
        } catch {
            present(error, title: "Couldn’t open that plan")
        }
    }

    private func savePlan(forcingPrompt: Bool) {
        if !forcingPrompt, store.fileURL != nil {
            do { try store.saveToExistingFile() } catch { present(error, title: "Couldn’t save") }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(store.model.document.name).homestead.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.save(to: url) } catch { present(error, title: "Couldn’t save") }
    }

    /// Unsaved work is the one thing this app can lose irreversibly, so
    /// discarding it always asks first.
    private func confirmDiscardingChanges() -> Bool {
        guard store.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "This plan has changes that haven’t been saved."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func present(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
