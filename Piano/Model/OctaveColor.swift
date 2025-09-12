//
// Created by Banghua Zhao on 12/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct OctaveColor {
    static let colors: [Color] = [
        Color.red,
        Color.orange,
        Color.yellow,
        Color.green,
        Color.cyan,
        Color.blue,
        Color.purple
    ]

    static func color(for octave: Int) -> Color {
        colors[octave - 1]
    }
}


