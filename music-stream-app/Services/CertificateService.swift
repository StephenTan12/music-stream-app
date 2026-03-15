import Foundation
import Security
import OSLog

struct StoredIdentity: Codable, Identifiable {
    let id: UUID
    let commonName: String
    let expirationDate: Date
    var label: String { "mTLS-client-\(id.uuidString)" }
}

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
    
    private nonisolated static let identityLabel = "mTLS-client-identity"
    private nonisolated static let firstLaunchKey = "CertificateService.hasLaunchedBefore"
    private nonisolated static let storedIdentitiesKey = "CertificateService.storedIdentities"
    private nonisolated static let selectedIdentityIdKey = "CertificateService.selectedIdentityId"
    private nonisolated static let expirationWarningDays = 30
    
    private let logger = Logger(subsystem: "com.music-stream-app", category: "CertificateService")
    private nonisolated static let staticLogger = Logger(subsystem: "com.music-stream-app", category: "CertificateService.Static")
    
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
    
    private(set) var storedIdentities: [StoredIdentity] = []
    
    private(set) var isClientCertificateConfigured: Bool = false
    
    var selectedIdentityId: UUID? {
        guard let idString = UserDefaults.standard.string(forKey: Self.selectedIdentityIdKey) else { return nil }
        return UUID(uuidString: idString)
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
        if identityCacheValid, let cached = cachedClientIdentity {
            staticLogger.debug("Using cached client identity")
            return cached
        }
        
        let label = Self.getActiveIdentityLabel()
        guard let label else {
            staticLogger.warning("No identity label found")
            cachedClientIdentity = nil
            identityCacheValid = true
            return nil
        }
        
        staticLogger.debug("Loading identity with label: \(label)")
        let identity = loadIdentityByLabelSync(label)
        
        if let identity = identity {
            var cert: SecCertificate?
            if SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert = cert {
                if let summary = SecCertificateCopySubjectSummary(cert) as String? {
                    staticLogger.info("Loaded identity certificate: \(summary)")
                }
            }
            
            var privateKey: SecKey?
            if SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess, privateKey != nil {
                staticLogger.info("Private key accessible")
            } else {
                staticLogger.error("Failed to access private key from identity")
            }
        } else {
            staticLogger.error("Failed to load identity from Keychain")
        }
        
        cachedClientIdentity = identity
        identityCacheValid = true
        return identity
    }
    
    private nonisolated static func getActiveIdentityLabel() -> String? {
        if let idString = UserDefaults.standard.string(forKey: selectedIdentityIdKey),
           let _ = UUID(uuidString: idString) {
            return "mTLS-client-\(idString)"
        }
        return identityLabel
    }
    
    private nonisolated static func loadIdentityByLabelSync(_ label: String) -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecAttrSynchronizable as String: false,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status != errSecSuccess {
            staticLogger.error("Keychain lookup failed with status: \(status)")
            return nil
        }
        
        guard let item else {
            staticLogger.error("Keychain returned nil item")
            return nil
        }
        
        let identity = item as! SecIdentity
        return identity
    }
    
    nonisolated static func invalidateIdentityCache() {
        cachedClientIdentity = nil
        identityCacheValid = false
    }
    
    nonisolated static var clientCredentialSync: URLCredential? {
        guard let identity = loadClientIdentitySync() else {
            staticLogger.error("No client identity available for credential")
            return nil
        }
        
        var certificate: SecCertificate?
        let certStatus = SecIdentityCopyCertificate(identity, &certificate)
        
        if certStatus == errSecSuccess, let cert = certificate {
            staticLogger.debug("Creating credential with certificate")
            return URLCredential(identity: identity, certificates: [cert], persistence: .none)
        }
        
        staticLogger.warning("Creating credential without explicit certificate")
        return URLCredential(identity: identity, certificates: nil, persistence: .none)
    }
    
    private nonisolated static let embeddedCACertificatePEM = """
        -----BEGIN CERTIFICATE-----
        MIIFXDCCA0QCCQDWUP7Ec5xMDzANBgkqhkiG9w0BAQsFADBwMQswCQYDVQQGEwJV
        UzEOMAwGA1UECAwFU3RhdGUxDTALBgNVBAcMBENpdHkxFTATBgNVBAoMDE11c2lj
        IFN0cmVhbTERMA8GA1UECwwIU2VjdXJpdHkxGDAWBgNVBAMMD011c2ljIFN0cmVh
        bSBDQTAeFw0yNjAzMTUwMjAwNDZaFw0zMTAzMTQwMjAwNDZaMHAxCzAJBgNVBAYT
        AlVTMQ4wDAYDVQQIDAVTdGF0ZTENMAsGA1UEBwwEQ2l0eTEVMBMGA1UECgwMTXVz
        aWMgU3RyZWFtMREwDwYDVQQLDAhTZWN1cml0eTEYMBYGA1UEAwwPTXVzaWMgU3Ry
        ZWFtIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAy30jYMBsmn1U
        baYHdMSAkTiXEztMh7lw1aW6QlJwl2wBvPHy60AdNvtDOzFCwJ2Zd2vblox6wyXG
        /CSV/PisTGYZ32bEXpcHbZ7/bBsiQ7KeLIhbp8L6OHkILk4FweBY4Ov7YrSzMxMs
        oJZsZ/v6XYKL7DZ6wd2pkpm8tn2X00Q1UxUBIbMVZl8vaWwE9thQoOAllyxCWjSt
        C+H4EPN79ZqV5IRMzMmgYj2lFJW8bB2bVmWDf/DOw7B538VE5B1MDm6QSJRZkx/L
        QafyFxuvGiJ7K6PdpmDuNyMCnE2iUJ97k1zq0Jo6KSxkoyN7OSNRBsrgrPicfuiG
        JA1mZAMGJQS+DXSh0N7DDSwpHeOyJhNRuVJSVG5hSf2gV33Si/atL/xEBkeUt+Xk
        J/KMwxORMnsSrnx5xYDE6O6J3M+e5npPk4gJ5IklTAJpOpfCbGUYPDLO8Tv6h+vZ
        YOlVomlIIhce/sD/Ivqayl/VofZCu8bgdGAabfa89pDmagq7sx4zLjq1jKj+Wdxm
        +YJP6TDT9T0b1Iq3nDbOJ1FaIOQBKCMhoepLd/Z+UOh7RKHNc7O6hpWNOp5Hmc8t
        boTMCyktDV2Et11fwyfTXG83WXlOKwDUkkeRNAUiHASz/L1GkPXjmXBGoAQl7M70
        6h728KHyBfzfmd6Auwwxg/KpiGbwElUCAwEAATANBgkqhkiG9w0BAQsFAAOCAgEA
        n1HuAIT9dvjIgpw2ITmPX1DcwcjWnFgVIw+H1iE+fjDdjZND5ReZ5qCmnrrM2H9x
        Dok9kHROWRL+RIjmutulzyIhqffvekKHf/q0N4TF9TWfFmsAdwL185bICcjcRLA+
        PDTjnH3g827xd9wSQKoQ5bdGLwZjoCPFDs2+SSlyCvVufGEg0+jjTSdeSv6ZGlmf
        Dkvg9yj9PJvoU6H0kKCEHKBDJrjmj1fQ2VTpCNfRIU0SW8U1bWwgtl///u7hunTe
        YF/w0IhSXra6vjGyULye/Zgeckzq1NrrD48/yDxnkpKg/bkslkflCFrZMnRkZt8w
        biLQXPfFsPLeV3I5S9NFDdAQ1OMcr5UgYoUEe+OU1krbHOYSsXSH2JU4QcCsv8X6
        DlDN7FrcbtBLp/bGSNDmW3JjBhULkDCMG9VarTipn6MpGeenDWm+ZPw/hF/LJW0n
        ABnVIxplFdP/xWMRrvTFKil/qYxl5S99YBOfCBGLG5f9qBxkZMu/5C0ILXEdYB2I
        x1eR/XTLwdhZq23cjNLF/iiKfDUZY7paTo/+sXzI+Tg+re5BrbzuhKkXB8HCOMbQ
        6EJxBjgPTPJ4M3lqrQHvCeOz+4uVWZbpsInbrld8+Mw7oydwa8OGM7HITEAaE2bv
        LL/zV3rFBZbmJ9Yo8wtbvcpubPdOAd8LxdMbHB11//w=
        -----END CERTIFICATE-----
        """
    
    nonisolated static func loadPinnedCACertificateSync() -> SecCertificate? {
        if let cached = cachedPinnedCA {
            return cached
        }
        
        let pemString = embeddedCACertificatePEM
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard let derData = Data(base64Encoded: pemString) else {
            return nil
        }
        
        let certificate = SecCertificateCreateWithData(nil, derData as CFData)
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
        
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let cert = certificate else {
            throw CertificateError.invalidP12OrPassword
        }
        
        let id = UUID()
        let commonName = extractCommonName(from: cert) ?? "Unknown"
        let expirationDate = extractExpirationDate(from: cert) ?? Date.distantFuture
        let label = "mTLS-client-\(id.uuidString)"
        
        try storeIdentityInKeychain(identity, label: label)
        
        var identities = loadStoredIdentitiesFromUserDefaults()
        let stored = StoredIdentity(id: id, commonName: commonName, expirationDate: expirationDate)
        identities.append(stored)
        saveStoredIdentitiesToUserDefaults(identities)
        UserDefaults.standard.set(id.uuidString, forKey: Self.selectedIdentityIdKey)
        
        Self.invalidateIdentityCache()
        refreshStoredIdentities()
        refreshCertificateInfo()
        logger.info("Certificate imported successfully")
    }
    
    func selectIdentity(id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: Self.selectedIdentityIdKey)
        Self.invalidateIdentityCache()
        refreshCertificateInfo()
    }
    
    func removeIdentity(id: UUID) {
        let label = "mTLS-client-\(id.uuidString)"
        deleteIdentityFromKeychain(label: label)
        
        var identities = loadStoredIdentitiesFromUserDefaults()
        identities.removeAll { $0.id == id }
        saveStoredIdentitiesToUserDefaults(identities)
        
        if UserDefaults.standard.string(forKey: Self.selectedIdentityIdKey) == id.uuidString {
            UserDefaults.standard.removeObject(forKey: Self.selectedIdentityIdKey)
            if let first = identities.first {
                UserDefaults.standard.set(first.id.uuidString, forKey: Self.selectedIdentityIdKey)
            }
        }
        
        Self.invalidateIdentityCache()
        refreshStoredIdentities()
        refreshCertificateInfo()
        logger.info("Certificate removed")
    }
    
    private func loadStoredIdentitiesFromUserDefaults() -> [StoredIdentity] {
        guard let data = UserDefaults.standard.data(forKey: Self.storedIdentitiesKey),
              let decoded = try? JSONDecoder().decode([StoredIdentity].self, from: data) else {
            return []
        }
        return decoded
    }
    
    private func saveStoredIdentitiesToUserDefaults(_ identities: [StoredIdentity]) {
        guard let data = try? JSONEncoder().encode(identities) else { return }
        UserDefaults.standard.set(data, forKey: Self.storedIdentitiesKey)
    }
    
    private func refreshStoredIdentities() {
        storedIdentities = loadStoredIdentitiesFromUserDefaults()
    }
    
    private func extractIdentity(from p12Data: Data, password: String) throws -> SecIdentity {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        
        guard status == errSecSuccess else {
            logger.error("P12 import failed with status: \(status)")
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
    
    private func storeIdentityInKeychain(_ identity: SecIdentity, label: String) throws {
        // Delete any existing identity with this label first (handles duplicates)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecValueRef as String: identity,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            logger.error("Failed to store identity in Keychain: \(status)")
            throw CertificateError.keychainError(status)
        }
    }
    
    func loadClientIdentity() -> SecIdentity? {
        Self.loadClientIdentitySync()
    }
    
    // MARK: - CA Certificate
    
    func loadPinnedCACertificate() throws -> SecCertificate {
        guard let certificate = Self.loadPinnedCACertificateSync() else {
            logger.error("Failed to load embedded CA certificate")
            throw CertificateError.noCACertificateInBundle
        }
        return certificate
    }
    
    // MARK: - Certificate Info
    
    private func refreshCertificateInfo() {
        guard let identity = loadClientIdentity() else {
            certificateCommonName = nil
            certificateExpirationDate = nil
            isClientCertificateConfigured = false
            return
        }
        
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        
        guard status == errSecSuccess, let cert = certificate else {
            certificateCommonName = nil
            certificateExpirationDate = nil
            isClientCertificateConfigured = false
            return
        }
        
        certificateCommonName = extractCommonName(from: cert)
        certificateExpirationDate = extractExpirationDate(from: cert)
        isClientCertificateConfigured = true
        
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
        for stored in loadStoredIdentitiesFromUserDefaults() {
            deleteIdentityFromKeychain(label: stored.label)
        }
        deleteIdentityFromKeychain(label: Self.identityLabel)
        UserDefaults.standard.removeObject(forKey: Self.storedIdentitiesKey)
        UserDefaults.standard.removeObject(forKey: Self.selectedIdentityIdKey)
        Self.invalidateIdentityCache()
        storedIdentities = []
        certificateCommonName = nil
        certificateExpirationDate = nil
        isClientCertificateConfigured = false
        logger.info("All certificate data removed")
    }
    
    private func deleteIdentityFromKeychain(label: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    func performFirstLaunchCleanup() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: Self.firstLaunchKey)
        
        if !hasLaunchedBefore {
            logger.info("First launch detected, clearing orphaned Keychain items")
            removeAllCertificateData()
            UserDefaults.standard.set(true, forKey: Self.firstLaunchKey)
        } else {
            migrateLegacyIdentityIfNeeded()
        }
        
        refreshStoredIdentities()
        refreshCertificateInfo()
    }
    
    private func migrateLegacyIdentityIfNeeded() {
        guard loadStoredIdentitiesFromUserDefaults().isEmpty else { return }
        
        guard let identity = Self.loadIdentityByLabelSync(Self.identityLabel) else { return }
        
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let cert = certificate else {
            return
        }
        
        let id = UUID()
        let commonName = extractCommonName(from: cert) ?? "Unknown"
        let expirationDate = extractExpirationDate(from: cert) ?? Date.distantFuture
        let newLabel = "mTLS-client-\(id.uuidString)"
        
        do {
            try storeIdentityInKeychain(identity, label: newLabel)
            deleteIdentityFromKeychain(label: Self.identityLabel)
            
            let stored = StoredIdentity(id: id, commonName: commonName, expirationDate: expirationDate)
            saveStoredIdentitiesToUserDefaults([stored])
            UserDefaults.standard.set(id.uuidString, forKey: Self.selectedIdentityIdKey)
            
            Self.invalidateIdentityCache()
            logger.info("Migrated legacy certificate to multi-identity storage")
        } catch {
            logger.error("Failed to migrate legacy certificate")
        }
    }
}
