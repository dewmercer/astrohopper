import Foundation

/// Celestron AUX bus protocol, as spoken by the SkyPortal WiFi module on TCP
/// port 2000 (and documented by the INDI `celestronaux` driver).
///
/// A packet is `0x3B, length, source, destination, command, data…, checksum`,
/// where `length` counts source, destination, command and data, and the
/// checksum is the two's complement of the sum of the bytes from `length`
/// through the last data byte.
enum AUX {
    static let preamble: UInt8 = 0x3B
    static let defaultHost = "1.2.3.4"
    static let port: UInt16 = 2000
    /// Largest plausible value of a packet's length byte.
    static let maxLength = 32

    /// One full turn of an axis in encoder steps.
    static let stepsPerRevolution = 16_777_216.0

    enum Device: UInt8 {
        case mainBoard = 0x01, handController = 0x04, azimuth = 0x10, altitude = 0x11
        case app = 0x20, gps = 0xB0, wifi = 0xB5
    }

    enum Command: UInt8 {
        case getPosition = 0x01
        case gotoFast = 0x02
        case setPosGuideRate = 0x06
        case setNegGuideRate = 0x07
        case slewDone = 0x13
        case gotoSlow = 0x17
        case movePos = 0x24
        case moveNeg = 0x25
        case getVersion = 0xFE
    }

    struct Packet: Equatable {
        var source: UInt8
        var destination: UInt8
        var command: UInt8
        var data: [UInt8]

        init(source: UInt8, destination: UInt8, command: UInt8, data: [UInt8] = []) {
            self.source = source
            self.destination = destination
            self.command = command
            self.data = data
        }

        init(_ command: Command, to device: Device, data: [UInt8] = []) {
            self.init(source: Device.app.rawValue, destination: device.rawValue, command: command.rawValue, data: data)
        }

        var bytes: [UInt8] {
            var b: [UInt8] = [AUX.preamble, UInt8(3 + data.count), source, destination, command] + data
            b.append(AUX.checksum(b[1...]))
            return b
        }

        /// The data as a big-endian unsigned number (1 to 3 bytes).
        var value: UInt32 { data.prefix(3).reduce(0) { $0 << 8 | UInt32($1) } }
    }

    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        UInt8(truncatingIfNeeded: 0 &- bytes.reduce(0) { $0 &+ Int($1) })
    }

    /// Big-endian encoding of the low `count` bytes of `value`.
    static func encode(_ value: UInt32, bytes count: Int = 3) -> [UInt8] {
        (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) }
    }

    /// Splits a byte stream into packets. Bytes before a preamble and packets
    /// with a bad checksum are skipped; an incomplete packet stays buffered.
    struct Parser {
        private var buffer: [UInt8] = []

        mutating func feed(_ bytes: [UInt8]) -> [Packet] {
            buffer += bytes
            var packets: [Packet] = []
            while true {
                guard let start = buffer.firstIndex(of: AUX.preamble) else {
                    buffer.removeAll()
                    break
                }
                if start > 0 { buffer.removeFirst(start) }
                guard buffer.count >= 2 else { break }
                let length = Int(buffer[1])
                let total = length + 3
                // real packets are short; a longer "length" means this 0x3B
                // was a data byte, not the start of a packet
                guard length >= 3, length <= AUX.maxLength else {
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= total else { break }
                let p = Array(buffer[0..<total])
                if AUX.checksum(p[1..<(total - 1)]) == p[total - 1] {
                    packets.append(Packet(source: p[2], destination: p[3], command: p[4], data: Array(p[5..<(total - 1)])))
                    buffer.removeFirst(total)
                } else {
                    // not a real packet start: look for the next preamble
                    buffer.removeFirst()
                }
            }
            return packets
        }
    }
}
