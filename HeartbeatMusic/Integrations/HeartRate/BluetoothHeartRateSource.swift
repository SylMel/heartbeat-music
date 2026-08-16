@preconcurrency import CoreBluetooth
import Foundation
import HeartbeatCore

/// Connects to Myzone and other monitors that expose the standard Bluetooth
/// Heart Rate Service (0x180D) and Heart Rate Measurement (0x2A37).
@MainActor
final class BluetoothHeartRateSource: NSObject, HeartRateSource {
    private static let heartRateService = CBUUID(string: "180D")
    private static let heartRateMeasurement = CBUUID(string: "2A37")

    private(set) var currentBPM: Double = 0
    var onHeartRateChange: ((Double) -> Void)?
    var onStatusChange: ((HeartRateSourceStatus) -> Void)?

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var isRunning = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        isRunning = true
        startScanningIfPossible()
    }

    func stop() {
        isRunning = false
        centralManager.stopScan()
        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        onStatusChange?(.idle)
    }

    private func startScanningIfPossible() {
        guard isRunning else { return }

        switch centralManager.state {
        case .poweredOn:
            onStatusChange?(.scanning)
            centralManager.scanForPeripherals(
                withServices: [Self.heartRateService],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .poweredOff:
            onStatusChange?(.unavailable("Turn on Bluetooth to connect Myzone"))
        case .unauthorized:
            onStatusChange?(.unavailable("Allow Bluetooth access in Settings"))
        case .unsupported:
            onStatusChange?(.unavailable("Bluetooth heart-rate monitors are unavailable here"))
        case .resetting:
            onStatusChange?(.ready("Bluetooth is restarting…"))
        case .unknown:
            onStatusChange?(.ready("Preparing Bluetooth…"))
        @unknown default:
            onStatusChange?(.unavailable("Bluetooth is unavailable"))
        }
    }

    private func deviceName(for peripheral: CBPeripheral) -> String {
        peripheral.name ?? "Myzone heart-rate monitor"
    }
}

extension BluetoothHeartRateSource: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        startScanningIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isRunning, connectedPeripheral == nil else { return }

        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        onStatusChange?(.connecting(deviceName(for: peripheral)))
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isRunning else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        onStatusChange?(.connecting(deviceName(for: peripheral)))
        peripheral.discoverServices([Self.heartRateService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripheral = nil
        onStatusChange?(.failed(error?.localizedDescription ?? "Could not connect to Myzone"))
        startScanningIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripheral = nil
        guard isRunning else { return }
        onStatusChange?(.ready("Myzone disconnected; reconnecting…"))
        startScanningIfPossible()
    }
}

extension BluetoothHeartRateSource: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            onStatusChange?(.failed(error.localizedDescription))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.heartRateService }) else {
            onStatusChange?(.failed("This device does not expose heart-rate data"))
            return
        }
        peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            onStatusChange?(.failed(error.localizedDescription))
            return
        }

        guard let measurement = service.characteristics?.first(where: {
            $0.uuid == Self.heartRateMeasurement
        }) else {
            onStatusChange?(.failed("Heart-rate measurement is unavailable"))
            return
        }

        peripheral.setNotifyValue(true, for: measurement)
        onStatusChange?(.connected(deviceName(for: peripheral)))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == Self.heartRateMeasurement,
              let data = characteristic.value,
              let bpm = HeartRateMeasurementParser.beatsPerMinute(from: data),
              bpm > 0 else { return }

        currentBPM = bpm
        onStatusChange?(.connected(deviceName(for: peripheral)))
        onHeartRateChange?(bpm)
    }
}
