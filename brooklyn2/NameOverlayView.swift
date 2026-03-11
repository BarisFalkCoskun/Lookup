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
            let bandAngle = Angle.degrees(-7)
            let title = formattedName(from: name)

            ZStack(alignment: .topLeading) {
                RibbonShape(slant: 34)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.76, green: 0.25, blue: 0.0),
                                Color(red: 0.92, green: 0.36, blue: 0.02)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * 1.14, height: 90)
                    .rotationEffect(bandAngle)
                    .offset(x: -geometry.size.width * 0.12, y: geometry.size.height * 0.56)
                    .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)

                RibbonShape(slant: 26)
                    .fill(Color.black.opacity(0.28))
                    .frame(width: geometry.size.width * 0.78, height: 46)
                    .rotationEffect(bandAngle)
                    .offset(x: geometry.size.width * 0.42, y: geometry.size.height * 0.64)

                VStack(alignment: .leading, spacing: -8) {
                    ForEach(title, id: \.self) { line in
                        Text(line)
                            .font(.system(size: title.count > 1 ? 30 : 38, weight: .black, design: .rounded))
                            .italic()
                    }
                }
                .tracking(0.5)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                .rotationEffect(bandAngle)
                .offset(x: geometry.size.width * 0.47, y: geometry.size.height * 0.545)
            }
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.94, anchor: .trailing)
            .offset(x: isVisible ? 0 : geometry.size.width * 0.16)
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isVisible)
        }
        .ignoresSafeArea()
        .onAppear {
            isVisible = true
        }
    }

    private func formattedName(from name: String) -> [String] {
        let words = name
            .uppercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard words.count > 1 else {
            return [name.uppercased()]
        }

        let midpoint = Int(ceil(Double(words.count) / 2.0))
        return [
            words[..<midpoint].joined(separator: " "),
            words[midpoint...].joined(separator: " ")
        ]
    }
}

private struct RibbonShape: Shape {
    let slant: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: slant, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
