//
//  WarningsListView.swift
//  Homestead
//
//  Reads ProjectModel.warnings(for:) directly — no new logic here, per
//  BACKLOG.md's stage 7 note that this panel needs none beyond what Core
//  already exposes.
//

import SwiftUI
import HomesteadEngine

struct WarningsListView: View {
    let warnings: [Warning]

    var body: some View {
        if warnings.isEmpty {
            ContentUnavailableView("No warnings", systemImage: "checkmark.circle", description: Text("This variant has no open issues."))
        } else {
            List(warnings, id: \.id) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: warning.severity))
                        .foregroundStyle(color(for: warning.severity))
                    Text(warning.message)
                        .font(.callout)
                }
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
