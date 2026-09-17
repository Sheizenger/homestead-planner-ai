//
//  WaterColours.swift
//  Homestead
//
//  `WaterPalette` lives in HomesteadCore, where the 3D scene is built and
//  where nothing may import SwiftUI, so it carries its colours as integers.
//  The flat plan draws with `Color`. This is the two-line bridge, and having
//  it means both views take their water from one definition rather than from
//  two copies that drift.
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

extension WaterPalette {
    var deepColour: Color { Color(hex: deep) }
    var shallowColour: Color { Color(hex: shallow) }
    var bankColour: Color { Color(hex: bank) }
    var weedColour: Color { Color(hex: weed) }
}
