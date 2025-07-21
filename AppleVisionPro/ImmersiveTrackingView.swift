//
//  ImmersiveTrackingView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 13.05.25.
//

import SwiftUI
import RealityKit
import AVKit

struct ClickData: Codable {
    let x: Double
    let y: Double
    let timestamp: Double
}

struct TapLocation {
    let point: CGPoint
    let timestamp: Double
}

struct ImmersiveTrackingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    
    @State private var tapLocations: [TapLocation] = []
    @State private var isRecording = false
    @State private var counterValue: Double = 0.00
    @State private var timer: Timer?
    @State private var recordingStartTime: Date?
    @State private var clickDataArray: [ClickData] = []
    @State private var isGeneratingHeatmap = false
    @State private var showPressHoldHint = false
    @State private var hintTimer: Timer?

    @State private var screenResolution: CGSize = CGSize(width: 3600, height: 2338)
    
    @State private var stopButtonPressProgress: CGFloat = 0
    @State private var stopButtonTimer: Timer?
    @State private var isStopButtonPressed = false
    @State private var backgroundVid: Bool = false
    
    private let stopButtonPressDuration: Double = 2.0
    
    private var frameSize: CGSize {
        CGSize(
            width: screenResolution.width * 0.911,
            height: screenResolution.height * 0.789
        )
    }

    var body: some View {
        RealityView { content, attachments in
            let headAnchor = AnchorEntity(.head)
            headAnchor.transform.translation = [-0.022, -0.038, -1.2]
            content.add(headAnchor)
            
            if let attachment = attachments.entity(for: "ui") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    headAnchor.addChild(attachment)
                }
            }
        } attachments: {
            Attachment(id: "ui") {
                ZStack {
                    if isRecording {
                        Rectangle()
                            .fill(Color.gray.opacity(0.001))
                            .frame(width: frameSize.width, height: frameSize.height)
                            .overlay(Rectangle().stroke(Color.blue, lineWidth: 0))
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                if let startTime = recordingStartTime {
                                    let timestamp = Date().timeIntervalSince(startTime)
                                    
                                    let xPercentage = Double(location.x / frameSize.width)
                                    let yPercentage = Double(location.y / frameSize.height)
                                    
                                    let clampedX = max(0.0, min(1.0, xPercentage))
                                    let clampedY = max(0.0, min(1.0, yPercentage))
                                    
                                    // Add to tap locations array to keep all dots visible
                                    tapLocations.append(TapLocation(point: location, timestamp: timestamp))
                                    
                                    clickDataArray.append(ClickData(
                                        x: clampedX,
                                        y: clampedY,
                                        timestamp: timestamp
                                    ))
                                    print("Tapped at (\(clampedX * 100), \(clampedY * 100)) at time \(timestamp)")
                                }
                            }

//                        // Draw all tap locations as persistent red dots
//                        ForEach(tapLocations.indices, id: \.self) { index in
//                            let location = tapLocations[index]
//                            let circleSize = min(frameSize.width, frameSize.height) * 0.04
//                            
//                            Circle()
//                                .fill(Color.red)
//                                .frame(width: circleSize, height: circleSize)
//                                .position(location.point)
//                        }
                    }
                    
                    VStack(spacing: 0) {
                        if isGeneratingHeatmap {
                            VStack(spacing: 30) {
                                Spacer()
                                
                                VStack(spacing: 20) {
                                    ProgressView().scaleEffect(2.0)
                                        .padding(.top, 30)
                                    
                                    Text("Generating Heatmap")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .padding()
                                    
                                    Button(action: {
                                        generateInBackground()
                                    }) {
                                        Text("Generate in Background")
                                            .font(.title2)
                                            .padding()
                                    }
                                }
                                .frame(width: 500)
                                .padding(40)
                                .glassBackgroundEffect()
                                .cornerRadius(25)
                                
                                Spacer()
                            }
                        } else if isRecording {
                            HStack(spacing: 20) {
                                HStack(spacing: 15) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 20, height: 20)
                                        .scaleEffect(1.2)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                                    
                                    Text("EYE TRACKING")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 25)
                                .padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 15).fill(.ultraThinMaterial))
                                
                                ZStack {
                                    RoundedRectangle(cornerRadius: 50)
                                        .trim(from: 0, to: stopButtonPressProgress)
                                        .stroke(Color.white, lineWidth: 3)
                                        .frame(width: 70, height: 208)
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear(duration: 0.1), value: stopButtonPressProgress)
                                    
                                    Button(action: {}) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "stop.circle.fill")
                                                .font(.largeTitle)
                                            Text("STOP")
                                                .font(.largeTitle)
                                                .fontWeight(.bold)
                                        }
                                        .padding(15)
                                    }
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { _ in
                                                if !isStopButtonPressed {
                                                    startStopButtonPress()
                                                    showPressHoldHint = true
                                                    hintTimer?.invalidate()
                                                    hintTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                                                        showPressHoldHint = false
                                                    }
                                                }
                                            }
                                            .onEnded { _ in
                                                stopStopButtonPress()
                                            }
                                    )
                                    
                                    if showPressHoldHint {
                                        Text("Press and Hold")
                                            .font(.system(size: 25))
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                            .offset(y: 80)
                                            .bold()
                                    }
                                }
                                .onDisappear {
                                    hintTimer?.invalidate()
                                }
                            }
                            .padding(.top, 300)
                        } else {
                            Spacer()
                            VStack{
                                Button(action: {
                                    Task {
                                        await MainActor.run {
                                            appState.currentPage = .test
                                        }
                                        await dismissImmersiveSpace()
                                        openWindow(id: "main")
                                    }
                                }) {
                                    Image(systemName: "chevron.backward")
                                        .padding(20)
                                    
                                }
                                .frame(width: 60, height: 60)
                                .offset(x: -340, y: 20)
                                
                                Text("Spacial Eye Tracking")
                                    .font(.largeTitle)
                                    .bold()
                                
                                Text("Click continuously to track where you look \n in your surroundings")
                                    .font(.title)
                                    .padding(20)
                                    .multilineTextAlignment(.center)
                                    
                                Text("Make sure View Mirroring is enabled")
                                    .font(.title2)
                                    .padding(20)
                                    .foregroundStyle(.secondary)
                                
                                Button(action: startScreenRecording) {
                                    HStack(spacing: 20) {
                                        Image(systemName: "record.circle")
                                            .font(.system(size: 40))
                                        Text("START RECORDING")
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                    }
                                    .padding(20)
                                }
                                .padding(40)
                            }
                            .frame(width: 800, height: 500)
                            .glassBackgroundEffect()
                        }
                        Spacer()
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                }
            }
        }
        .onDisappear {
            if isRecording {
                stopScreenRecording()
                generateInBackground()
            }
        }
    }
    
    private func generateInBackground() {
        backgroundVid = true
        print("Generating video in background")
        Task {
            await dismissImmersiveSpace()
            await MainActor.run {
                appState.currentPage = .test
            }
            openWindow(id: "main")
        }
    }
    
    private func startStopButtonPress() {
        isStopButtonPressed = true
        stopButtonPressProgress = 0
        
        stopButtonTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            stopButtonPressProgress += 0.05 / stopButtonPressDuration
            
            if stopButtonPressProgress >= 1.0 {
                stopScreenRecording()
                stopStopButtonPress()
            }
        }
    }
    
    private func stopStopButtonPress() {
        isStopButtonPressed = false
        stopButtonTimer?.invalidate()
        stopButtonTimer = nil
        stopButtonPressProgress = 0
    }
    
    private func startScreenRecording() {
        isRecording = true
        recordingStartTime = Date()
        counterValue = 0.00
        tapLocations.removeAll()  // Clear all previous tap locations
        clickDataArray.removeAll()
        appState.clickData.removeAll()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
                if let startTime = self.recordingStartTime {
                    self.counterValue = Date().timeIntervalSince(startTime) - 0.4
                    if self.counterValue < 0 {
                        self.counterValue = 0.00
                    }
                }
            }
        }
        
        Task { await sendStartRecordingRequest() }
    }
    
    private func stopScreenRecording() {
        guard !isGeneratingHeatmap else { return }
        
        isRecording = false
        timer?.invalidate()
        timer = nil
        recordingStartTime = nil
        isGeneratingHeatmap = true
        print("Starting heatmap video generation...")
        
        Task { await sendStopRecordingRequest() }
    }
    
    private func sendStartRecordingRequest() async {
        guard let url = URL(string: "http://\(appState.serverIPAddress)/start_recording") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        let requestBody = [
            "duration": 0,
            "continuous": true
        ] as [String : Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func sendStopRecordingRequest() async {
        guard let url = URL(string: "http://\(appState.serverIPAddress)/stop_recording") else {
            await MainActor.run { isGeneratingHeatmap = false }
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let trackingData = [
            "user_name": appState.userName,
            "user_age": appState.userAge,
            "user_gender": appState.userGender,
            "precision_score": appState.precisionScore,
            "tracking_type": "spatial_eye_tracking",
            "timestamp": timestamp,
            "click_data": clickDataArray.map { ["x": $0.x, "y": $0.y, "timestamp": $0.timestamp] }
        ] as [String : Any]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0
        
        let requestBody = [
            "stop": true,
            "tracking_data": trackingData
        ] as [String : Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               httpResponse.mimeType == "video/mp4" {
                if !backgroundVid{
                    await handleReceivedVideoData(data, trackingData: trackingData)
                }
            } else {
                await MainActor.run { isGeneratingHeatmap = false }
            }
        } catch {
            print("Failed to stop recording: \(error)")
            await MainActor.run { isGeneratingHeatmap = false }
        }
    }
    
    private func handleReceivedVideoData(_ data: Data, trackingData: [String: Any]) async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heatmap_\(UUID().uuidString).mp4")
        
        do {
            try data.write(to: tempURL)
            print("Heatmap video generated")
            
            await dismissImmersiveSpace()

            await MainActor.run {
                appState.VideoURL = tempURL
                appState.clickData = clickDataArray
                
                appState.videoData = trackingData
                
                appState.eyeTrackingMode = .display
                appState.currentPage = .eyeTracking
                
                isGeneratingHeatmap = false
                
                openWindow(id: "main")
            }
            
        } catch {
            print("Failed to save video file: \(error)")
            await MainActor.run { isGeneratingHeatmap = false }
        }
    }
}
