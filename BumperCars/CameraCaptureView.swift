// ABOUTME: Wrapper for camera preview with capture button
// ABOUTME: Manages photo capture flow for selfie setup

import SwiftUI
import AVFoundation

struct CameraCaptureView: View {
    let onPhotoCaptured: (UIImage) -> Void
    @State private var coordinator: CameraPreviewView.Coordinator?
    
    var body: some View {
        VStack(spacing: 20) {
            CameraPreviewViewWithCapture(
                coordinator: $coordinator,
                onPhotoCaptured: onPhotoCaptured
            )
            .frame(width: 300, height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 3)
            )
            
            Button(action: {
                coordinator?.capturePhoto()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                    
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 85, height: 85)
                }
            }
        }
    }
}

struct CameraPreviewViewWithCapture: UIViewRepresentable {
    @Binding var coordinator: CameraPreviewView.Coordinator?
    let onPhotoCaptured: (UIImage) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        // Create capture session
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        // Get front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: frontCamera) else {
            print("[Camera] Failed to get front camera")
            return view
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        // Add photo output
        let photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            context.coordinator.photoOutput = photoOutput
        }
        
        // Create preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Handle rotation
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        
        // Add preview layer to view
        view.layer.addSublayer(previewLayer)
        
        // Store session and layer in coordinator
        context.coordinator.captureSession = captureSession
        context.coordinator.previewLayer = previewLayer
        
        // Expose coordinator to parent
        DispatchQueue.main.async {
            self.coordinator = context.coordinator
        }
        
        // Start session on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let previewLayer = context.coordinator.previewLayer {
                previewLayer.frame = uiView.bounds
            }
        }
    }
    
    func makeCoordinator() -> CameraPreviewView.Coordinator {
        let coordinator = CameraPreviewView.Coordinator()
        coordinator.onPhotoCaptured = onPhotoCaptured
        return coordinator
    }
}


