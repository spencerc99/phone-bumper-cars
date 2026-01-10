// ABOUTME: Main UI view displaying connection status, distance, and collision feedback.
// ABOUTME: Manages the overall app state and visual collision indicator overlay.

import SwiftUI
import simd

struct ContentView: View {
    @StateObject private var bumperSession = BumperSession()

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Title
                Text("Bumper Cars")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Connection Status
                ConnectionStatusView(status: bumperSession.connectionStatus)

                Spacer()

                // Center section with camera preview and distance/direction
                VStack(spacing: 20) {
                    // Camera preview in center
                    CameraPreviewView()
                        .frame(width: 200, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    // Distance and Direction below camera
                    if bumperSession.isConnected {
                        DistanceView(distance: bumperSession.distance)

                        // Direction indicator
                        if let direction = bumperSession.direction {
                            DirectionView(direction: direction)
                        }
                    } else {
                        Text("Searching for nearby device...")
                            .foregroundColor(.gray)
                            .italic()
                    }
                }

                Spacer()

                // Debug info
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Peers found: \(bumperSession.peersFound)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text(bumperSession.debugLog)
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                        
                        if !bumperSession.debugDetails.isEmpty {
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            Text("Capabilities:")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .fontWeight(.semibold)
                            
                            Text(bumperSession.debugDetails)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.8))
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
                }
                .frame(maxHeight: 200)
            }
            .padding()

            // Collision indicator overlay
            CollisionOverlayView(
                isVisible: bumperSession.showCollisionIndicator,
                position: bumperSession.collisionPosition,
                intensity: bumperSession.collisionIntensity
            )
        }
        .onAppear {
            bumperSession.start()
        }
    }
}

struct ConnectionStatusView: View {
    let status: ConnectionStatus

    var body: some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 12, height: 12)
            Text(status.text)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.3))
        .cornerRadius(20)
    }
}

struct DistanceView: View {
    let distance: Float?

    var body: some View {
        VStack(spacing: 8) {
            Text("Distance")
                .font(.headline)
                .foregroundColor(.gray)

            if let distance = distance {
                Text(String(format: "%.2f m", distance))
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            } else {
                Text("--")
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }
}

struct DirectionView: View {
    let direction: simd_float3

    var body: some View {
        VStack(spacing: 8) {
            Text("Direction")
                .font(.headline)
                .foregroundColor(.gray)

            // Show direction as arrow indicator
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 100, height: 100)

                // Arrow pointing to other device
                Arrow()
                    .fill(Color.blue)
                    .frame(width: 40, height: 60)
                    .rotationEffect(.radians(Double(atan2(direction.x, -direction.z))))
            }
        }
    }
}

struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: width, y: height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.65, y: height))
        path.addLine(to: CGPoint(x: width * 0.35, y: height))
        path.addLine(to: CGPoint(x: width * 0.35, y: height * 0.4))
        path.addLine(to: CGPoint(x: 0, y: height * 0.4))
        path.closeSubpath()

        return path
    }
}

struct CollisionOverlayView: View {
    let isVisible: Bool
    let position: CGPoint  // -1 to 1, where edges are at -1 or 1
    let intensity: CGFloat

    private func edgePosition(in size: CGSize) -> CGPoint {
        // position.x: -1 = left edge, 1 = right edge
        // position.y: -1 = bottom edge, 1 = top edge
        if abs(position.x) > abs(position.y) {
            // Horizontal collision (left or right edge)
            return CGPoint(
                x: position.x > 0 ? size.width : 0,
                y: size.height / 2
            )
        } else if abs(position.y) > 0 {
            // Vertical collision (top or bottom edge)
            return CGPoint(
                x: size.width / 2,
                y: position.y > 0 ? 0 : size.height
            )
        } else {
            // Center (no direction info)
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if isVisible {
                let baseSize: CGFloat = 250
                let size = baseSize + intensity * 100
                let pos = edgePosition(in: geometry.size)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.red,
                                Color.orange.opacity(0.9),
                                Color.yellow.opacity(0.6),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 4)
                            .frame(width: size * 0.3, height: size * 0.3)
                    )
                    .position(pos)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeOut(duration: 0.4), value: isVisible)
            }
        }
    }
}

enum ConnectionStatus {
    case disconnected
    case searching
    case connected

    var color: Color {
        switch self {
        case .disconnected: return .red
        case .searching: return .yellow
        case .connected: return .green
        }
    }

    var text: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .searching: return "Searching..."
        case .connected: return "Connected"
        }
    }
}

#Preview {
    ContentView()
}
