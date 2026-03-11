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
    private var sessionConfigured = false

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
        guard !sessionConfigured else { return }

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
        sessionConfigured = true
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

        let originalImage = CIImage(cvPixelBuffer: pixelBuffer)
        let compositedImage: CIImage

        if let maskBuffer = segmentationRequest.results?.first?.pixelBuffer {
            let maskImage = CIImage(cvPixelBuffer: maskBuffer)
            compositedImage = compositeB99Effect(person: originalImage, mask: maskImage) ?? stylizedScene(from: originalImage)
        } else {
            compositedImage = stylizedScene(from: originalImage)
        }

        // Render to CGImage
        guard let cgImage = ciContext.createCGImage(compositedImage, from: compositedImage.extent) else { return }

        Task { @MainActor in
            self.currentFrame = cgImage
            self.faceDetected = hasFace
        }
    }

    private func compositeB99Effect(person: CIImage, mask: CIImage) -> CIImage? {
        let extent = person.extent
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)

        // Scale the Vision mask up to the live frame.
        let scaleX = extent.width / mask.extent.width
        let scaleY = extent.height / mask.extent.height
        let scaledMask = mask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: extent)

        let background = stylizedScene(from: person)
        guard let isolatedSubject = blend(foreground: person, background: clear, mask: scaledMask) else {
            return background
        }

        let subjectShadowMask = scaledMask
            .transformed(by: CGAffineTransform(translationX: 18, y: -8))
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18.0])
            .cropped(to: extent)

        let subjectGlowMask = scaledMask
            .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": 10.0])
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10.0])
            .cropped(to: extent)

        let shadowColor = CIImage(color: CIColor(red: 0.32, green: 0.08, blue: 0.0, alpha: 0.34)).cropped(to: extent)
        let glowColor = CIImage(color: CIColor(red: 1.0, green: 0.64, blue: 0.24, alpha: 0.22)).cropped(to: extent)

        let shadow = blend(foreground: shadowColor, background: clear, mask: subjectShadowMask)
        let glow = blend(foreground: glowColor, background: clear, mask: subjectGlowMask)

        let liftedSubject = isolatedSubject
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.08,
                kCIInputContrastKey: 1.1,
                kCIInputBrightnessKey: 0.02
            ])
            .applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.35])

        var composed = background

        if let shadow {
            composed = shadow.composited(over: composed)
        }

        if let glow {
            composed = glow.composited(over: composed)
        }

        return liftedSubject.composited(over: composed).cropped(to: extent)
    }

    private func stylizedScene(from image: CIImage) -> CIImage {
        let extent = image.extent
        let blurredBase = image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10.0])
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.82,
                kCIInputContrastKey: 1.16,
                kCIInputBrightnessKey: -0.03
            ])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.1])
            .applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: 0.55,
                kCIInputRadiusKey: max(extent.width, extent.height) * 0.95
            ])

        let warmWash = CIImage(color: CIColor(red: 1.0, green: 0.49, blue: 0.08, alpha: 0.18))
            .cropped(to: extent)

        let gradientFilter = CIFilter.linearGradient()
        gradientFilter.point0 = CGPoint(x: extent.minX, y: extent.maxY * 0.9)
        gradientFilter.point1 = CGPoint(x: extent.maxX, y: extent.minY)
        gradientFilter.color0 = CIColor(red: 1.0, green: 0.68, blue: 0.22, alpha: 0.22)
        gradientFilter.color1 = CIColor(red: 0.55, green: 0.16, blue: 0.02, alpha: 0.34)

        let gradient = (gradientFilter.outputImage ?? warmWash).cropped(to: extent)
        return warmWash.composited(over: gradient.composited(over: blurredBase)).cropped(to: extent)
    }

    private func blend(foreground: CIImage, background: CIImage, mask: CIImage) -> CIImage? {
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = foreground
        blendFilter.backgroundImage = background
        blendFilter.maskImage = mask
        return blendFilter.outputImage?.cropped(to: background.extent)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processFrame(sampleBuffer)
    }
}
