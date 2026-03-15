//
//  SettingsView.swift
//  music-stream-app
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProtocol: String
    @State private var host: String
    @State private var portString: String
    @State private var certificateService = CertificateService.shared
    @State private var showCertificateImport = false
    
    var onSave: (() -> Void)?
    
    init(onSave: (() -> Void)? = nil) {
        let config = ServerConfigService.shared
        _selectedProtocol = State(initialValue: config.serverProtocol)
        _host = State(initialValue: config.serverHost)
        _portString = State(initialValue: config.serverPort.map { String($0) } ?? "")
        self.onSave = onSave
    }
    
    private var isValid: Bool {
        let trimmedPort = portString.trimmingCharacters(in: .whitespaces)
        let hasValidHost = !host.trimmingCharacters(in: .whitespaces).isEmpty
        let hasValidPort = trimmedPort.isEmpty || (Int(trimmedPort).map { $0 > 0 && $0 <= 65535 } ?? false)
        
        if selectedProtocol == "https" {
            return hasValidHost && hasValidPort && certificateService.isClientCertificateConfigured
        }
        return hasValidHost && hasValidPort
    }
    
    private var previewURL: String {
        let trimmedPort = portString.trimmingCharacters(in: .whitespaces)
        if trimmedPort.isEmpty {
            return "\(selectedProtocol)://\(host)"
        }
        return "\(selectedProtocol)://\(host):\(trimmedPort)"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Protocol", selection: $selectedProtocol) {
                        Text("http").tag("http")
                        Text("https").tag("https")
                    }
                    
                    TextField("Host / IP Address", text: $host)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("Port (optional)", text: $portString)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Server Configuration")
                } footer: {
                    Text("URL: \(previewURL)")
                        .font(.caption)
                        .opacity(host.isEmpty ? 0 : 1)
                }
                
                if selectedProtocol == "https" {
                    Section {
                        CertificateStatusView()
                        
                        Button {
                            showCertificateImport = true
                        } label: {
                            Label(
                                certificateService.isClientCertificateConfigured ? "Change Certificate" : "Add Certificate",
                                systemImage: "plus.circle.fill"
                            )
                        }
                    } header: {
                        Text("Client Certificate")
                    } footer: {
                        Text("Required for secure HTTPS connections")
                    }
                }
                
                Section {
                    Button("Save") {
                        saveSettings()
                    }
                    .disabled(!isValid)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showCertificateImport) {
                CertificateSelectionView()
            }
        }
    }
    
    private func saveSettings() {
        let config = ServerConfigService.shared
        config.serverProtocol = selectedProtocol
        config.serverHost = host.trimmingCharacters(in: .whitespaces)
        let trimmedPort = portString.trimmingCharacters(in: .whitespaces)
        config.serverPort = trimmedPort.isEmpty ? nil : Int(trimmedPort)
        onSave?()
        dismiss()
    }
}

#Preview {
    SettingsView()
}
