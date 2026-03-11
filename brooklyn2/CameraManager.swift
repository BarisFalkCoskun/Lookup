//
//  CameraManager.swift
//  brooklyn2
//
//  Created by Boris on 11/03/2026.
//

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import UIKit

@Observable
final class CameraManager: NSObject {
    var currentFrame: CGImage?
    var faceDetected: Bool = false

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.brooklyn2.processing", qos: .userInteractive)
    private let ciContext = CIContext()

    // Vision requests
    private let segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    private let faceDetectionRequest = VNDetectFaceRectanglesRequest()

    func startSession() {
        guard !captureSession.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.configureSession()
            self?.captureSession.startRunning()
        }
    }

    func stopSession() {
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        // Add back camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        // Add video data output
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        guard captureSession.canAddOutput(videoOutput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(videoOutput)

        // Rotate video output to portrait for the back camera
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        captureSession.commitConfiguration()
    }

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([segmentationRequest, faceDetectionRequest])
        } catch {
            return
        }

        // Check for face detection
        let hasFace = !(faceDetectionRequest.results?.isEmpty ?? true)

        // Get segmentation mask
        guard let maskBuffer = segmentationRequest.results?.first?.pixelBuffer else { return }

        // Composite
        let originalImage = CIImage(cvPixelBuffer: pixelBuffer)
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)

        guard let compositedImage = compositeB99Effect(person: originalImage, mask: maskImage) else { return }

        // Render to CGImage
        guard let cgImage = ciContext.createCGImage(compositedImage, from: originalImage.extent) else { return }

        Task { @MainActor in
            self.currentFrame = cgImage
            self.faceDetected = hasFace
        }
    }

    private func compositeB99Effect(person: CIImage, mask: CIImage) -> CIImage? {
        let extent = person.extent

        // B99 warm orange/amber solid background
        let background = CIImage(color: CIColor(red: 0.85, green: 0.45, blue: 0.05, alpha: 1.0))
            .cropped(to: extent)

        // Scale mask to match the original image dimensions
        let scaleX = extent.width / mask.extent.width
        let scaleY = extent.height / mask.extent.height
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Blend: person on styled background using the segmentation mask
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = person
        blendFilter.backgroundImage = background
        blendFilter.maskImage = scaledMask

        guard let blendedImage = blendFilter.outputImage else { return nil }

        // Apply a warm orange color tint over the whole image (like the B99 intro color grade)
        let orangeTint = CIImage(color: CIColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 0.25))
            .cropped(to: extent)

        let tintedFilter = CIFilter.sourceOverCompositing()
        tintedFilter.inputImage = orangeTint
        tintedFilter.backgroundImage = blendedImage

        return tintedFilter.outputImage
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processFrame(sampleBuffer)
    }
}
