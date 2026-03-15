//
//  CertificateImportView.swift
//  music-stream-app
//

import SwiftUI
import UniformTypeIdentifiers

struct CertificateImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String?
    @State private var password = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    private var canImport: Bool {
        selectedFileURL != nil && !password.isEmpty
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Import Certificate")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Select your .p12 certificate file and enter the password")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Certificate File")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            showFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: selectedFileURL != nil ? "doc.fill" : "doc.badge.plus")
                                    .foregroundStyle(selectedFileURL != nil ? Color.accentColor : .secondary)
                                
                                Text(selectedFileName ?? "Select Certificate File")
                                    .foregroundStyle(selectedFileURL != nil ? .primary : .secondary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        .accessibilityLabel(selectedFileName ?? "Select certificate file")
                        .accessibilityHint("Opens file picker to select a .p12 certificate")
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Certificate Password")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        SecureField("Enter password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .accessibilityLabel("Certificate password")
                    }
                }
                .padding(.horizontal, 32)
                
                if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Error: \(errorMessage)")
                }
                
                Button {
                    Task {
                        await importCertificate()
                    }
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        
                        Text(isImporting ? "Importing..." : "Import Certificate")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canImport || isImporting)
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 40)
                .accessibilityLabel("Import certificate")
                .accessibilityHint(canImport ? "Imports the selected certificate" : "Select a certificate file and enter password first")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.pkcs12],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .task {
            checkPendingImport()
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedFileURL = url
            selectedFileName = url.lastPathComponent
            errorMessage = nil
            
        case .failure:
            errorMessage = "Could not access the selected file"
        }
    }
    
    private func checkPendingImport() {
        if let pendingURL = CertificateService.shared.pendingImportURL {
            selectedFileURL = pendingURL
            selectedFileName = pendingURL.lastPathComponent
            CertificateService.shared.pendingImportURL = nil
        }
    }
    
    private func importCertificate() async {
        guard let url = selectedFileURL else { return }
        
        isImporting = true
        errorMessage = nil
        
        defer {
            isImporting = false
            password = ""
        }
        
        do {
            try await CertificateService.shared.importP12(from: url, password: password)
            dismiss()
        } catch let error as CertificateError {
            switch error {
            case .invalidP12OrPassword:
                errorMessage = "Invalid certificate or incorrect password"
            case .fileAccessDenied:
                errorMessage = "Could not access the certificate file"
            default:
                errorMessage = "Import failed. Please try again."
            }
        } catch {
            errorMessage = "Import failed. Please try again."
        }
    }
}

#Preview {
    CertificateImportView()
}
