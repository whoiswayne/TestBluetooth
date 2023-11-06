//
//  FZNewBluetoothManager.swift
//  MyFzone
//
//  Created by Wayne on 2023/10/30.
//

import Foundation
import SwiftyBluetooth
import CoreBluetooth
import HWWeakTimer

public let kBluetoothService = "AE30"
public let kBluetoothWriteChar = "AE01"
public let kBluetoothReadChar = "AE02"

public let kBluetoothNamePrefix = "fzone"

public class FZNewBluetoothManager {
    static let shared = FZNewBluetoothManager()
    
    var timer: Timer?
    public var scannedPerDict = [String: Peripheral]()
    public var connectedDict = [String: Peripheral]()
    
    private var notifiedChars = [String: CBCharacteristic]()
    
    public func startScan(_ completion: @escaping (_ peripheral: Peripheral) -> Void) {
        scanForPeripherals(timeoutAfter: 15) { result in
            switch result {
            case .scanStarted:
                break
            case .scanResult(peripheral: let peripheral, advertisementData: let data, RSSI: let RSSI):
                guard let name = peripheral.name, name.lowercased().hasPrefix(kBluetoothNamePrefix) else {
                    return
                }
                if !self.scannedPerDict.keys.contains(peripheral.identifier.uuidString) {
                    self.scannedPerDict[peripheral.identifier.uuidString] = peripheral
                    completion(peripheral)
                }
            case .scanStopped(peripherals: let peripherals, error: let error):
                print("[Scan] stopped: ", peripherals.compactMap({ per in
                    per.identifier.uuidString
                }), "error: ", error?.localizedDescription ?? "")
            }
        }
    }
    
    public func connect(_ peripheral: Peripheral, completion: @escaping ((_ success: Bool) -> Void)) {
        peripheral.connect(withTimeout: 15) { result in
            switch result {
            case .success():
                completion(true)
                self.discoverServices(peripheral, completion: completion)
            case .failure(_):
                completion(false)
            }
        }
    }
    
    public func disconnect(_ per: Peripheral) {
        stopTimer()
        per.disconnect { result in
            switch result {
            case .success(_):
                break
            case .failure(_):
                break
            }
        }
    }
    
    func discoverServices(_ peripheral: Peripheral, completion: @escaping ((_ success: Bool) -> Void)) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            peripheral.discoverServices(withUUIDs: [kBluetoothService]) { result in
                switch result {
                case .success(let services):
                    for s in services {
                        if s.uuid.uuidString == kBluetoothService {
                            self.discoverCharacteristics(peripheral, service: s.uuid, completion: completion)
                        }
                    }
                case .failure(_):
                    break
                }
            }
        })
    }
    
    func discoverCharacteristics(_ peripheral: Peripheral, service: CBUUIDConvertible, completion: @escaping ((_ success: Bool) -> Void)) {
        peripheral.discoverCharacteristics(withUUIDs: [kBluetoothWriteChar, kBluetoothReadChar], ofServiceWithUUID: service) { result in
            switch result {
            case .success(let characteristics):
                NotificationCenter.default.addObserver(forName: Peripheral.PeripheralCharacteristicValueUpdate,
                                                        object: peripheral,
                                                        queue: nil) { (notification) in
                    let charac = notification.userInfo!["characteristic"] as! CBCharacteristic
                    if let error = notification.userInfo?["error"] as? SBError {
                        // Deal with error
                    }
                    print("receive characteristicValueUpdate notification")
                    // stopTimer()
                }
                for char in characteristics {
                    if char.uuid.uuidString == kBluetoothReadChar {
                        self.notifiedChars[peripheral.identifier.uuidString] = char
                        peripheral.setNotifyValue(toEnabled: true, ofCharac: char) { [weak self] result in
                            switch result {
                            case .success(let isNotifying):
                                if isNotifying {
                                    self?.sendBiz(peripheral)
                                }
                            case .failure(_):
                                break
                            }
                        }
                    }
                }
                completion(true)
            case .failure(_):
                completion(false)
            }
        }
    }
    
    func sendBiz(_ peripheral: Peripheral) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            // 连接后设置蓝牙设备的时间
            self.timer = HWWeakTimer.scheduledTimer(withTimeInterval: 1, block: { [weak self] obj in
                self?.sendSetTimeMsg(peripheral)
            }, userInfo: nil, repeats: true)
            if let timer = self.timer {
                RunLoop.current.add(timer, forMode: .common)
            }
        })
    }
    
    func readValue(_ per: Peripheral, char: CBCharacteristic, completion: @escaping ((_ data: Data) -> Void)) {
        per.readValue(ofCharac: char) { result in
            switch result {
            case .success(let data):
                print("[Read] AE02", String(data: data, encoding: .utf8) ?? "empty")
                completion(data)
            case .failure(_):
                break // An error happened while attempting to read the data
            }
        }
    }
    
    func sendMsg(_ cmd: String, peripheral: Peripheral) {
        guard let data = cmd.data(using: String.Encoding.utf8) else {
            return
        }
        if data.count <= 180 {
            sendData(data, peripheral: peripheral)
        } else {
            // 分段写入
        }
    }
    
    func sendData(_ data: Data, peripheral: Peripheral) {
        peripheral.writeValue(ofCharacWithUUID: kBluetoothWriteChar, fromServiceWithUUID: kBluetoothService, value: data, type: .withoutResponse) { result in
            switch result {
            case .success(_):
                print("[写入指令成功]: \(String(data: data, encoding: .utf8) ?? "")")
                break
            case .failure(_):
                break
            }
        }
    }

    public func sendSetTimeMsg(_ peripheral: Peripheral) {
//        let msg = "55AA0600080D170b07000325036e"
        let msg = "55AA0600080D170b061718030276"
        print("[写入指令]", msg)
        sendMsg(msg, peripheral: peripheral)
    }

    func stopTimer() {
        guard let timer else {
            return
        }
        timer.invalidate()
        self.timer = nil
    }
}
