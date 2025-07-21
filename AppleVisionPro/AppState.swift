//
//  AppState.swift
//  AppleVisionPro
//
//  Created by Esra Mehmedova on 26.04.25.
//

import SwiftUI
import Combine
import Network

class AppState: ObservableObject {
    enum WindowPage {
        case content
        case test
        case click
        case eyeTracking
        case bullseyeTest
        case videoUpload
    }
    
    enum EyeTrackingMode {
        case normal
        case display
    }
    
    @Published var currentPage: WindowPage = .content
    @Published var serverIPAddress: String = ""
    @Published var userName: String = ""
    @Published var videoName: String = ""
    @Published var clickData: [ClickData] = []
    @Published var VideoURL: URL?
    @Published var uploadedVideoURL: URL?
    @Published var eyeTrackingMode: EyeTrackingMode = .normal
    @Published var videoData: [String: Any]?
    @Published var reachResult: String = ""
    @Published var userAge: Int = 0
    @Published var userGender: String = ""
    @Published var precisionScore: Double = 0.0
    @Published var eyeTrackingWindowSize: CGSize?
    
    private var browser: NWBrowser?
    
    init() {
        startServiceDiscovery()
    }
    
    private func startServiceDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: "_visionpro._tcp", domain: nil), using: parameters)
        
        browser?.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                print("Browser failed: \(error)")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { results, changes in
            for result in results {
                if case .service(_, _, _, _) = result.endpoint {
                    self.resolveService(result)
                }
            }
        }
        
        browser?.start(queue: .main)
    }
    
    private func resolveService(_ result: NWBrowser.Result) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = endpoint {
                    let hostString = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                    let address = "\(hostString):\(port)"
                    DispatchQueue.main.async {
                        self.serverIPAddress = address
                        print("Server discovered and connected: \(address)")
                    }
                }
                connection.cancel()
            case .failed(let error):
                print("Connection failed: \(error)")
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    deinit {
        browser?.cancel()
    }
}
