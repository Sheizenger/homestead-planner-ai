import Foundation
import HomesteadEngine

/// Search over the object catalog for the add-object palette (`+`, a
/// keyboard shortcut) — the one authoring path the web app never had at all
/// (see BACKLOG.md): a way to see the whole catalog and place something the
/// generator didn't.
public enum ObjectPalette {
    /// Matches on the catalog label or id, case-insensitively, substring
    /// rather than prefix — "shed" should find "Tool Shed". An empty query
    /// returns the whole catalog grouped by category, in `ZONE_CATEGORY_ORDER`
    /// then declaration order within it, so the palette has a sensible
    /// browsing order even before the user types anything.
    public static func search(_ query: String) -> [ObjectLibrary.Entry] {
        let ordered = ZONE_CATEGORY_ORDER.flatMap { ObjectLibrary.entries(in: ObjectCategory(zone: $0)!) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ordered }
        let needle = trimmed.lowercased()
        return ordered.filter {
            $0.label.lowercased().contains(needle) || $0.id.lowercased().contains(needle)
        }
    }
}
