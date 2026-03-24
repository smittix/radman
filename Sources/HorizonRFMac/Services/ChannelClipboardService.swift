import AppKit
import Foundation

private struct ChannelClipboardPayload: Codable {
    let version: Int
    let channels: [ChannelMemory]
}

enum ChannelClipboardServiceError: LocalizedError {
    case nothingCopied
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .nothingCopied:
            return "There are no RadMan channels on the clipboard yet."
        case .invalidPayload:
            return "The clipboard contents could not be decoded as RadMan channels."
        }
    }
}

enum ChannelClipboardService {
    static let pasteboardType = NSPasteboard.PasteboardType("com.radman.channel-set")

    static func hasChannels() -> Bool {
        NSPasteboard.general.data(forType: pasteboardType) != nil
    }

    static func copy(_ channels: [ChannelMemory]) throws {
        let payload = ChannelClipboardPayload(version: 1, channels: channels)
        let data = try JSONEncoder().encode(payload)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: pasteboardType)
    }

    static func paste() throws -> [ChannelMemory] {
        guard let data = NSPasteboard.general.data(forType: pasteboardType) else {
            throw ChannelClipboardServiceError.nothingCopied
        }

        guard let payload = try? JSONDecoder().decode(ChannelClipboardPayload.self, from: data) else {
            throw ChannelClipboardServiceError.invalidPayload
        }
        return payload.channels
    }
}
