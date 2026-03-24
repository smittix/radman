import Darwin
import Foundation

struct SerialPortInfo: Identifiable, Hashable {
    let path: String

    var id: String { path }

    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var isBluetooth: Bool {
        name.localizedCaseInsensitiveContains("bluetooth")
    }

    var isLikelyUSBSerial: Bool {
        let value = name.lowercased()
        return value.contains("usb") || value.contains("serial") || value.contains("wch") || value.contains("uart")
    }

    var summary: String {
        if isBluetooth {
            return "Bluetooth serial port"
        }
        if isLikelyUSBSerial {
            return "Likely USB serial radio cable"
        }
        return "Serial device"
    }
}

enum SerialPortServiceError: LocalizedError {
    case unsupportedBaudRate(Int)
    case openFailed(String)
    case configurationFailed(String)
    case writeFailed(String)
    case writeTruncated(expected: Int, actual: Int)
    case readTimedOut(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedBaudRate(baudRate):
            return "Unsupported baud rate \(baudRate)."
        case let .openFailed(path):
            return "Could not open serial port \(path)."
        case let .configurationFailed(path):
            return "Could not configure serial port \(path)."
        case let .writeFailed(path):
            return "Could not write to serial port \(path)."
        case let .writeTruncated(expected, actual):
            return "Serial write was truncated. Expected \(expected) bytes but wrote \(actual)."
        case let .readTimedOut(expected, actual):
            return "Timed out reading serial data. Expected \(expected) bytes but received \(actual)."
        }
    }
}

protocol SerialPortConnection {
    func flushIO() throws
    func write(_ data: Data) throws
    func readExact(count: Int, timeout: TimeInterval) throws -> Data
    func capture(timeout: TimeInterval) throws -> Data
}

enum SerialPortService {
    static func candidatePorts(devDirectory: URL = URL(fileURLWithPath: "/dev", isDirectory: true)) -> [SerialPortInfo] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: devDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return entries
            .filter { $0.lastPathComponent.hasPrefix("cu.") }
            .map { SerialPortInfo(path: $0.path) }
            .sorted(by: comparePorts)
    }

    static func portExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    static func capture(path: String, baudRate: Int, timeout: TimeInterval) throws -> Data {
        try withConnection(path: path, baudRate: baudRate) { connection in
            try connection.capture(timeout: timeout)
        }
    }

    static func withConnection<T>(path: String, baudRate: Int, action: (any SerialPortConnection) throws -> T) throws -> T {
        let connection = try POSIXSerialPortConnection(path: path, baudRate: baudRate)
        return try action(connection)
    }

    private static func comparePorts(_ lhs: SerialPortInfo, _ rhs: SerialPortInfo) -> Bool {
        if lhs.isLikelyUSBSerial != rhs.isLikelyUSBSerial {
            return lhs.isLikelyUSBSerial && !rhs.isLikelyUSBSerial
        }
        if lhs.isBluetooth != rhs.isBluetooth {
            return !lhs.isBluetooth && rhs.isBluetooth
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    fileprivate static func openConfiguredPort(path: String, baudRate: Int) throws -> Int32 {
        let descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw SerialPortServiceError.openFailed(path)
        }

        var options = termios()
        guard tcgetattr(descriptor, &options) == 0 else {
            close(descriptor)
            throw SerialPortServiceError.configurationFailed(path)
        }

        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cc.16 = 0
        options.c_cc.17 = 1

        let speed = try speedConstant(for: baudRate)
        guard cfsetispeed(&options, speed) == 0, cfsetospeed(&options, speed) == 0 else {
            close(descriptor)
            throw SerialPortServiceError.configurationFailed(path)
        }

        guard tcsetattr(descriptor, TCSANOW, &options) == 0 else {
            close(descriptor)
            throw SerialPortServiceError.configurationFailed(path)
        }

        _ = fcntl(descriptor, F_SETFL, 0)
        tcflush(descriptor, TCIOFLUSH)

        return descriptor
    }

    private static func speedConstant(for baudRate: Int) throws -> speed_t {
        switch baudRate {
        case 9600:
            return speed_t(B9600)
        case 19200:
            return speed_t(B19200)
        case 38400:
            return speed_t(B38400)
        case 57600:
            return speed_t(B57600)
        case 115200:
            return speed_t(B115200)
        default:
            throw SerialPortServiceError.unsupportedBaudRate(baudRate)
        }
    }
}

private final class POSIXSerialPortConnection: SerialPortConnection {
    private let path: String
    private let descriptor: Int32

    init(path: String, baudRate: Int) throws {
        self.path = path
        descriptor = try SerialPortService.openConfiguredPort(path: path, baudRate: baudRate)
    }

    deinit {
        close(descriptor)
    }

    func flushIO() throws {
        guard tcflush(descriptor, TCIOFLUSH) == 0 else {
            throw SerialPortServiceError.configurationFailed(path)
        }
    }

    func write(_ data: Data) throws {
        guard !data.isEmpty else { return }

        var totalWritten = 0
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            while totalWritten < data.count {
                let pointer = baseAddress.advanced(by: totalWritten)
                let bytesWritten = Darwin.write(descriptor, pointer, data.count - totalWritten)
                if bytesWritten < 0 {
                    throw SerialPortServiceError.writeFailed(path)
                }
                if bytesWritten == 0 {
                    throw SerialPortServiceError.writeTruncated(expected: data.count, actual: totalWritten)
                }
                totalWritten += bytesWritten
            }
        }
    }

    func readExact(count: Int, timeout: TimeInterval) throws -> Data {
        var payload = Data()
        let deadline = Date().addingTimeInterval(timeout)

        while payload.count < count {
            if Date() >= deadline {
                throw SerialPortServiceError.readTimedOut(expected: count, actual: payload.count)
            }

            let remaining = deadline.timeIntervalSinceNow
            let wait = max(0.0, min(0.25, remaining))
            if try !waitUntilReadable(timeout: wait) {
                continue
            }

            let chunkSize = max(1, count - payload.count)
            let chunk = try readChunk(maxBytes: chunkSize)
            if chunk.isEmpty {
                continue
            }
            payload.append(chunk)
        }

        return payload
    }

    func capture(timeout: TimeInterval) throws -> Data {
        var payload = Data()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            let wait = max(0.0, min(0.25, remaining))
            if try !waitUntilReadable(timeout: wait) {
                continue
            }

            let chunk = try readChunk(maxBytes: 512)
            if chunk.isEmpty {
                usleep(100_000)
                continue
            }
            payload.append(chunk)
        }

        return payload
    }

    private func readChunk(maxBytes: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let bytesRead = Darwin.read(descriptor, &buffer, buffer.count)

        if bytesRead < 0 {
            throw SerialPortServiceError.openFailed(path)
        }
        if bytesRead == 0 {
            return Data()
        }

        return Data(buffer.prefix(bytesRead))
    }

    private func waitUntilReadable(timeout: TimeInterval) throws -> Bool {
        let timeoutMilliseconds = max(0, Int32((timeout * 1_000).rounded()))
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let result = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
        if result < 0 {
            throw SerialPortServiceError.openFailed(path)
        }
        return result > 0
    }
}
