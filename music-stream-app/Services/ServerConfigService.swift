//
//  ServerConfigService.swift
//  music-stream-app
//

import Foundation

@MainActor @Observable
final class ServerConfigService {
    static let shared = ServerConfigService()
    
    private enum Keys {
        static let serverProtocol = "serverProtocol"
        static let serverHost = "serverHost"
        static let serverPort = "serverPort"
        static let serverConfigured = "serverConfigured"
    }
    
    var serverProtocol: String {
        didSet { save() }
    }
    
    var serverHost: String {
        didSet { save() }
    }
    
    var serverPort: Int {
        didSet { save() }
    }
    
    var isConfigured: Bool {
        didSet {
            UserDefaults.standard.set(isConfigured, forKey: Keys.serverConfigured)
        }
    }
    
    var baseURL: String {
        "\(serverProtocol)://\(serverHost):\(serverPort)"
    }
    
    private init() {
        let defaults = UserDefaults.standard
        
        self.serverProtocol = defaults.string(forKey: Keys.serverProtocol) ?? "http"
        self.serverHost = defaults.string(forKey: Keys.serverHost) ?? ""
        self.serverPort = defaults.object(forKey: Keys.serverPort) as? Int ?? 8000
        self.isConfigured = defaults.bool(forKey: Keys.serverConfigured)
    }
    
    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(serverProtocol, forKey: Keys.serverProtocol)
        defaults.set(serverHost, forKey: Keys.serverHost)
        defaults.set(serverPort, forKey: Keys.serverPort)
    }
}
