import Foundation

/// Parses the Bluetooth SIG Heart Rate Measurement characteristic (0x2A37).
public enum HeartRateMeasurementParser {
    public static func beatsPerMinute(from data: Data) -> Double? {
        guard data.count >= 2 else { return nil }

        let flags = data[data.startIndex]
        let usesSixteenBitValue = flags & 0x01 != 0

        if usesSixteenBitValue {
            guard data.count >= 3 else { return nil }
            let lowByte = UInt16(data[data.startIndex + 1])
            let highByte = UInt16(data[data.startIndex + 2])
            return Double(lowByte | (highByte << 8))
        }

        return Double(data[data.startIndex + 1])
    }
}
