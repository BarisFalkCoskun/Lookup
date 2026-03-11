//
//  NameOverlayView.swift
//  brooklyn2
//
//  Created by Boris on 11/03/2026.
//

import SwiftUI

struct NameOverlayView: View {
    let name: String
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Orange banner stripe — slightly angled like B99
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.9, green: 0.45, blue: 0.0),
                                Color(red: 1.0, green: 0.55, blue: 0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 70)
                    .rotationEffect(.degrees(-2))
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height * 0.72
                    )

                // Name text — bold, right-aligned on the banner
                Text(name.uppercased())
                    .font(.system(size: 44, weight: .black, design: .default))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .position(
                        x: geometry.size.width * 0.55,
                        y: geometry.size.height * 0.72
                    )
            }
            .opacity(isVisible ? 1 : 0)
            .offset(x: isVisible ? 0 : 200)
            .animation(.easeOut(duration: 0.35), value: isVisible)
        }
        .ignoresSafeArea()
        .onAppear {
            isVisible = true
        }
    }
}
