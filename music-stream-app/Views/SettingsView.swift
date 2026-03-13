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
    
    var onSave: (() -> Void)?
    
    init(onSave: (() -> Void)? = nil) {
        let config = ServerConfigService.shared
        _selectedProtocol = State(initialValue: config.serverProtocol)
        _host = State(initialValue: config.serverHost)
        _portString = State(initialValue: String(config.serverPort))
        self.onSave = onSave
    }
    
    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(portString) != nil &&
        (Int(portString) ?? 0) > 0 &&
        (Int(portString) ?? 0) <= 65535
    }
    
    private var previewURL: String {
        let port = Int(portString) ?? 8000
        return "\(selectedProtocol)://\(host):\(port)"
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
                    
                    TextField("Port", text: $portString)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Server Configuration")
                } footer: {
                    Text("URL: \(previewURL)")
                        .font(.caption)
                        .opacity(host.isEmpty ? 0 : 1)
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
        }
    }
    
    private func saveSettings() {
        let config = ServerConfigService.shared
        config.serverProtocol = selectedProtocol
        config.serverHost = host.trimmingCharacters(in: .whitespaces)
        config.serverPort = Int(portString) ?? 8000
        onSave?()
        dismiss()
    }
}

#Preview {
    SettingsView()
}
