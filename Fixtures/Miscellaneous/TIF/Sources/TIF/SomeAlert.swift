//
//  SomeAlert.swift
//  MyFwk
//
//  Created by ankit on 10/31/19.
//  Copyright © 2019 Ankit. All rights reserved.
//

import Cocoa

public class SomeAlert: NSViewController {
    
    @IBOutlet var label: NSTextField!
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        let bundlePath = Bundle.main.path(forResource: "TIF_TIF", ofType: "bundle")!
      let bundle = Bundle(path: bundlePath)!

        let txt = bundle.path(forResource: "some", ofType: "txt")!
        let c = FileManager.default.contents(atPath: txt)!

        label.stringValue = String(data:c, encoding: .utf8)!
        // Do view setup here.
    }
}
