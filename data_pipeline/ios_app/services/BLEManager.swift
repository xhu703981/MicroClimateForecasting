//
//  BLEManager.swift
//  nRFapp
//
//  Created by heartbrokenboy on 9/17/25.
//

//central：iphone； peripheral：Nordic dev kit
import CoreBluetooth
import os

struct Peripheral: Identifiable {
    let id: Int
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

final class BLEManager: NSObject, ObservableObject {
 
    static let NUS_SERVICE = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let NUS_TX      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // notify
    static let NUS_RX      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // write/wwr

    static private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "BLE")

    private var central: CBCentralManager!
    private var connected: CBPeripheral?

    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?

    @Published var isSwitchedOn = false
    @Published var isConnected = false
    @Published var peripherals: [Peripheral] = []
    
    @Published var logLines: [String] = []

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.nRFapp.ble.central"]
        )
    }

    private func log(_ s: String) {
        Self.logger.info("\(s, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.logLines.append(s)
        }
    }

    // MARK: - Public API

    func startScanning() {
        peripherals.removeAll()
        log("Starting scan")
        central.scanForPeripherals(withServices: [Self.NUS_SERVICE], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        log("Stopping scan")
        central.stopScan()
    }

    func connectPeripheral(_ p: CBPeripheral) {
        if let c = connected {
            central.cancelPeripheralConnection(c)
        }
        log("Connecting to \(p.name ?? "<no name>")")
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let c = connected {
            central.cancelPeripheralConnection(c)
        }
    }

    func send(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        send(data: data)
    }

    func send(data: Data) {
        guard let c = connected, let rx = rxCharacteristic else {
            log("send(): not connected or no RX characteristic")
            return
        }
        let writeType: CBCharacteristicWriteType = rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        c.writeValue(data, for: rx, type: writeType)
        log("→ \(String(data: data, encoding: .utf8) ?? "\(data as NSData)")")
    }
    
    private func handleIncoming(text: String) {
        // ✅ FIX 1: Regex now matches actual firmware format:
        // "T=19.37C H=52.82% P=0.000981hPa"
        let pattern = #"T=([-+]?[0-9]*\.?[0-9]+)C\s+H=([-+]?[0-9]*\.?[0-9]+)%\s+P=([-+]?[0-9]*\.?[0-9]+)hPa"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            log("Regex compile error")
            return
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            log("Could not parse: \(text)")
            return
        }

        func extract(_ i: Int) -> Double? {
            guard let r = Range(match.range(at: i), in: text) else { return nil }
            return Double(text[r])
        }

        guard let t = extract(1), let h = extract(2), let p = extract(3) else {
            log("Failed to extract numbers from: \(text)")
            return
        }

        // Convert pressure from hPa (firmware sends kPa divided by 100, i.e. actual hPa)
        // Firmware: sensor_value / 100.0 → result is in hPa already
        let pressure_hpa = p * 1000.0  // firmware sends in kPa, convert to hPa

        log("Parsed → T=\(t)°C, H=\(h)%, P=\(pressure_hpa)hPa")

        // ✅ FIX 2: Correct pressure range — sea level pressure is ~950-1050 hPa
        guard (-40...85).contains(t),
              (0...100).contains(h),
              (800...1100).contains(pressure_hpa) else {
            log("Out-of-range values — T:\(t) H:\(h) P:\(pressure_hpa), skipping upload")
            return
        }

        sendSensorReadingWithTime(tempC: t, humPct: h, presHpa: pressure_hpa)
    }

}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isSwitchedOn = (central.state == .poweredOn)
        log("Central state: \(central.state.rawValue)")
        if isSwitchedOn {
            startScanning()
        } else {
            stopScanning()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber,) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Unknown"

        if peripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            return
        }

        let newPeripheral = Peripheral(id: peripherals.count, name: advName, rssi: RSSI.intValue, peripheral: peripheral)
        peripherals.append(newPeripheral)
        log("Discovered: \(advName) RSSI:\(RSSI)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Connected: \(peripheral.name ?? "<no name>")")
        stopScanning()
        connected = peripheral
        isConnected = true
        rxCharacteristic = nil
        txCharacteristic = nil

        peripheral.delegate = self
        peripheral.discoverServices([Self.NUS_SERVICE])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log("Fail to connect: \(error?.localizedDescription ?? "unknown")")
        isConnected = false
        connected = nil
        startScanning()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log("Disconnected: \(error?.localizedDescription ?? "normal")")
        isConnected = false
        connected = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        startScanning()
    }

    func centralManager(_ central: CBCentralManager,
                        willRestoreState dict: [String: Any]) {
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let peripheral = restoredPeripherals.first {
            connected = peripheral
            isConnected = (peripheral.state == .connected || peripheral.state == .connecting)
            peripheral.delegate = self
            if peripheral.state == .connected {
                peripheral.discoverServices([Self.NUS_SERVICE])
            } else {
                central.connect(peripheral, options: nil)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error { log("discoverServices error: \(e.localizedDescription)") }
        guard let services = peripheral.services, !services.isEmpty else {
            log("No services found"); return
        }
        for s in services where s.uuid == Self.NUS_SERVICE {
            log("NUS service found: \(s.uuid)")
            peripheral.discoverCharacteristics(nil, for: s)
            return
        }
        log("NUS service not found")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let e = error { log("discoverCharacteristics error: \(e.localizedDescription)") }
        guard let chars = service.characteristics, !chars.isEmpty else {
            log("No characteristics"); return
        }

        for ch in chars {
            if ch.properties.contains(.notify) {
                txCharacteristic = ch
                peripheral.setNotifyValue(true, for: ch)
                log("TX (notify) char: \(ch.uuid)")
            }
            if ch.properties.contains(.writeWithoutResponse) || ch.properties.contains(.write) {
                rxCharacteristic = ch
                log("RX (write) char: \(ch.uuid) props:\(ch.properties)")
            }
        }

        if txCharacteristic == nil && rxCharacteristic == nil {
            log("No suitable TX/RX characteristics found. Check UUIDs/firmware.")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error { log("notifyState error: \(e.localizedDescription)") }
        else { log("notifyState for \(characteristic.uuid): \(characteristic.isNotifying)") }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error { log("didUpdateValue error: \(e.localizedDescription)"); return }
        guard let data = characteristic.value else { return }
        let text = String(data: data, encoding: .utf8) ?? "\(data as NSData)"
        log("← \(text)")
        handleIncoming(text: text)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error { log("didWriteValue error: \(e.localizedDescription)") }
        else { log("didWriteValue OK for \(characteristic.uuid)") }
    }
}