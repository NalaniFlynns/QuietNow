//
//  QuietNowApp.swift
//  QuietNow
//

import SwiftUI

@main
struct QuietNowApp: App {
    var body: some Scene {
        // 废弃原作者的 DocumentGroup，改用标准的 WindowGroup
        WindowGroup {
            MainView() // 加载我们自己写的主界面
        }
        
        #if os(macOS)
            Settings {
                SettingsView()
            }
        #endif
    }
}
