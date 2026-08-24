//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network
import SignalServiceKit
import WiFiAware

@available(iOS 26.0, *)
class WADeviceTransferSession: DeviceTransfer.Session {

    private class FileInfo {
        let handle: FileHandle
        let progress: Progress
        let fileUrl: URL
        init(handle: FileHandle, progress: Progress, fileUrl: URL) {
            self.handle = handle
            self.progress = progress
            self.fileUrl = fileUrl
        }
    }

    typealias WiFiAwareConnection = NetworkConnection<Coder<WiFiAware.NetworkEvent, WiFiAware.NetworkEvent, NetworkJSONCoder>>

    private let logger = PrefixedLogger(prefix: "[WifiAware]")

    private let connection: WiFiAwareConnection
    private var activeFiles = AtomicValue(Dictionary<String, FileInfo>(), lock: .init())

    private var receiverTask: Task<Void, Error>?

    var messages: AsyncThrowingStream<DeviceTransfer.SessionMessage, any Error>
    private let messageSink: AsyncThrowingStream<DeviceTransfer.SessionMessage, Error>.Continuation

    init(connection: WiFiAwareConnection) throws {
        self.connection = connection
        (self.messages, self.messageSink) = AsyncThrowingStream.makeStream(of: DeviceTransfer.SessionMessage.self)
        self.receiverTask = Task {
            for try await (event, _) in connection.messages {
                switch event {
                case .done:
                    self.messageSink.yield(.message(.done))
                case .appBackgrounded:
                    self.messageSink.yield(.message(.backgroundApp))
                case .resourceBegin(file: let file, size: let size):
                    // Reserve file
                    let progress = try self.startReceive(file: file, size: size)
                    self.messageSink.yield(.startResource(file, size, progress))
                case .resourceData(file: let file, data: let data):
                    // Write file
                    try writeData(file: file, data: data)
                case .resourceEnd(file: let file):
                    // Finish file
                    let fileUrl = try finishReceive(file: file)
                    self.messageSink.yield(.finishResource(file, fileUrl))
                }
            }
        }
    }

    func waitForConnection() async throws {
    }

    func disconnect(error: Error?) {
        self.messageSink.finish(throwing: error)
        self.receiverTask?.cancel()
        self.receiverTask = nil

        let activeFiles = activeFiles.swap([:])
        for file in activeFiles.values {
            do {
                try file.handle.close()
            } catch {
                Logger.error("Error closing file \(file.fileUrl): \(error)")
            }
        }
    }

    func send(message: DeviceTransfer.Message) throws {
        Task {
            do {
                switch message {
                case .backgroundApp: try await connection.send(WiFiAware.NetworkEvent.appBackgrounded)
                case .done: try await connection.send(WiFiAware.NetworkEvent.done)
                }
            } catch {
                logger.error("Error sending message: \(error)")
            }
        }
    }

    func sendFile(url: URL, name: String, size: UInt64) async throws {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url, options: [.mappedIfSafe, .uncached])
        } catch {
            disconnect(error: error)
            throw error
        }

        let progress = Progress(totalUnitCount: Int64(fileData.count))
        try await messageSink.yield(.startResource(name, size, progress))
        try await connection.send(.resourceBegin(file: name, size: UInt64(fileData.count)))

        var currentOffset: Int = 0
        let chunkSize: Int = 65535
        while currentOffset < fileData.count {
            try Task.checkCancellation()
            let dataSlice = fileData.dropFirst(currentOffset).prefix(chunkSize)
            try await connection.send(.resourceData(file: name, data: dataSlice))
            currentOffset += dataSlice.count
            progress.completedUnitCount += Int64(dataSlice.count)
        }

        try await connection.send(.resourceEnd(file: name))
        try await messageSink.yield(.finishResource(name, url))
    }

    // Start file
    func startReceive(file: String, size: UInt64) throws -> Progress {
        let temporaryURL = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: false)
        guard
            FileManager.default.createFile(
                atPath: temporaryURL.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            )
        else {
            let error = OWSAssertionError("Cannot access output file.")
            disconnect(error: error)
            throw error
        }
        let handle = try FileHandle(forWritingTo: temporaryURL)
        let progress = Progress(totalUnitCount: Int64(size))
        let info = FileInfo(handle: handle, progress: progress, fileUrl: temporaryURL)
        activeFiles.update { $0[file] = info }
        return progress
    }

    // receive bit
    func writeData(file: String, data: Data) throws {
        guard let info = activeFiles.get()[file] else {
            let error = OWSAssertionError("Expected file missing")
            disconnect(error: error)
            throw error
        }
        try info.handle.write(contentsOf: data)
        info.progress.completedUnitCount += Int64(data.count)
    }

    // finish file
    func finishReceive(file: String) throws -> URL {
        guard let info = activeFiles.update(block: { $0.removeValue(forKey: file) }) else {
            let error = OWSAssertionError("Missing file")
            disconnect(error: error)
            throw error
        }
        try info.handle.close()
        info.progress.completedUnitCount = info.progress.totalUnitCount
        return info.fileUrl
    }
}
