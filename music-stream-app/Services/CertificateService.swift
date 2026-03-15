import Foundation
import Security
import OSLog

enum CertificateError: LocalizedError {
    case invalidP12OrPassword
    case fileAccessDenied
    case keychainError(OSStatus)
    case noCACertificateInBundle
    
    var errorDescription: String? {
        switch self {
        case .invalidP12OrPassword: return "Invalid certificate file or incorrect password"
        case .fileAccessDenied: return "Could not access the certificate file"
        case .keychainError(let status): return "Keychain error: \(status)"
        case .noCACertificateInBundle: return "CA certificate not found in app bundle"
        }
    }
}

@MainActor
@Observable
final class CertificateService {
    static let shared = CertificateService()
    
    private nonisolated static let serviceName = "com.music-stream-app"
    private nonisolated static let identityLabel = "mTLS-client-identity"
    private nonisolated static let firstLaunchKey = "CertificateService.hasLaunchedBefore"
    private nonisolated static let expirationWarningDays = 30
    
    private let logger = Logger(subsystem: "com.music-stream-app", category: "CertificateService")
    
    // MARK: - Cached Values (Static for cross-actor access)
    // These are lazily loaded and cached to avoid repeated Keychain/file lookups
    // Using nonisolated(unsafe) because writes are controlled:
    // - cachedPinnedCA: written once during lazy init, immutable after
    // - cachedClientIdentity/identityCacheValid: only written from MainActor via invalidateIdentityCache()
    private nonisolated(unsafe) static var cachedPinnedCA: SecCertificate?
    private nonisolated(unsafe) static var cachedClientIdentity: SecIdentity?
    private nonisolated(unsafe) static var identityCacheValid = false
    
    var pendingImportURL: URL?
    
    private(set) var certificateCommonName: String?
    private(set) var certificateExpirationDate: Date?
    
    var isClientCertificateConfigured: Bool {
        Self.loadClientIdentitySync() != nil
    }
    
    var isCertificateExpired: Bool {
        guard let expirationDate = certificateExpirationDate else { return false }
        return expirationDate < Date()
    }
    
    var isCertificateExpiringSoon: Bool {
        guard let expirationDate = certificateExpirationDate else { return false }
        let warningDate = Calendar.current.date(byAdding: .day, value: Self.expirationWarningDays, to: Date()) ?? Date()
        return expirationDate < warningDate && !isCertificateExpired
    }
    
    var clientCredential: URLCredential? {
        Self.clientCredentialSync
    }
    
    // MARK: - Nonisolated Methods for Network Delegate
    
    // MARK: - Static Nonisolated Methods (for NetworkSessionDelegate)
    // These are static to avoid needing to access `shared` from nonisolated contexts
    
    nonisolated static func loadClientIdentitySync() -> SecIdentity? {
        // Return cached identity if available
        if identityCacheValid, let cached = cachedClientIdentity {
            return cached
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: identityLabel,
            kSecAttrService as String: serviceName,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let identity = item else {
            cachedClientIdentity = nil
            identityCacheValid = true
            return nil
        }
        
        let result = identity as! SecIdentity
        cachedClientIdentity = result
        identityCacheValid = true
        return result
    }
    
    nonisolated static func invalidateIdentityCache() {
        cachedClientIdentity = nil
        identityCacheValid = false
    }
    
    nonisolated static var clientCredentialSync: URLCredential? {
        guard let identity = loadClientIdentitySync() else { return nil }
        return URLCredential(identity: identity, certificates: nil, persistence: .none)
    }
    
    nonisolated static func loadPinnedCACertificateSync() -> SecCertificate? {
        // Return cached CA certificate if available
        if let cached = cachedPinnedCA {
            return cached
        }
        
        let caResource = "ca"
        let caExtension = "crt"
        
        guard let caURL = Bundle.main.url(forResource: caResource, withExtension: caExtension),
              let caData = try? Data(contentsOf: caURL) else {
            return nil
        }
        
        let certificate = SecCertificateCreateWithData(nil, caData as CFData)
        cachedPinnedCA = certificate
        return certificate
    }
    
    private nonisolated init() {
        // Empty init - certificate info is refreshed via performFirstLaunchCleanup() at app startup
    }
    
    // MARK: - P12 Import
    
    func importP12(from url: URL, password: String) async throws {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        var p12Data: Data
        do {
            p12Data = try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read certificate file")
            throw CertificateError.fileAccessDenied
        }
        
        defer {
            p12Data.resetBytes(in: p12Data.startIndex..<p12Data.endIndex)
        }
        
        let identity = try extractIdentity(from: p12Data, password: password)
        
        try storeIdentityInKeychain(identity)
        
        Self.invalidateIdentityCache()
        refreshCertificateInfo()
        logger.info("Certificate imported successfully")
    }
    
    private func extractIdentity(from p12Data: Data, password: String) throws -> SecIdentity {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        
        guard status == errSecSuccess else {
            logger.error("P12 import failed with status")
            throw CertificateError.invalidP12OrPassword
        }
        
        guard let itemsArray = items as? [[String: Any]],
              let firstItem = itemsArray.first,
              let identityRef = firstItem[kSecImportItemIdentity as String] else {
            logger.error("No identity found in P12 file")
            throw CertificateError.invalidP12OrPassword
        }
        
        // Force cast is safe here - CoreFoundation types don't support runtime type checking,
        // so conditional downcast always succeeds. The guard above ensures the value exists.
        let identity = identityRef as! SecIdentity
        return identity
    }
    
    // MARK: - Keychain Operations
    
    private func storeIdentityInKeychain(_ identity: SecIdentity) throws {
        deleteIdentityFromKeychain()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecValueRef as String: identity,
            kSecAttrLabel as String: Self.identityLabel,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            logger.error("Failed to store identity in Keychain")
            throw CertificateError.keychainError(status)
        }
    }
    
    func loadClientIdentity() -> SecIdentity? {
        Self.loadClientIdentitySync()
    }
    
    // MARK: - CA Certificate
    
    func loadPinnedCACertificate() throws -> SecCertificate {
        guard let caURL = Bundle.main.url(forResource: "ca", withExtension: "crt"),
              let caData = try? Data(contentsOf: caURL) else {
            logger.error("CA certificate not found in bundle")
            throw CertificateError.noCACertificateInBundle
        }
        
        guard let certificate = SecCertificateCreateWithData(nil, caData as CFData) else {
            logger.error("Failed to create certificate from CA data")
            throw CertificateError.noCACertificateInBundle
        }
        
        return certificate
    }
    
    // MARK: - Certificate Info
    
    private func refreshCertificateInfo() {
        guard let identity = loadClientIdentity() else {
            certificateCommonName = nil
            certificateExpirationDate = nil
            return
        }
        
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        
        guard status == errSecSuccess, let cert = certificate else {
            certificateCommonName = nil
            certificateExpirationDate = nil
            return
        }
        
        certificateCommonName = extractCommonName(from: cert)
        certificateExpirationDate = extractExpirationDate(from: cert)
        
        if let expDate = certificateExpirationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            logger.info("Certificate expires on \(formatter.string(from: expDate))")
        }
    }
    
    private func extractCommonName(from certificate: SecCertificate) -> String? {
        var commonName: CFString?
        let status = SecCertificateCopyCommonName(certificate, &commonName)
        
        guard status == errSecSuccess, let name = commonName as String? else {
            return nil
        }
        
        return name
    }
    
    private func extractExpirationDate(from certificate: SecCertificate) -> Date? {
        // Parse expiration date from certificate's DER data
        // X.509 certificates encode validity as: SEQUENCE { notBefore, notAfter }
        // We search for the validity sequence and extract notAfter
        let derData = SecCertificateCopyData(certificate) as Data
        return parseExpirationDateFromDER(derData)
    }
    
    private func parseExpirationDateFromDER(_ data: Data) -> Date? {
        // X.509 validity dates are encoded as UTCTime (0x17) or GeneralizedTime (0x18)
        // UTCTime format: YYMMDDHHMMSSZ (13 bytes)
        // GeneralizedTime format: YYYYMMDDHHMMSSZ (15 bytes)
        // We scan for the second time value in the validity sequence (notAfter)
        
        var timeValuesFound: [Date] = []
        var index = 0
        let bytes = [UInt8](data)
        
        while index < bytes.count - 13 {
            let tag = bytes[index]
            
            if tag == 0x17 { // UTCTime
                let length = Int(bytes[index + 1])
                if length >= 12 && index + 2 + length <= bytes.count {
                    let timeBytes = Array(bytes[(index + 2)..<(index + 2 + length)])
                    if let date = parseUTCTime(timeBytes) {
                        timeValuesFound.append(date)
                    }
                }
                index += 2 + length
            } else if tag == 0x18 { // GeneralizedTime
                let length = Int(bytes[index + 1])
                if length >= 14 && index + 2 + length <= bytes.count {
                    let timeBytes = Array(bytes[(index + 2)..<(index + 2 + length)])
                    if let date = parseGeneralizedTime(timeBytes) {
                        timeValuesFound.append(date)
                    }
                }
                index += 2 + length
            } else {
                index += 1
            }
        }
        
        // The second time value in a certificate is notAfter (expiration)
        return timeValuesFound.count >= 2 ? timeValuesFound[1] : timeValuesFound.last
    }
    
    private func parseUTCTime(_ bytes: [UInt8]) -> Date? {
        guard bytes.count >= 12 else { return nil }
        guard let timeString = String(bytes: bytes, encoding: .ascii) else { return nil }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        // UTCTime: YYMMDDHHMMSSZ
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        if let date = formatter.date(from: timeString) {
            return date
        }
        
        // Some certs omit seconds: YYMMDDHHMM'Z'
        formatter.dateFormat = "yyMMddHHmm'Z'"
        return formatter.date(from: timeString)
    }
    
    private func parseGeneralizedTime(_ bytes: [UInt8]) -> Date? {
        guard bytes.count >= 14 else { return nil }
        guard let timeString = String(bytes: bytes, encoding: .ascii) else { return nil }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        // GeneralizedTime: YYYYMMDDHHMMSSZ
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return formatter.date(from: timeString)
    }
    
    // MARK: - Cleanup
    
    func removeAllCertificateData() {
        deleteIdentityFromKeychain()
        Self.invalidateIdentityCache()
        certificateCommonName = nil
        certificateExpirationDate = nil
        logger.info("All certificate data removed")
    }
    
    private func deleteIdentityFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: Self.identityLabel,
            kSecAttrService as String: Self.serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    func performFirstLaunchCleanup() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: Self.firstLaunchKey)
        
        if !hasLaunchedBefore {
            logger.info("First launch detected, clearing orphaned Keychain items")
            removeAllCertificateData()
            UserDefaults.standard.set(true, forKey: Self.firstLaunchKey)
        }
        
        // Always refresh certificate info on startup
        refreshCertificateInfo()
    }
}
