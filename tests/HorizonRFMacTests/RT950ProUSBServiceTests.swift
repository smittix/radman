import XCTest
@testable import HorizonRFMac

final class RT950ProUSBServiceTests: XCTestCase {
    func testIdentifyRadioUsesNativeHandshake() throws {
        let connection = FakeSerialPortConnection(readQueue: [
            Data([0x06]),
            Data([0x01, 0x36, 0x01, 0x74, 0x04, 0x00, 0x05, 0x20, 0x02, 0x00, 0x02, 0x60, 0x01, 0x03, 0x30, 0x04]),
            Data("RT-950      ".utf8),
        ])

        let report = try RT950ProUSBService.identifyRadio(
            using: connection,
            profileName: "Test Radio",
            serialPort: "/dev/cu.usbserial-110"
        )

        XCTAssertEqual(report.modelIdentifier, "RT-950")
        XCTAssertEqual(report.handshakeBlobHex, "01 36 01 74 04 00 05 20 02 00 02 60 01 03 30 04")
        XCTAssertEqual(connection.writes, [
            Data("PROGRAMBT9000U".utf8),
            Data([0x46]),
            Data([0x4D]),
        ])
    }

    func testDownloadCloneReadsAndDecryptsNativeBlocks() throws {
        let plaintextBlockOne = Data((0..<RT950ProUSBService.blockSize).map { UInt8($0) })
        let plaintextBlockTwo = Data((0..<RT950ProUSBService.blockSize).map { UInt8((255 - $0) & 0xFF) })
        let key = "BHT "
        let encryptedBlockOne = RT950ProUSBService.xorTransform(payload: plaintextBlockOne, key: key)
        let encryptedBlockTwo = RT950ProUSBService.xorTransform(payload: plaintextBlockTwo, key: key)

        let connection = FakeSerialPortConnection(readQueue: [
            Data([0x06]),
            Data(repeating: 0x01, count: 16),
            Data("RT-950      ".utf8),
            Data([0x06]),
            Data([0x52, 0x00, 0x00, UInt8(RT950ProUSBService.blockSize)]) + encryptedBlockOne,
            Data([0x54, 0x00, 0x00, UInt8(RT950ProUSBService.blockSize)]) + encryptedBlockTwo,
        ])

        let report = try RT950ProUSBService.downloadClone(
            using: connection,
            profileName: "Test Radio",
            serialPort: "/dev/cu.usbserial-110",
            segments: [
                RT950ProCloneSegment(readCommand: 0x52, writeCommand: 0x57, start: 0x0000, length: RT950ProUSBService.blockSize),
                RT950ProCloneSegment(readCommand: 0x54, writeCommand: 0x55, start: 0x0000, length: RT950ProUSBService.blockSize),
            ],
            negotiationByte: 0x10,
            negotiationMaterial: Array(repeating: 0, count: 19)
        )

        let cloneData = try XCTUnwrap(Data(base64Encoded: report.rawCloneBase64))
        XCTAssertEqual(cloneData, plaintextBlockOne + plaintextBlockTwo)
        XCTAssertEqual(report.cloneByteCount, RT950ProUSBService.blockSize * 2)
        XCTAssertEqual(report.identification.modelIdentifier, "RT-950")
        XCTAssertEqual(report.negotiatedXORKey, "BHT ")
        XCTAssertEqual(connection.writes[0], Data("PROGRAMBT9000U".utf8))
        XCTAssertEqual(connection.writes[1], Data([0x46]))
        XCTAssertEqual(connection.writes[2], Data([0x4D]))
        XCTAssertEqual(connection.writes[3].prefix(4), Data("SEND".utf8))
        XCTAssertEqual(connection.writes[4], Data([0x52, 0x00, 0x00, UInt8(RT950ProUSBService.blockSize)]))
        XCTAssertEqual(connection.writes[5], Data([0x54, 0x00, 0x00, UInt8(RT950ProUSBService.blockSize)]))
        XCTAssertEqual(connection.writes[6], Data([0x45]))
    }

    func testUploadCloneWritesExpectedHeadersAndPayloads() throws {
        let plaintextBlockOne = Data((0..<RT950ProUSBService.blockSize).map { UInt8($0) })
        let plaintextBlockTwo = Data((0..<RT950ProUSBService.blockSize).map { UInt8((200 + $0) & 0xFF) })
        let key = "BHT "

        let connection = FakeSerialPortConnection(readQueue: [
            Data([0x06]),
            Data(repeating: 0x02, count: 16),
            Data("RT-950      ".utf8),
            Data([0x06]),
            Data([0x06]),
            Data([0x06]),
        ])

        let report = try RT950ProUSBService.uploadClone(
            using: connection,
            cloneData: plaintextBlockOne + plaintextBlockTwo,
            profileName: "Test Radio",
            serialPort: "/dev/cu.usbserial-110",
            segments: [
                RT950ProCloneSegment(readCommand: 0x52, writeCommand: 0x57, start: 0x0000, length: RT950ProUSBService.blockSize),
                RT950ProCloneSegment(readCommand: 0x54, writeCommand: 0x55, start: 0x0000, length: RT950ProUSBService.blockSize),
            ],
            negotiationByte: 0x10,
            negotiationMaterial: Array(repeating: 0, count: 19)
        )

        XCTAssertEqual(report.identification.modelIdentifier, "RT-950")
        XCTAssertEqual(report.cloneByteCount, RT950ProUSBService.blockSize * 2)
        XCTAssertEqual(connection.writes[0], Data("PROGRAMBT9000U".utf8))
        XCTAssertEqual(connection.writes[1], Data([0x46]))
        XCTAssertEqual(connection.writes[2], Data([0x4D]))
        XCTAssertEqual(connection.writes[3].prefix(4), Data("SEND".utf8))
        XCTAssertEqual(
            connection.writes[4],
            Data([0x57, 0x00, 0x00, UInt8(RT950ProUSBService.blockSize)]) +
                RT950ProUSBService.xorTransform(payload: plaintextBlockOne, key: key)
        )
        XCTAssertEqual(
            connection.writes[5],
            Data([0x55, 0x00, 0x00, UInt8(RT950ProUSBService.blockSize)]) +
                RT950ProUSBService.xorTransform(payload: plaintextBlockTwo, key: key)
        )
        XCTAssertEqual(connection.writes[6], Data([0x45]))
    }

    func testSerialPortCandidateSortingPrefersUSBOverBluetooth() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        FileManager.default.createFile(atPath: directory.appendingPathComponent("cu.Bluetooth-Incoming-Port").path, contents: Data())
        FileManager.default.createFile(atPath: directory.appendingPathComponent("cu.usbserial-1420").path, contents: Data())
        FileManager.default.createFile(atPath: directory.appendingPathComponent("tty.debug").path, contents: Data())

        let ports = SerialPortService.candidatePorts(devDirectory: directory)

        XCTAssertEqual(ports.map(\.name), ["cu.usbserial-1420", "cu.Bluetooth-Incoming-Port"])
        XCTAssertTrue(ports.first?.isLikelyUSBSerial == true)
    }

    func testPreflightFlagsMissingSerialPort() {
        var profile = RadioProfile()
        profile.name = "RT950"
        profile.builtInModel = .radtelRT950Pro
        profile.model = BuiltInRadioModel.radtelRT950Pro.rawValue
        profile.serialPort = ""

        let report = RT950ProUSBService.preflight(
            profile: profile,
            availablePorts: [SerialPortInfo(path: "/dev/cu.usbserial-1420")]
        )

        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.issues.contains { $0.localizedCaseInsensitiveContains("No serial port is configured") })
    }

    func testPreflightAcceptsVisibleConfiguredPort() {
        var profile = RadioProfile()
        profile.name = "RT950"
        profile.builtInModel = .radtelRT950Pro
        profile.model = BuiltInRadioModel.radtelRT950Pro.rawValue
        profile.serialPort = "/dev/cu.usbserial-1420"

        let report = RT950ProUSBService.preflight(
            profile: profile,
            availablePorts: [SerialPortInfo(path: "/dev/cu.usbserial-1420")]
        )

        XCTAssertTrue(report.isReady)
    }
}

private final class FakeSerialPortConnection: SerialPortConnection {
    private(set) var writes: [Data] = []
    private var readQueue: [Data]

    init(readQueue: [Data]) {
        self.readQueue = readQueue
    }

    func flushIO() throws {}

    func write(_ data: Data) throws {
        writes.append(data)
    }

    func readExact(count: Int, timeout: TimeInterval) throws -> Data {
        guard !readQueue.isEmpty else {
            throw SerialPortServiceError.readTimedOut(expected: count, actual: 0)
        }

        let next = readQueue.removeFirst()
        guard next.count == count else {
            throw SerialPortServiceError.readTimedOut(expected: count, actual: next.count)
        }
        return next
    }

    func capture(timeout: TimeInterval) throws -> Data {
        Data()
    }
}
