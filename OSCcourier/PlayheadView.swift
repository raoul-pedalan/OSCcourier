//
//  PlayheadView 2.swift
//  OSCcourier
//
//  Created by bernard pierre on 29/06/2026.
//


// PlayheadView.swift
import SwiftUI

struct PlayheadView: View {
    @Binding var position: Double
    @Binding var enLecture: Bool
    let duree: Double
    let largeurTimeline: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: height)
            .offset(x: CGFloat(position / duree) * largeurTimeline)
    }
}