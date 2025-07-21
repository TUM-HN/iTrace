//
//  ClickingView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 24.04.25.
//

import SwiftUI

struct ClickingView: View {
    @State private var clickCount = 0
    @State private var startTime: Date?
    @State private var endTime: Date?
    @State private var showRestartButton = false

    let totalClicks = 20

    
    @EnvironmentObject private var appState: AppState

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
            
            VStack(spacing: 40) {
                
                Text("Clicking Speed")
                    .font(.largeTitle)
                    .bold()
                
                Text("Tap on the circle as fast as possible until it's full \n to measure your clicking speed for eye tracking")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .padding()
                
                ZStack {
                    Circle()
                        .fill(.gray)
                        .contentShape(Circle())
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: innerCircleSize, height: innerCircleSize)
                        .animation(.easeOut(duration: 0.2), value: clickCount)
                    
                    if clickCount == totalClicks && showRestartButton {
                        Button(action: restartTest) {
                            Circle()
                                .fill(.white)
                                .frame(width: innerCircleSize, height: innerCircleSize)
                                .overlay(
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.black)
                                )
                        }
                        .transition(.scale)
                    }
                }
                .frame(width: 200, height: 200)
                .gesture(
                    TapGesture().onEnded {
                        if clickCount < totalClicks {
                            handleTap()
                        }
                    }
                )
                
                VStack {
                    if clickCount == totalClicks, let start = startTime, let end = endTime {
                        let timeTaken = end.timeIntervalSince(start)
                        let clicksPerSecond = Double(totalClicks) / timeTaken
                        Text("Speed: \(String(format: "%.2f", clicksPerSecond)) clicks/sec")
                            .font(.title2)
                    }
                }
                .frame(height: 40)
            }
            .padding(.top, 50)
        }
    }

    private var innerCircleSize: CGFloat {
        CGFloat(10 + (190.0 * Double(clickCount) / Double(totalClicks)))
    }

    private func handleTap() {
        if clickCount == 0 {
            startTime = Date()
        }
        if clickCount < totalClicks {
            clickCount += 1
        }
        if clickCount == totalClicks {
            endTime = Date()
            // Add a 1.5 second delay before showing the restart button
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showRestartButton = true
                }
            }
        }
    }
    
    private func restartTest() {
        withAnimation(.easeInOut(duration: 0.3)) {
            clickCount = 0
            startTime = nil
            endTime = nil
            showRestartButton = false
        }
    }
}
