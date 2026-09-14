//
//  WarningsListView.swift
//  Homestead
//
//  Reads ProjectModel.warnings(for:) directly — no new logic here, per
//  BACKLOG.md's stage 7 note that this panel needs none beyond what Core
//  already exposes.
//
//  Selecting a warning highlights the objects it is about. A warning that
//  says "pool and goat paddock are too close" is only useful if you can see
//  which two it means: the plan can hold fifteen objects and the message
//  names them by label, not by position.
//

import SwiftUI
import HomesteadEngine

struct WarningsListView: View {
    let warnings: [Warning]
    @Binding var selectedWarningID: String?
    /// Returns what the fix did, or nil when there is no small answer —
    /// which the row then says, instead of a button that looks broken.
    var applyFix: (Warning) -> Resolve.Fix?

    @State private var declined: Set<String> = []

    var body: some View {
        if warnings.isEmpty {
            ContentUnavailableView("No warnings", systemImage: "checkmark.circle", description: Text("This variant has no open issues."))
        } else {
            List(warnings, id: \.id, selection: $selectedWarningID) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: warning.severity))
                        .foregroundStyle(color(for: warning.severity))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(warning.message)
                            .font(.callout)
                        if declined.contains(warning.id) {
                            Text("No small move fixes this one — try a different variant or a bigger plot.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let fix = warning.suggestedFix, !declined.contains(warning.id) {
                        Button(fix.label) {
                            if applyFix(warning) == nil { declined.insert(warning.id) }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .tag(warning.id)
            }
            // A warning that got fixed is gone, and the list is rebuilt from
            // scratch; a "no fix" note about a warning that no longer exists
            // would outlive its subject.
            .onChange(of: warnings.map(\.id)) { _, ids in
                declined.formIntersection(ids)
            }
        }
    }

    private func icon(for severity: WarningSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .caution: return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        }
    }

    private func color(for severity: WarningSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .caution: return .orange
        case .critical: return .red
        }
    }
}
