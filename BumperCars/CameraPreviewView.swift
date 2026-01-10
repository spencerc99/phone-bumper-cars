// ABOUTME: Camera preview component displaying the front-facing camera feed.
// ABOUTME: Wraps AVFoundation's AVCaptureVideoPreviewLayer for SwiftUI integration.

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        // Create capture session
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .medium
        
        // Get front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: frontCamera) else {
            print("[Camera] Failed to get front camera")
            return view
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        // Create preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Handle rotation based on device orientation (iOS 16.0 compatible)
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            // Portrait orientation
            connection.videoOrientation = .portrait
        }
        
        // Add preview layer to view
        view.layer.addSublayer(previewLayer)
        
        // Store session and layer in coordinator
        context.coordinator.captureSession = captureSession
        context.coordinator.previewLayer = previewLayer
        
        // Start session on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame when view size changes
        DispatchQueue.main.async {
            if let previewLayer = context.coordinator.previewLayer {
                previewLayer.frame = uiView.bounds
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        
        deinit {
            captureSession?.stopRunning()
        }
    }
}

