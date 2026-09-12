//
//  CategoryStyle.swift
//  Homestead
//
//  The plan's palette, ported verbatim from the web app's
//  `src/domain/categories.ts` CATEGORY_STYLES — including its dark variants,
//  which is what the first pass was missing: it hardcoded near-white fills,
//  so the canvas stayed glaring white inside a dark-mode window.
//
//  Both apps reading the same numbers is the point; a second palette invented
//  here would drift the moment either side is touched.
//

import SwiftUI
import HomesteadEngine

extension Color {
    /// `#rrggbb`, the form the web palette is written in.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct CategoryStyle {
    let fill: Color
    let stroke: Color

    static func of(_ category: ObjectCategory, _ scheme: ColorScheme) -> CategoryStyle {
        let (lightFill, lightStroke, darkFill, darkStroke) = palette(category)
        return scheme == .dark
            ? CategoryStyle(fill: Color(hex: darkFill), stroke: Color(hex: darkStroke))
            : CategoryStyle(fill: Color(hex: lightFill), stroke: Color(hex: lightStroke))
    }

    private static func palette(_ category: ObjectCategory) -> (UInt32, UInt32, UInt32, UInt32) {
        switch category {
        case .residential:     return (0xe4dccb, 0x8a7a58, 0x3a3527, 0xc8b88a)
        case .access:          return (0xd9d4c9, 0x8a8474, 0x33312b, 0xa9a48f)
        case .foodAnnual:      return (0xd7e4c5, 0x5f7d3a, 0x2b331f, 0x9dbf78)
        case .foodPerennial:   return (0xc9dfc4, 0x3f6b3a, 0x213328, 0x7fae76)
        case .greenhouse:      return (0xcfe6e6, 0x3f7d7d, 0x1f3333, 0x7fbdbd)
        case .animal:          return (0xe8d9c3, 0x8a5f2f, 0x332a1c, 0xc9a06b)
        case .utility:         return (0xdcdcdc, 0x6b6b6b, 0x2e2e2e, 0xa3a3a3)
        case .water:           return (0xc3d9e8, 0x2f5f8a, 0x1c2a33, 0x6ba3c9)
        case .energy:          return (0xe8e0c3, 0x8a7a2f, 0x332f1c, 0xc9b96b)
        case .storage:         return (0xddd2c3, 0x7d5f3f, 0x2f271e, 0xbfa076)
        case .leisure:         return (0xe0d3e6, 0x6b4a7d, 0x2b2233, 0xa97fc9)
        case .futureExpansion: return (0xf0f0f0, 0x999999, 0x262626, 0x777777)
        // Fences and paths aren't zone categories in the web palette; they
        // follow "access", which is what they are.
        case .fence, .path:    return (0xd9d4c9, 0x8a8474, 0x33312b, 0xa9a48f)
        }
    }

    static func label(_ category: ObjectCategory) -> String {
        switch category {
        case .residential: return "Residential"
        case .access: return "Access & paths"
        case .foodAnnual: return "Annual crops"
        case .foodPerennial: return "Orchard & berries"
        case .greenhouse: return "Greenhouse"
        case .animal: return "Animals"
        case .utility: return "Utilities"
        case .water: return "Water"
        case .energy: return "Energy"
        case .storage: return "Storage"
        case .leisure: return "Leisure"
        case .futureExpansion: return "Future expansion"
        case .fence: return "Fence"
        case .path: return "Path"
        }
    }
}

/// Everything that isn't a plan object: the sheet the plan is drawn on.
struct CanvasChrome {
    let background: Color
    let plotFill: Color
    let plotStroke: Color
    let grid: Color
    let furniture: Color
    let label: Color

    static func of(_ scheme: ColorScheme) -> CanvasChrome {
        scheme == .dark
            ? CanvasChrome(
                background: Color(hex: 0x1a1a18),
                plotFill: Color(hex: 0x232320),
                plotStroke: Color(hex: 0x6f6a5c),
                grid: Color(hex: 0x2c2c28),
                furniture: Color(hex: 0x9a9488),
                label: Color(hex: 0xdcd7c9)
            )
            : CanvasChrome(
                background: Color(hex: 0xf2f0ea),
                plotFill: Color(hex: 0xfbfaf6),
                plotStroke: Color(hex: 0x8a8474),
                grid: Color(hex: 0xe6e3d9),
                furniture: Color(hex: 0x6b6659),
                label: Color(hex: 0x2b2a26)
            )
    }
}
