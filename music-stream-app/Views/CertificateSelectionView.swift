//
//  CertificateSelectionView.swift
//  music-stream-app
//

import SwiftUI

struct CertificateSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var certificateService = CertificateService.shared
    @State private var showImport = false
    @State private var isSelecting = false
    
    var body: some View {
        NavigationStack {
            List {
                savedCertificatesSection
                importSection
            }
            .navigationTitle("Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                importSheet
            }
        }
    }
    
    @ViewBuilder
    private var savedCertificatesSection: some View {
        if !certificateService.storedIdentities.isEmpty {
            Section {
                ForEach(certificateService.storedIdentities) { stored in
                    certificateRow(for: stored)
                }
            } header: {
                Text("Saved Certificates")
            }
        }
    }
    
    private func certificateRow(for stored: StoredIdentity) -> some View {
        Button {
            isSelecting = true
            certificateService.selectIdentity(id: stored.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSelecting = false
                dismiss()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stored.commonName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(stored.expirationDate, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(stored.expirationDate < Date() ? .red : .secondary)
                }
                Spacer()
                if isSelecting && certificateService.selectedIdentityId != stored.id {
                    ProgressView()
                        .controlSize(.small)
                } else if certificateService.selectedIdentityId == stored.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(isSelecting)
        .accessibilityLabel(stored.commonName)
        .accessibilityHint(certificateService.selectedIdentityId == stored.id ? "Currently selected" : "Select this certificate")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                certificateService.removeIdentity(id: stored.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
    
    private var importSection: some View {
        Section {
            Button {
                showImport = true
            } label: {
                Label("Import New Certificate", systemImage: "plus.circle.fill")
            }
            .accessibilityLabel("Import new certificate")
            .accessibilityHint("Opens file picker to import a .p12 certificate")
        } header: {
            Text(certificateService.storedIdentities.isEmpty ? "Add Certificate" : "Or")
        }
    }
    
    private var importSheet: some View {
        NavigationStack {
            CertificateImportView(onImportComplete: {
                dismiss()
            })
            .navigationTitle("Import Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showImport = false
                    }
                }
            }
        }
    }
}

#Preview {
    CertificateSelectionView()
}
