import Foundation
import IOBluetooth

private let controlChannel: BluetoothRFCOMMChannelID = 15
private let candidateChannels: [BluetoothRFCOMMChannelID] = [15, 17, 13, 12, 29]
private let maxControlChannelAttempts = 3
private let openTimeout: TimeInterval = 8
private let readTimeout: TimeInterval = 2
private let closeTimeout: TimeInterval = 3
private let retryDelay: TimeInterval = 2
private let probeHoldDelay: TimeInterval = 2
private let probeChannelDelay: TimeInterval = 1
private let responseWait: TimeInterval = 2

enum PoCError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case deviceNotFound(String?)
    case openStartFailed(IOReturn)
    case openCompleteTimeout
    case openCompleteFailed(IOReturn)
    case channelObjectNil
    case writeFailed(IOReturn)

    var description: String {
        switch self {
        case .invalidArgument(let value):
            return "Invalid argument: \(value)"
        case .deviceNotFound(let target):
            if let target {
                return "No paired Bluetooth device matched: \(target)"
            }
            return "No paired OPPO/Enco device was found"
        case .openStartFailed(let status):
            return "RFCOMM open start failed: \(formatIOReturn(status))"
        case .openCompleteTimeout:
            return "RFCOMM open complete timed out"
        case .openCompleteFailed(let status):
            return "RFCOMM open complete failed: \(formatIOReturn(status))"
        case .channelObjectNil:
            return "RFCOMM channel object is nil"
        case .writeFailed(let status):
            return "RFCOMM write failed: \(formatIOReturn(status))"
        }
    }
}

struct Options {
    var target: String?
    var listOnly = false
}

struct CommandPacket {
    let label: String
    let sources: [String]
    let raw: [UInt8]
}

struct BatterySnapshot {
    let raw: Data
    let left: UInt8?
    let right: UInt8?
    let batteryCase: UInt8?
}

struct SafeHandshakeSummary {
    let channelConnected: Bool
    let handshakePassed: Bool
    let batteryResponseCount: Int
    let batteryResponses: [BatterySnapshot]
}

struct Phase3BResult {
    let channelConnected: Bool
    let handshakePassed: Bool
    let ancWritePassed: Bool
    let batteryResponses: [BatterySnapshot]
}

enum SafeHandshakePackets {
    static let enableStatusPush = CommandPacket(
        label: "Enable Status Push",
        sources: [
            "Packets.kt lines 211-214"
        ],
        raw: [0xAA, 0x09, 0x00, 0x00, 0x05, 0x02, 0x3A, 0x02, 0x00, 0x01, 0x02]
    )

    static let batteryQuery = CommandPacket(
        label: "Battery Query",
        sources: [
            "Packets.kt lines 206-209",
            "RfcommController.kt lines 981-984",
            "RfcommController.kt lines 996-1002"
        ],
        raw: [0xAA, 0x07, 0x00, 0x00, 0x06, 0x01, 0xF0, 0x00, 0x00]
    )
}

enum Phase3BPackets {
    static let queryANC = CommandPacket(
        label: "Query ANC",
        sources: [
            "Packets.kt lines 12-28",
            "Packets.kt lines 216-219",
            "RfcommController.kt lines 996-1002"
        ],
        raw: buildPacket(command: 0x010C, payload: [0x01, 0x01])
    )

    static let queryANCAfterTransparency = CommandPacket(
        label: "Query ANC After Transparency",
        sources: queryANC.sources,
        raw: queryANC.raw
    )

    static let queryANCAfterOff = CommandPacket(
        label: "Query ANC After Off",
        sources: queryANC.sources,
        raw: queryANC.raw
    )

    static let setTransparency = CommandPacket(
        label: "Set Transparency",
        sources: [
            "Packets.kt lines 12-28",
            "Packets.kt lines 177-180",
            "RfcommController.kt lines 959-975"
        ],
        raw: buildPacket(command: 0x0404, payload: [0x01, 0x01, 0x04])
    )

    static let setANCOff = CommandPacket(
        label: "Set ANC Off",
        sources: [
            "Packets.kt lines 12-28",
            "Packets.kt lines 196-199",
            "RfcommController.kt lines 959-975"
        ],
        raw: buildPacket(command: 0x0404, payload: [0x01, 0x01, 0x01])
    )
}

final class SafeRfcommListener: NSObject {
    var channel: IOBluetoothRFCOMMChannel?
    private(set) var openStatus: IOReturn?
    private(set) var didClose = false
    private(set) var responses: [Data] = []

    var responseCount: Int {
        responses.count
    }

    func responsesSince(_ index: Int) -> [Data] {
        guard index < responses.count else { return [] }
        return Array(responses[index...])
    }

    func resetOpenState() {
        channel = nil
        openStatus = nil
        didClose = false
        responses.removeAll()
    }

    func resetAfterFailure() {
        channel = nil
        openStatus = nil
        didClose = false
    }

    @objc func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        channel = rfcommChannel
        openStatus = status
    }

    @objc func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        didClose = true
    }

    @objc func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        responses.append(data)

        print("RECV:")
        print(data.hexString)
    }

    @objc func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status: IOReturn
    ) {}

    @objc func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status: IOReturn,
        bytesWritten: Int
    ) {}
}

final class SafeRfcommConnection {
    let listener: SafeRfcommListener
    let channel: IOBluetoothRFCOMMChannel

    init(listener: SafeRfcommListener, channel: IOBluetoothRFCOMMChannel) {
        self.listener = listener
        self.channel = channel
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

func parseOptions() throws -> Options {
    var options = Options()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--name", "--address", "--target":
            guard let value = iterator.next() else {
                throw PoCError.invalidArgument(argument)
            }
            options.target = value
        case "--list":
            options.listOnly = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            if options.target == nil {
                options.target = argument
            } else {
                throw PoCError.invalidArgument(argument)
            }
        }
    }

    return options
}

func printUsage() {
    print("""
    Usage:
      OppoPodsRfcommPoC --name "OPPO Enco Air4 Pro"
      OppoPodsRfcommPoC --address "AA-BB-CC-DD-EE-FF"
      OppoPodsRfcommPoC --list
    """)
}

func pairedDevices() -> [IOBluetoothDevice] {
    (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
}

func printPairedDevices(_ devices: [IOBluetoothDevice]) {
    print("Paired Bluetooth Devices:")
    for device in devices {
        let name = device.name ?? "(unknown)"
        let address = device.addressString ?? "(no address)"
        print("- \(name) [\(address)]")
    }
}

func findTargetDevice(in devices: [IOBluetoothDevice], target: String?) throws -> IOBluetoothDevice {
    if let target {
        let normalizedTarget = normalize(target)
        if let device = devices.first(where: { device in
            normalize(device.name ?? "").contains(normalizedTarget)
                || normalize(device.addressString ?? "").contains(normalizedTarget)
        }) {
            return device
        }
        throw PoCError.deviceNotFound(target)
    }

    if let device = devices.first(where: { device in
        let name = normalize(device.name ?? "")
        return name.contains("oppo")
            || name.contains("enco")
            || name.contains("oneplus")
            || name.contains("realme")
    }) {
        return device
    }

    throw PoCError.deviceNotFound(nil)
}

func normalize(_ value: String) -> String {
    value
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

func openChannel(
    device: IOBluetoothDevice,
    channelID: BluetoothRFCOMMChannelID,
    listener: SafeRfcommListener
) throws -> IOBluetoothRFCOMMChannel {
    listener.resetOpenState()
    var openedChannel: IOBluetoothRFCOMMChannel?
    let startStatus = device.openRFCOMMChannelAsync(
        &openedChannel,
        withChannelID: channelID,
        delegate: listener
    )

    listener.channel = openedChannel

    guard startStatus == kIOReturnSuccess else {
        throw PoCError.openStartFailed(startStatus)
    }

    let openDeadline = Date().addingTimeInterval(openTimeout)
    while listener.openStatus == nil && !listener.didClose && Date() < openDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    guard let openStatus = listener.openStatus else {
        closeIfNeeded(openedChannel ?? listener.channel, listener: listener, shouldLog: true)
        listener.resetAfterFailure()
        throw PoCError.openCompleteTimeout
    }

    guard openStatus == kIOReturnSuccess else {
        closeIfNeeded(openedChannel ?? listener.channel, listener: listener, shouldLog: true)
        listener.resetAfterFailure()
        throw PoCError.openCompleteFailed(openStatus)
    }

    guard let channel = openedChannel ?? listener.channel else {
        throw PoCError.channelObjectNil
    }

    return channel
}

func sendCommand(_ packet: CommandPacket, channel: IOBluetoothRFCOMMChannel) throws {
    print("")
    print("SEND \(packet.label):")
    print("SOURCE:")
    for source in packet.sources {
        print(source)
    }
    print(packet.raw.hexString)
    try write(packet.raw, to: channel)
}

func write(_ bytes: [UInt8], to channel: IOBluetoothRFCOMMChannel) throws {
    var mutableBytes = bytes
    let status = mutableBytes.withUnsafeMutableBytes { buffer in
        channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
    }

    print("WRITE COMPLETE:")
    print(formatIOReturn(status))

    guard status == kIOReturnSuccess else {
        throw PoCError.writeFailed(status)
    }
}

func waitForResponses(listener: SafeRfcommListener, baseline: Int, timeout: TimeInterval) -> [Data] {
    let deadline = Date().addingTimeInterval(timeout)

    while !listener.didClose && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    return listener.responsesSince(baseline)
}

func close(channel: IOBluetoothRFCOMMChannel, listener: SafeRfcommListener) {
    listener.resetAfterFailure()
    listener.channel = channel
    print("")
    print("CLOSE REQUEST")
    channel.close()

    let closeDeadline = Date().addingTimeInterval(closeTimeout)
    while !listener.didClose && Date() < closeDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    if listener.didClose {
        print("CHANNEL CLOSED")
    } else {
        print("CHANNEL CLOSED: timeout")
    }
}

func closeIfNeeded(_ channel: IOBluetoothRFCOMMChannel?, listener: SafeRfcommListener, shouldLog: Bool) {
    guard let channel else { return }
    listener.resetAfterFailure()
    listener.channel = channel
    if shouldLog {
        print("")
        print("CLOSE REQUEST")
    }
    channel.close()

    let closeDeadline = Date().addingTimeInterval(closeTimeout)
    while !listener.didClose && Date() < closeDeadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    if shouldLog {
        if listener.didClose {
            print("CHANNEL CLOSED")
        } else {
            print("CHANNEL CLOSED: timeout")
        }
    }
}

func connectControlChannel(device: IOBluetoothDevice) -> SafeRfcommConnection? {
    for attempt in 1...maxControlChannelAttempts {
        print("")
        print("CONNECT ATTEMPT \(attempt): Channel \(controlChannel)")

        let listener = SafeRfcommListener()
        do {
            let channel = try openChannel(device: device, channelID: controlChannel, listener: listener)
            print("OPEN COMPLETE: \(formatIOReturn(listener.openStatus ?? kIOReturnSuccess))")
            print("CONNECTED")
            return SafeRfcommConnection(listener: listener, channel: channel)
        } catch PoCError.openCompleteTimeout {
            print("OPEN COMPLETE: timeout")
            print("TIMEOUT")
            listener.resetAfterFailure()
            Thread.sleep(forTimeInterval: retryDelay)
        } catch {
            if let status = listener.openStatus {
                print("OPEN COMPLETE: \(formatIOReturn(status))")
            } else {
                print("OPEN COMPLETE: unavailable")
            }
            print("TIMEOUT")
            listener.resetAfterFailure()
            Thread.sleep(forTimeInterval: retryDelay)
        }
    }

    probeCandidateChannels(device: device)
    return nil
}

func probeCandidateChannels(device: IOBluetoothDevice) {
    for channelID in candidateChannels {
        print("")
        print("CONNECT ATTEMPT 1: Channel \(channelID)")

        let listener = SafeRfcommListener()
        do {
            let channel = try openChannel(device: device, channelID: channelID, listener: listener)
            print("OPEN COMPLETE: \(formatIOReturn(listener.openStatus ?? kIOReturnSuccess))")
            print("CONNECTED")
            Thread.sleep(forTimeInterval: probeHoldDelay)
            close(channel: channel, listener: listener)
        } catch PoCError.openCompleteTimeout {
            print("OPEN COMPLETE: timeout")
            print("TIMEOUT")
            listener.resetAfterFailure()
        } catch {
            if let status = listener.openStatus {
                print("OPEN COMPLETE: \(formatIOReturn(status))")
            } else {
                print("OPEN COMPLETE: unavailable")
            }
            print("TIMEOUT")
            listener.resetAfterFailure()
        }

        Thread.sleep(forTimeInterval: probeChannelDelay)
    }
}

func runPhase3B(device: IOBluetoothDevice) throws -> Phase3BResult {
    guard let connection = connectControlChannel(device: device) else {
        print("")
        print("RESULT:")
        print("FAILED")
        return Phase3BResult(
            channelConnected: false,
            handshakePassed: false,
            ancWritePassed: false,
            batteryResponses: []
        )
    }

    defer {
        close(channel: connection.channel, listener: connection.listener)
    }

    let handshake = try performSafeHandshake(connection: connection)
    guard handshake.passed else {
        print("")
        print("RESULT:")
        print("ANC WRITE TEST FAILED")
        return Phase3BResult(
            channelConnected: true,
            handshakePassed: false,
            ancWritePassed: false,
            batteryResponses: handshake.batteryResponses
        )
    }

    var ancCandidateCount = 0
    try sendANCStep(Phase3BPackets.queryANC, connection: connection, wait: responseWait, candidateCount: &ancCandidateCount)
    try sendANCStep(Phase3BPackets.setTransparency, connection: connection, wait: responseWait, candidateCount: &ancCandidateCount)
    try sendANCStep(Phase3BPackets.queryANCAfterTransparency, connection: connection, wait: responseWait, candidateCount: &ancCandidateCount)
    try sendANCStep(Phase3BPackets.setANCOff, connection: connection, wait: responseWait, candidateCount: &ancCandidateCount)
    try sendANCStep(Phase3BPackets.queryANCAfterOff, connection: connection, wait: responseWait, candidateCount: &ancCandidateCount)

    let passed = ancCandidateCount > 0

    print("")
    print("RESULT:")
    if passed {
        print("ANC WRITE TEST PASSED")
    } else {
        print("ANC WRITE TEST FAILED")
    }

    return Phase3BResult(
        channelConnected: true,
        handshakePassed: true,
        ancWritePassed: passed,
        batteryResponses: handshake.batteryResponses
    )
}

func performSafeHandshake(connection: SafeRfcommConnection) throws -> (passed: Bool, batteryResponses: [BatterySnapshot]) {
    try sendCommand(SafeHandshakePackets.enableStatusPush, channel: connection.channel)
    Thread.sleep(forTimeInterval: 0.05)

    let baseline = connection.listener.responseCount
    try sendCommand(SafeHandshakePackets.batteryQuery, channel: connection.channel)
    let responses = waitForResponses(listener: connection.listener, baseline: baseline, timeout: readTimeout)
    let batteryResponses = responses.compactMap { batterySnapshot(from: $0) }

    if batteryResponses.isEmpty {
        print("")
        print("RESULT:")
        print("FAILED")
        return (false, [])
    }

    for snapshot in batteryResponses {
        printBatterySnapshot(snapshot)
    }

    print("")
    print("SAFE HANDSHAKE PASSED")
    return (true, batteryResponses)
}

func sendANCStep(
    _ packet: CommandPacket,
    connection: SafeRfcommConnection,
    wait: TimeInterval,
    candidateCount: inout Int
) throws {
    let baseline = connection.listener.responseCount
    try sendCommand(packet, channel: connection.channel)
    let responses = waitForResponses(listener: connection.listener, baseline: baseline, timeout: wait)
    let candidates = responses.filter { isANCCandidateFrame($0) }
    candidateCount += candidates.count

    for candidate in candidates {
        print("")
        print("ANC CANDIDATE FRAME:")
        print(candidate.hexString)
    }
}

func batterySnapshot(from data: Data) -> BatterySnapshot? {
    let bytes = Array(data)
    guard bytes.count >= 4 else { return nil }

    for commandIndex in 0...(bytes.count - 3) where bytes[commandIndex] == 0x06 && bytes[commandIndex + 1] == 0x81 && bytes[commandIndex + 2] == 0xF0 {
        guard bytes[..<commandIndex].contains(0xAA) else { continue }

        if let fields = parseBatteryFields(in: bytes, after: commandIndex + 3) {
            return BatterySnapshot(
                raw: data,
                left: normalizedBatteryValue(fields.left),
                right: normalizedBatteryValue(fields.right),
                batteryCase: normalizedBatteryValue(fields.batteryCase)
            )
        }

        return BatterySnapshot(raw: data, left: nil, right: nil, batteryCase: nil)
    }

    return nil
}

func isANCCandidateFrame(_ data: Data) -> Bool {
    let bytes = Array(data)
    guard bytes.count >= 6, bytes.contains(0xAA) else { return false }

    for index in 0..<(bytes.count - 1) {
        if bytes[index] == 0x0C && bytes[index + 1] == 0x81 {
            return true
        }

        if bytes[index] == 0x04 && bytes[index + 1] == 0x02 {
            return true
        }
    }

    return false
}

func parseBatteryFields(in bytes: [UInt8], after startIndex: Int) -> (left: UInt8, right: UInt8, batteryCase: UInt8)? {
    guard startIndex <= bytes.count - 7 else { return nil }

    for index in startIndex...(bytes.count - 7) where bytes[index] == 0x03 {
        guard bytes[index + 1] == 0x01,
              bytes[index + 3] == 0x02,
              bytes[index + 5] == 0x03 else {
            continue
        }

        return (
            left: bytes[index + 2],
            right: bytes[index + 4],
            batteryCase: bytes[index + 6]
        )
    }

    return nil
}

func normalizedBatteryValue(_ value: UInt8) -> UInt8? {
    guard value != 0x00 && value != 0xFF else { return nil }
    return value
}

func printBatterySnapshot(_ snapshot: BatterySnapshot) {
    print("")
    print("BATTERY RAW:")
    print(snapshot.raw.hexString)
    print("")
    print("BATTERY DECODE:")
    print("Left: \(batteryText(snapshot.left))")
    print("Right: \(batteryText(snapshot.right))")
    print("Case: \(batteryText(snapshot.batteryCase))")
}

func batteryText(_ value: UInt8?) -> String {
    guard let value else {
        return "Unknown / Not present / Not reported"
    }

    return "\(value)%"
}

func printSummary(_ result: Phase3BResult) {
    let latestBattery = result.batteryResponses.last

    print("")
    print("SUMMARY:")
    print("Channel 15 connect: \(result.channelConnected ? "success" : "failed")")
    print("Safe handshake: \(result.handshakePassed ? "passed" : "failed")")
    print("ANC write test: \(result.ancWritePassed ? "passed" : "failed")")
    print("Battery responses: \(result.batteryResponses.isEmpty ? 0 : 1) / 1")
    print("Decoded battery:")
    print("* Left: \(batteryText(latestBattery?.left))")
    print("* Right: \(batteryText(latestBattery?.right))")
    print("* Case: \(batteryText(latestBattery?.batteryCase))")

    if hasPossibleFieldMismatch(result.batteryResponses) {
        print("")
        print("POSSIBLE FIELD MISMATCH")
    }
}

func hasPossibleFieldMismatch(_ responses: [BatterySnapshot]) -> Bool {
    responses.contains { snapshot in
        [snapshot.left, snapshot.right, snapshot.batteryCase].contains { value in
            guard let value else { return false }
            return value > 100
        }
    }
}

func buildPacket(command: UInt16, sequence: UInt8 = 0xF0, payload: [UInt8] = []) -> [UInt8] {
    let payloadLength = UInt16(payload.count)
    let totalLength = UInt8(7 + payload.count)
    return [
        0xAA,
        totalLength,
        0x00,
        0x00,
        UInt8(command & 0x00FF),
        UInt8((command >> 8) & 0x00FF),
        sequence,
        UInt8(payloadLength & 0x00FF),
        UInt8((payloadLength >> 8) & 0x00FF)
    ] + payload
}

func run() throws {
    let options = try parseOptions()
    let devices = pairedDevices()
    printPairedDevices(devices)

    if options.listOnly {
        return
    }

    let device = try findTargetDevice(in: devices, target: options.target)
    let deviceName = device.name ?? "OPPO device"
    print("Target Device: \(deviceName)")
    print("Target Address: \(device.addressString ?? "(no address)")")

    let result = try runPhase3B(device: device)
    printSummary(result)
}

func formatIOReturn(_ value: IOReturn) -> String {
    "0x" + String(UInt32(bitPattern: value), radix: 16, uppercase: true)
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    exit(1)
}
