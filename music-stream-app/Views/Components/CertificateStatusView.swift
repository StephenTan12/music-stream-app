import SwiftUI

struct CertificateStatusView: View {
    @State private var certificateService = CertificateService.shared
    @State private var showRemoveConfirmation = false
    
    private var statusIcon: String {
        if certificateService.isClientCertificateConfigured {
            if certificateService.isCertificateExpired { return "xmark.shield.fill" }
            if certificateService.isCertificateExpiringSoon { return "exclamationmark.shield.fill" }
            return "checkmark.shield.fill"
        }
        return "exclamationmark.triangle.fill"
    }
    
    private var statusColor: Color {
        if certificateService.isClientCertificateConfigured {
            if certificateService.isCertificateExpired { return .red }
            if certificateService.isCertificateExpiringSoon { return .orange }
            return .green
        }
        return .orange
    }
    
    private var statusText: String {
        certificateService.isClientCertificateConfigured ? "Certificate Installed" : "No Certificate"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusText)
            
            if certificateService.isClientCertificateConfigured {
                VStack(alignment: .leading, spacing: 4) {
                    if let commonName = certificateService.certificateCommonName {
                        Text(commonName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let expirationDate = certificateService.certificateExpirationDate {
                        HStack(spacing: 4) {
                            if certificateService.isCertificateExpired {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text("Expired: \(expirationDate, format: .dateTime.month().day().year())")
                                    .foregroundStyle(.red)
                            } else if certificateService.isCertificateExpiringSoon {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Expires: \(expirationDate, format: .dateTime.month().day().year())")
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Expires: \(expirationDate, format: .dateTime.month().day().year())")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                }
                
                Button("Remove Certificate", role: .destructive) {
                    showRemoveConfirmation = true
                }
                .font(.subheadline)
                .padding(.top, 4)
            } else {
                Text("A client certificate is required for HTTPS connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Remove Certificate?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                certificateService.removeAllCertificateData()
            }
        } message: {
            Text("You will need to import a new certificate to connect to HTTPS servers.")
        }
    }
}

#Preview {
    CertificateStatusView()
        .padding()
}
