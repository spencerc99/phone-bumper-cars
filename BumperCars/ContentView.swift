// ABOUTME: Main UI view displaying connection status, distance, and collision feedback.
// ABOUTME: Manages the overall app state and visual collision indicator overlay.

import SwiftUI
import simd

// MARK: - Shake Detection

// Device shake notification
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name(rawValue: "deviceDidShakeNotification")
}

// Override motionEnded to detect shake
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}

// View modifier for shake detection
struct ShakeViewModifier: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onAppear()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeViewModifier(action: action))
    }
}

// Color extension for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct ContentView: View {
    @StateObject private var bumperSession = BumperSession()
    @State private var showingCameraSetup = false // Start with false, check for saved photos
    @State private var captureStep: CaptureStep = .normal
    @State private var showDebugMenu = false
    @State private var showDebugInfo = false
    @State private var showDistance = false
    
    enum CaptureStep {
        case normal, surprised, done
        
        var instruction: String {
            switch self {
            case .normal: return "Take a normal photo of yourself"
            case .surprised: return "Now make a surprised face! 😮"
            case .done: return ""
            }
        }
        
        var buttonText: String {
            switch self {
            case .normal: return "Capture Normal Photo"
            case .surprised: return "Capture Surprised Photo"
            case .done: return ""
            }
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            if showingCameraSetup {
                // Selfie capture flow
                cameraSetupView
            } else {
                // Main game view
                mainGameView
            }
        }
        .onAppear {
            // Keep screen on while app is active
            UIApplication.shared.isIdleTimerDisabled = true
            
            // Check if we have saved selfies
            if bumperSession.normalSelfie == nil || bumperSession.surprisedSelfie == nil {
                // No saved selfies, show camera setup
                showingCameraSetup = true
            } else {
                // Have saved selfies, start the game
                bumperSession.start()
            }
        }
        .onDisappear {
            // Re-enable auto-lock when app closes
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    var cameraSetupView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Text("Setup Your Selfies")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(captureStep.instruction)
                .font(.title2)
                .foregroundColor(.yellow)
                .multilineTextAlignment(.center)
                .padding()
            
            // Camera capture view with button
            CameraCaptureView(onPhotoCaptured: { image in
                handlePhotoCaptured(image)
            })
            
            Spacer()
        }
        .padding()
    }
    
    var mainGameView: some View {
        ZStack {
            // Background flash - changes to bright orange on collision
            Color(hex: bumperSession.showSurprisedFace ? "#ff9900" : "#000000")
                .ignoresSafeArea()
                .animation(.none, value: bumperSession.showSurprisedFace) // Instant, no animation
            
            VStack(spacing: 30) {
                // Title
                Text("Bumper Phones")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Connection Status
                ConnectionStatusView(status: bumperSession.connectionStatus)

                Spacer()

                // Center section with selfie display
                VStack(spacing: 20) {
                    // Selfie display - switches between normal and surprised
                    // Use ZStack to preload both images for instant switching
                    ZStack {
                        if let normalSelfie = bumperSession.normalSelfie {
                            Image(uiImage: normalSelfie)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 250, height: 350)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white, lineWidth: 4)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                                .opacity(bumperSession.showSurprisedFace ? 0 : 1)
                        }
                        
                        if let surprisedSelfie = bumperSession.surprisedSelfie {
                            Image(uiImage: surprisedSelfie)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 250, height: 350)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white, lineWidth: 4)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                                .scaleEffect(1.05)
                                .opacity(bumperSession.showSurprisedFace ? 1 : 0)
                        }
                    }
                    .offset(y: -80) // Move photo up 40px to center it better
                    .animation(.none, value: bumperSession.showSurprisedFace) // Instant switch, no animation
                    .onTapGesture(count: 3) {
                        // Triple tap to retake photos
                        retakePhotos()
                    }
                    
                    // Distance display (only if enabled)
                    if showDistance {
                        if bumperSession.isConnected {
                            if let distance = bumperSession.distance {
                                Text(String(format: "%.2f m", distance))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        } else {
                            Text("Searching for nearby device...")
                                .foregroundColor(.gray)
                                .italic()
                        }
                    }
                }

                Spacer()

                // Debug info (only if enabled)
                if showDebugInfo {
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
            }
            .padding()
            
            // Debug menu overlay
            if showDebugMenu {
                debugMenuOverlay
            }
            
            // Debug menu trigger - double tap top right corner
            VStack {
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: 80, height: 80)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            // Toggle debug menu on double tap
                            withAnimation(.spring(response: 0.3)) {
                                showDebugMenu.toggle()
                            }
                        }
                }
                Spacer()
            }
        }
    }
    
    var debugMenuOverlay: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        showDebugMenu = false
                    }
                }
            
            // Menu
            VStack(spacing: 20) {
                Text("Debug Menu")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Divider()
                    .background(Color.white)
                
                Toggle("Show Debug Info", isOn: $showDebugInfo)
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .foregroundColor(.white)
                
                Toggle("Show Distance", isOn: $showDistance)
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .foregroundColor(.white)
                
                Divider()
                    .background(Color.white)
                
                Button(action: {
                    retakePhotos()
                    withAnimation(.spring(response: 0.3)) {
                        showDebugMenu = false
                    }
                }) {
                    Text("Retake Photos")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        showDebugMenu = false
                    }
                }) {
                    Text("Close")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray)
                        .cornerRadius(10)
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.15))
            )
            .padding(40)
        }
    }
    
    // MARK: - Helper Functions
    
    func handlePhotoCaptured(_ image: UIImage) {
        print("[UI] Photo captured for step: \(captureStep)")
        
        switch captureStep {
        case .normal:
            bumperSession.normalSelfie = image
            captureStep = .surprised
            
        case .surprised:
            bumperSession.surprisedSelfie = image
            captureStep = .done
            
            // Start the game
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingCameraSetup = false
                bumperSession.start()
            }
            
        case .done:
            break
        }
    }
    
    func retakePhotos() {
        print("[UI] Triple tap detected - retaking photos")
        
        // Stop the session
        bumperSession.stop()
        
        // Clear saved selfies from storage
        bumperSession.clearSavedSelfies()
        
        // Reset photos and capture step
        bumperSession.normalSelfie = nil
        bumperSession.surprisedSelfie = nil
        captureStep = .normal
        
        // Show camera setup again
        showingCameraSetup = true
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
