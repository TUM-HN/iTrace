//
//  VideoUploadView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 08.06.25.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoUploadView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingDocumentPicker = false
    @State private var isVideoSelected = false
    @State private var selectedVideoName = ""
    
    var body: some View {
        
        ZStack {
            Button(action: {
                appState.currentPage = .test
            }) {
                Image(systemName: "chevron.backward")
                    .padding(20)
            }
            .offset(x: -580, y: -300)
            .frame(width: 60, height: 60)
            
            VStack(spacing: 30) {
                Text("Video Eye Tracking")
                    .font(.largeTitle)
                    .bold()
                
                Text("Click continuously to track where you look while watching a video")
                    .font(.title)
                    .padding(50)
                
                VStack{
                    Button(action: {
                        showingDocumentPicker = true
                    }) {
                        HStack(spacing: 10){
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                            Text("Upload Video")
                                .font(.title2)
                        }
                        .padding()
                    }
                    .padding()
                    
                    if isVideoSelected {
                        Text("Video Selected: " + selectedVideoName)
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("No video selected")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    appState.currentPage = .eyeTracking
                    appState.videoName = selectedVideoName
                }) {
                    Text("Start")
                        .font(.title)
                        .padding()
                }
                .disabled(isVideoSelected == false)
                .padding(.top, 50)
            }
            .padding(.top, 50)
            .fileImporter(
                isPresented: $showingDocumentPicker,
                allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        handleVideoSelection(url: url)
                    }
                case .failure(let error):
                    print("Error selecting video: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleVideoSelection(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security-scoped resource")
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsPath.appendingPathComponent("uploaded_video.mp4")
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            appState.uploadedVideoURL = destinationURL
            isVideoSelected = true
            selectedVideoName = url.lastPathComponent
        } catch {
            print("Error copying video: \(error.localizedDescription)")
        }
        
        url.stopAccessingSecurityScopedResource()
    }
}
