//
//  ViewController.swift
//  TestBluetooth
//
//  Created by 王玮 on 2023/11/6.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        FZNewBluetoothManager.shared.startScan { peripheral in
            FZNewBluetoothManager.shared.connect(peripheral) { success in
                
            }
        }
    }
}

