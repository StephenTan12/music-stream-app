import Foundation
import Security
import os

final class NetworkSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    static let shared = NetworkSessionDelegate()
    
    private let logger = Logger(subsystem: "com.music-stream-app", category: "NetworkSessionDelegate")
    
    private override init() {
        super.init()
    }
    
    // MARK: - URLSessionDelegate (session-level challenges)
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        logger.debug("Session-level challenge: \(challenge.protectionSpace.authenticationMethod)")
        handleChallenge(challenge, completionHandler: completionHandler)
    }
    
    // MARK: - URLSessionTaskDelegate (task-level challenges)
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        logger.debug("Task-level challenge: \(challenge.protectionSpace.authenticationMethod)")
        handleChallenge(challenge, completionHandler: completionHandler)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logger.error("Task completed with error: \(error.localizedDescription)")
        } else {
            logger.debug("Task completed successfully")
        }
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("Received response: \(httpResponse.statusCode)")
        }
        completionHandler(.allow)
    }
    
    // MARK: - Challenge Handling
    
    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let authMethod = challenge.protectionSpace.authenticationMethod
        
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
        
        if let identity = credential.identity {
            var cert: SecCertificate?
            if SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert = cert {
                if let summary = SecCertificateCopySubjectSummary(cert) as String? {
                    logger.debug("Using client certificate: \(summary)")
                }
            }
        }
        
        logger.debug("Using client certificate credential")
        completionHandler(.useCredential, credential)
    }
    
    // MARK: - Connection State Tracking
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for metric in metrics.transactionMetrics {
            if let protocol_ = metric.networkProtocolName {
                logger.debug("Protocol: \(protocol_)")
            }
            if metric.isReusedConnection {
                logger.debug("Reused connection")
            }
            if let secureConnectionStart = metric.secureConnectionStartDate,
               let secureConnectionEnd = metric.secureConnectionEndDate {
                let tlsTime = secureConnectionEnd.timeIntervalSince(secureConnectionStart)
                logger.debug("TLS handshake time: \(tlsTime)s")
            }
        }
    }
}
