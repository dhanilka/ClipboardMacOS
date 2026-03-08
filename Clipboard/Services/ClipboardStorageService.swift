import CryptoKit
import Foundation
import Security

struct ClipboardArchive: Codable, Sendable {
    var version: Int
    var createdAt: Date
    var items: [PersistedClipboardItem]

    init(version: Int = 1, createdAt: Date = Date(), items: [PersistedClipboardItem]) {
        self.version = version
        self.createdAt = createdAt
        self.items = items
    }
}

struct PersistedClipboardItem: Codable, Sendable {
    var id: UUID
    var contentType: ClipboardContentType
    var timestamp: Date
    var previewText: String
    var isPinned: Bool
    var duplicateKey: String
    var textValue: String?
    var urlValue: String?
    var imageBase64: String?
}

actor ClipboardStorageService {
    enum StorageError: LocalizedError {
        case invalidEncryptedPayload
        case decryptionFailed
        case keyGenerationFailed

        var errorDescription: String? {
            switch self {
            case .invalidEncryptedPayload:
                return "The clipboard file format is invalid."
            case .decryptionFailed:
                return "Unable to decrypt clipboard data."
            case .keyGenerationFailed:
                return "Unable to create encryption key."
            }
        }
    }

    private struct EncryptedEnvelope: Codable {
        let version: Int
        let nonce: String
        let ciphertext: String
        let tag: String
    }

    private let keychainService = "ncrypt.ClipVault"
    private let keychainAccount = "clipboard-history-key-v1"
    private let historyFileName = "history.encjson"

    private var historyFileURL: URL {
        let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupportRoot.appendingPathComponent("ClipVault", isDirectory: true)
        return appFolder.appendingPathComponent(historyFileName)
    }

    func loadArchive() async throws -> ClipboardArchive? {
        let url = historyFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try await decryptArchive(from: data)
    }

    func saveArchive(_ archive: ClipboardArchive) async throws {
        let encrypted = try await encryptArchive(archive)
        let directoryURL = historyFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try encrypted.write(to: historyFileURL, options: .atomic)
    }

    func exportArchive(_ archive: ClipboardArchive, to url: URL) async throws {
        let encrypted = try await encryptArchive(archive)
        try encrypted.write(to: url, options: .atomic)
    }

    func importArchive(from url: URL) async throws -> ClipboardArchive {
        let data = try Data(contentsOf: url)
        return try await decryptArchive(from: data)
    }

    private func encryptArchive(_ archive: ClipboardArchive) async throws -> Data {
        let plainData = try await MainActor.run {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(archive)
        }

        let key = try loadOrCreateKey()
        let sealedBox = try AES.GCM.seal(plainData, using: key)
        let envelope = EncryptedEnvelope(
            version: 1,
            nonce: Data(sealedBox.nonce).base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )
        return try JSONEncoder().encode(envelope)
    }

    private func decryptArchive(from data: Data) async throws -> ClipboardArchive {
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: data)
        guard
            let nonceData = Data(base64Encoded: envelope.nonce),
            let ciphertext = Data(base64Encoded: envelope.ciphertext),
            let tag = Data(base64Encoded: envelope.tag)
        else {
            throw StorageError.invalidEncryptedPayload
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let key = try loadOrCreateKey()
        let decrypted: Data
        do {
            decrypted = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw StorageError.decryptionFailed
        }

        return try await MainActor.run {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ClipboardArchive.self, from: decrypted)
        }
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        if let existingKeyData = try lookupKeyData() {
            return SymmetricKey(data: existingKeyData)
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try saveKeyData(keyData)
        return newKey
    }

    private func lookupKeyData() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func saveKeyData(_ data: Data) throws {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: keychainService,
                kSecAttrAccount: keychainAccount
            ]
            let update: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
            }
            return
        }

        throw StorageError.keyGenerationFailed
    }
}
