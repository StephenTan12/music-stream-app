//
//  ServerSetupView.swift
//  music-stream-app
//

import SwiftUI

struct ServerSetupView: View {
    @State private var selectedProtocol: String = "http"
    @State private var host: String = ""
    @State private var portString: String = "8000"
    
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
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Welcome to Music Stream")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Connect to your music server to get started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Protocol")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Picker("Protocol", selection: $selectedProtocol) {
                            Text("http").tag("http")
                            Text("https").tag("https")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Host / IP Address")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("e.g., 192.168.1.100 or myserver.com", text: $host)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Port")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("8000", text: $portString)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    }
                    
                    Text(previewURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(host.isEmpty ? 0 : 1)
                }
                .padding(.horizontal, 32)
                
                Button {
                    connect()
                } label: {
                    Text("Connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
    }
    
    private func connect() {
        let config = ServerConfigService.shared
        config.serverProtocol = selectedProtocol
        config.serverHost = host.trimmingCharacters(in: .whitespaces)
        config.serverPort = Int(portString) ?? 8000
        config.isConfigured = true
    }
}

#Preview {
    ServerSetupView()
}
