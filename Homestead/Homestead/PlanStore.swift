//
//  PlanStore.swift
//  Homestead
//
//  Owns the document, its undo stack and its file. ProjectModel deliberately
//  has no undo of its own — UndoManager doesn't exist outside Apple
//  platforms, so HomesteadCore can't depend on it and stay Linux-testable
//  (see AGENTS.md). Wiring it is the app layer's job, and this is it.
//

import Foundation
import SwiftUI
import HomesteadEngine
import HomesteadCore

@Observable
final class PlanStore {
    let model: ProjectModel
    private(set) var fileURL: URL?
    private(set) var savedDocument: PlanDocument

    @ObservationIgnored private let undoManager = UndoManager()

    init(document: PlanDocument = .blank(name: "My Homestead", widthM: 60, heightM: 45)) {
        model = ProjectModel(document: document)
        savedDocument = document
    }

    var hasUnsavedChanges: Bool { model.document != savedDocument }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    /// Runs `edit`, having first recorded the document as it was. Every
    /// mutating action in the UI goes through here, which is what makes undo
    /// uniform: the snapshot is taken at the same point for all of them, and
    /// nothing has to describe its own inverse.
    func edit(_ name: String, _ edit: () -> Void) {
        let before = model.document
        edit()
        guard model.document != before else { return }
        register(name: name, restoring: before)
    }

    /// A drag produces a mutation per frame, which would otherwise fill the
    /// undo stack with dozens of one-pixel steps. The snapshot is taken once
    /// when the gesture starts and registered once when it ends, so the whole
    /// drag undoes as the single action it looks like.
    private(set) var isInteracting = false
    @ObservationIgnored private var interactiveSnapshot: PlanDocument?

    func beginInteractiveEdit() {
        guard !isInteracting else { return }
        isInteracting = true
        interactiveSnapshot = model.document
    }

    func endInteractiveEdit(_ name: String) {
        defer {
            isInteracting = false
            interactiveSnapshot = nil
        }
        guard let before = interactiveSnapshot, model.document != before else { return }
        register(name: name, restoring: before)
    }

    private func register(name: String, restoring snapshot: PlanDocument) {
        undoManager.setActionName(name)
        undoManager.registerUndo(withTarget: self) { store in
            let redoSnapshot = store.model.document
            store.model.restore(snapshot)
            store.register(name: name, restoring: redoSnapshot)
        }
    }

    func undo() { undoManager.undo() }
    func redo() { undoManager.redo() }

    /// Starts over. Deliberately not undoable: the confirmation prompt is the
    /// safeguard, and an undo stack pointing into a discarded document would
    /// be a way to half-resurrect it.
    func reset() {
        let fresh = PlanDocument.blank(name: "My Homestead", widthM: 60, heightM: 45)
        model.restore(fresh)
        savedDocument = fresh
        fileURL = nil
        undoManager.removeAllActions()
    }

    // MARK: - Files

    func open(from url: URL) throws {
        let document = try PlanDocumentCodec.decode(Data(contentsOf: url))
        model.restore(document)
        savedDocument = document
        fileURL = url
        undoManager.removeAllActions()
    }

    func save(to url: URL) throws {
        let document = model.document
        try PlanDocumentCodec.encode(document).write(to: url, options: .atomic)
        savedDocument = document
        fileURL = url
    }

    func saveToExistingFile() throws {
        guard let fileURL else { return }
        try save(to: fileURL)
    }
}
