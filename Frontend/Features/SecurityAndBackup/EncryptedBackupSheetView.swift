// EncryptedBackupSheetView.swift — Giao diện Export và Import tệp .lockinbackup mã hóa AES-GCM.
// Thuộc Frontend/Features/SecurityAndBackup; sử dụng FileDocument + fileExporter / fileImporter của SwiftUI.

import SwiftUI
import UniformTypeIdentifiers

public struct LockInBackupDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.data] }

    public var data: Data

    public init(data: Data = Data()) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = contents
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

public struct EncryptedBackupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: SecurityAndBackupViewModel

    @State private var exportPassphrase = ""
    @State private var importPassphrase = ""
    @State private var restoreMode: BackupRestoreMode = .merge
    @State private var pendingImportData: Data?
    @State private var isShowingExporter = false
    @State private var isShowingImporter = false
    @State private var documentToExport = LockInBackupDocument()
    @State private var localMessage: String?

    public init(viewModel: SecurityAndBackupViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Xuất sao lưu (.lockinbackup)") {
                    SecureField("Passphrase bảo vệ (ít nhất 8 ký tự)", text: $exportPassphrase)
                    Button("Tạo & Xuất file mã hóa") {
                        Task {
                            if let exported = await viewModel.exportEncryptedBackup(passphrase: exportPassphrase) {
                                documentToExport = LockInBackupDocument(data: exported)
                                exportPassphrase = ""
                                isShowingExporter = true
                            }
                        }
                    }
                    .disabled(exportPassphrase.count < AppConstants.minBackupPassphraseLength)
                }

                Section("Khôi phục từ file (.lockinbackup)") {
                    Picker("Chế độ khôi phục", selection: $restoreMode) {
                        Text("Gộp thêm dữ liệu (.merge)").tag(BackupRestoreMode.merge)
                        Text("Ghi đè toàn bộ (.overwrite)").tag(BackupRestoreMode.overwrite)
                    }

                    Button("Chọn tệp sao lưu") {
                        isShowingImporter = true
                    }

                    if let pendingImportData {
                        Text("Đã chọn tệp (\(pendingImportData.count) bytes)")
                            .font(.caption)
                            .foregroundStyle(Color(lockInHex: palette.accentHex))
                        SecureField("Nhập passphrase để giải mã", text: $importPassphrase)
                        Button("Giải mã & Khôi phục") {
                            Task {
                                let ok = await viewModel.importEncryptedBackup(
                                    data: pendingImportData,
                                    passphrase: importPassphrase,
                                    mode: restoreMode
                                )
                                importPassphrase = ""
                                if ok {
                                    localMessage = "Khôi phục thành công!"
                                    self.pendingImportData = nil
                                }
                            }
                        }
                        .disabled(importPassphrase.isEmpty)
                    }
                }

                if let localMessage {
                    Section {
                        Text(localMessage)
                            .foregroundStyle(.green)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sao lưu Mã hóa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $isShowingExporter,
                document: documentToExport,
                contentType: .data,
                defaultFilename: "LockInBackup.\(AppConstants.backupFileExtension)"
            ) { result in
                if case .failure(let error) = result {
                    viewModel.errorMessage = error.localizedDescription
                } else {
                    localMessage = "Đã xuất file .lockinbackup thành công."
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.data]
            ) { result in
                switch result {
                case .success(let url):
                    let needsStop = url.startAccessingSecurityScopedResource()
                    defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        guard data.count <= AppConstants.maxBackupFileBytes else {
                            viewModel.errorMessage = LockInDomainError.backupExceedsMaxSize.localizedDescription
                            return
                        }
                        pendingImportData = data
                        viewModel.errorMessage = nil
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
