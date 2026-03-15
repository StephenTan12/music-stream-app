import Foundation
import Security
import os

final class NetworkSessionDelegate: NSObject, URLSessionDelegate {
    static let shared = NetworkSessionDelegate()
    
    private let logger = Logger(subsystem: "com.music-stream-app", category: "NetworkSessionDelegate")
    
    private override init() {
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let authMethod = challenge.protectionSpace.authenticationMethod
        logger.debug("Received authentication challenge: \(authMethod)")
        
        switch authMethod {
        case NSURLAuthenticationMethodServerTrust:
            handleServerTrustChallenge(challenge, completionHandler: completionHandler)
            
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCertificateChallenge(challenge, completionHandler: completionHandler)
            
        default:
            logger.debug("Using default handling for challenge type: \(authMethod)")
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    private func handleServerTrustChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            logger.error("Server trust challenge missing serverTrust")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        guard let pinnedCA = CertificateService.loadPinnedCACertificateSync() else {
            logger.error("Failed to load pinned CA certificate")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let anchorCertificates = [pinnedCA] as CFArray
        let anchorStatus = SecTrustSetAnchorCertificates(serverTrust, anchorCertificates)
        guard anchorStatus == errSecSuccess else {
            logger.error("Failed to set anchor certificates: \(anchorStatus)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let anchorOnlyStatus = SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        guard anchorOnlyStatus == errSecSuccess else {
            logger.error("Failed to set anchor certificates only: \(anchorOnlyStatus)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        var error: CFError?
        let trustValid = SecTrustEvaluateWithError(serverTrust, &error)
        
        if trustValid {
            logger.debug("Server trust evaluation succeeded")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            if let error = error {
                logger.error("Server trust evaluation failed: \(error.localizedDescription)")
            } else {
                logger.error("Server trust evaluation failed")
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    private func handleClientCertificateChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let credential = CertificateService.clientCredentialSync else {
            logger.error("Client credential not available")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        logger.debug("Using client certificate credential")
        completionHandler(.useCredential, credential)
    }
}
