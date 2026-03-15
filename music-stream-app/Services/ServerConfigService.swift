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
    
    var serverPort: Int? {
        didSet { save() }
    }
    
    var isConfigured: Bool {
        didSet {
            UserDefaults.standard.set(isConfigured, forKey: Keys.serverConfigured)
        }
    }
    
    var baseURL: String {
        if let port = serverPort {
            return "\(serverProtocol)://\(serverHost):\(port)"
        }
        return "\(serverProtocol)://\(serverHost)"
    }
    
    var isCertificateRequired: Bool {
        serverProtocol == "https"
    }
    
    var isReadyToConnect: Bool {
        let hasValidHost = !serverHost.isEmpty
        let hasValidPort = serverPort == nil || (serverPort! > 0 && serverPort! <= 65535)
        
        if isCertificateRequired {
            return hasValidHost && hasValidPort && CertificateService.shared.isClientCertificateConfigured
        }
        return hasValidHost && hasValidPort
    }
    
    private init() {
        let defaults = UserDefaults.standard
        
        self.serverProtocol = defaults.string(forKey: Keys.serverProtocol) ?? "http"
        self.serverHost = defaults.string(forKey: Keys.serverHost) ?? ""
        self.serverPort = defaults.object(forKey: Keys.serverPort) as? Int
        self.isConfigured = defaults.bool(forKey: Keys.serverConfigured)
    }
    
    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(serverProtocol, forKey: Keys.serverProtocol)
        defaults.set(serverHost, forKey: Keys.serverHost)
        if let port = serverPort {
            defaults.set(port, forKey: Keys.serverPort)
        } else {
            defaults.removeObject(forKey: Keys.serverPort)
        }
    }
}
