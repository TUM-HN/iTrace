//
//  ContentView.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 19.04.25.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject private var appState: AppState
    @State private var userName: String = ""
    @State private var userAge: String = ""
    @State private var selectedGender: Gender = .male
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isAgeFieldFocused: Bool
    
    enum Gender: String, CaseIterable {
        case male = "Male"
        case female = "Female"
        case other = "Other"
    }
    
    private var isFormValid: Bool {
        !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !userAge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(userAge) != nil &&
        Int(userAge)! > 0 &&
        Int(userAge)! < 150
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Welcome to iTrace")
                    .font(.largeTitle)
                    .bold()
                
                Text("Track your gaze across videos and real-world environments")
                    .font(.title)
                    .padding(.horizontal, 50)
                    .multilineTextAlignment(.center)
                
                Text("Before you start, please enter your information:")
                    .font(.title2)
                    .padding(.top, 20)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Name")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        TextField("Enter your name", text: $userName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                isAgeFieldFocused = true
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Age")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        TextField("Enter your age", text: $userAge)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                            .keyboardType(.numberPad)
                            .focused($isAgeFieldFocused)
                            .onChange(of: userAge) { _, newValue in
                                userAge = newValue.filter { $0.isNumber }
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Gender")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Picker("Gender", selection: $selectedGender) {
                            ForEach(Gender.allCases, id: \.self) { gender in
                                Text(gender.rawValue).tag(gender)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                    }
                    .padding()
                }
                .padding(.horizontal, 40)
                
                
                Button(action: {
                    let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedAge = userAge.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    appState.userName = trimmedName
                    appState.userAge = Int(trimmedAge) ?? 0
                    appState.userGender = selectedGender.rawValue
                    appState.currentPage = .test
                    appState.precisionScore = 0
                }) {
                    Text("Start")
                        .font(.title)
                        .padding()
                }
                .disabled(!isFormValid)
                
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isNameFieldFocused = true
                }
            }
        }
    }
}
