//
//  ContentView.swift
//  brooklyn2
//
//  Created by Boris on 11/03/2026.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var cameraManager = CameraManager()
    @State private var cameraAuthorized = false
    @State private var authorizationChecked = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if authorizationChecked {
                if cameraAuthorized {
                    cameraView
                } else {
                    permissionDeniedView
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task {
            await checkCameraPermission()
        }
    }

    private var cameraView: some View {
        ZStack {
            // Composited camera frame
            if let frame = cameraManager.currentFrame {
                Image(decorative: frame, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            }

            // B99 name overlay
            if cameraManager.faceDetected {
                NameOverlayView(name: "Person")
            }
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
            Text("Camera Access Required")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Open Settings and allow camera access to use the B99 effect.")
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func checkCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraAuthorized = false
        }
        authorizationChecked = true
    }
}
