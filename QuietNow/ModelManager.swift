//
//  ModelManager.swift
//  QuietNow
//
//  Created by Spotlight Deveaux on 2023-06-14.
//

import Foundation
import OSLog

let logger = Logger(subsystem: "space.joscomputing.QuietNow", category: "ModelDiscovery")

enum ModelError: Error {
    case modelNotFound
    case invalidSimctlOutput
}

let ModelPathKey = "modelPath"

#if os(macOS)

    // MARK: simctl output parsing

    // We expect the JSON out to look something like the following:
//
    // {
    //   "runtimes:" [
//     {
//       "runtimeRoot": "[...]"
//     },
//     [...]
    //   ]
    // }
    struct SimctlRuntime: Decodable {
        let runtimeRoot: String
    }

    struct SimctlRuntimes: Decodable {
        let runtimes: [SimctlRuntime]
    }

    /// Fetch registered iOS simulator runtimes.
    ///
    /// In Xcode 15.0 and above, the iOS simulator runtime exists outside of Xcode.
    /// Additionally, in any version previously, Xcode is not necessarily installed within /Applications.
    /// As such, we can utilize `xcrun simctl list runtimes --json` to get all available runtimes.
    func fetchSimulatorRuntimes() throws -> [URL] {
        let simctlPipe = Pipe()

        let simctl = Process()
        // We're hardcoding this - fingers crossed it doesn't change in the future
        simctl.executableURL = URL(filePath: "/usr/bin/xcrun")
        simctl.arguments = ["simctl", "list", "runtimes", "--json"]
        simctl.standardOutput = simctlPipe
        try simctl.run()
        simctl.waitUntilExit()

        // We should be able to parse this as JSON.
        let simctlOutputData = try simctlPipe.fileHandleForReading.readToEnd()
        guard let simctlOutputData else {
            throw ModelError.invalidSimctlOutput
        }

        let simctlRuntimes = try JSONDecoder().decode(SimctlRuntimes.self, from: simctlOutputData)
        let allRuntimeRoots = simctlRuntimes.runtimes.map {
            // Append the runtime roots to the framework path.
            let frameworkPath = $0.runtimeRoot + "/System/Library/PrivateFrameworks/MediaPlaybackCore.framework"
            return URL(filePath: frameworkPath)
        }
        return allRuntimeRoots
    }

    // MARK: Model paths

    /// Attempts to search for a registered model path.
    /// - Returns: A string with the model path, suitable for providing to the Audio Unit. If not possible, returns empty.
    func getFrameworkPaths() -> [URL] {
        // First, let's check if it exists natively - just in case macOS begins shipping with this model.
        var possibleLocations = [
            URL(filePath: "/System/Library/PrivateFrameworks/MediaPlaybackCore.framework/Versions/A/Resources"),
        ]
        // Append simulator runtimes, if possible.
        do {
            let simulatorRuntimes = try fetchSimulatorRuntimes()
            possibleLocations += simulatorRuntimes
        } catch {
            // You'll have to configure the simulator path on your own, sorry :)
        }

        return possibleLocations
    }

#else

    // Shim to provide support for iOS, watchOS, tvOS, xrOS, [...] discovery. It does not throw.
    func getFrameworkPaths() -> [URL] {
        // We will rely on the location of MediaPlaybackCore.framework.
        // While we should likely look up its bundle by identifier, hardcoding will suffice for now.
        return [URL(filePath: "/System/Library/PrivateFrameworks/MediaPlaybackCore.framework")]
    }

#endif

extension URL {
    /// Quick quality-of-life hack to avoid repeatedly calling out to FileManager.
    func exists() -> Bool {
        FileManager.default.fileExists(atPath: rawPath)
    }

    /// A similar quality-of-life hack to avoid a ton of URL encoded paths.
    var rawPath: String {
        path(percentEncoded: false)
    }

    /// Determines whether the given URL is a directory.
    // https://stackoverflow.com/a/65152079
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

/// Determines whether the given location has a model.
/// We determine whether the model's "aufx-nnet-appl.plist" property list is present.
func pathHasValidModel(_ modelPath: URL) -> Bool {
    return modelPath.appending(path: "aufx-nnet-appl.plist").exists()
}

/// Attempts to search for a registered model path.
/// - Returns: A string with the model path, suitable for providing to the Audio Unit. If not possible, returns empty.
func getModelPath() -> String {
    let fileManager = FileManager.default
    
    // 1. 检查缓存
    if let savedPath = UserDefaults.standard.string(forKey: ModelPathKey) {
        let savedURL = URL(fileURLWithPath: savedPath)
        if pathHasValidModel(savedURL) {
            return savedPath
        }
        UserDefaults.standard.removeObject(forKey: ModelPathKey)
    }

    let possibleLocations = getFrameworkPaths()
    
    for frameworkLocation in possibleLocations {
        guard frameworkLocation.exists() else { continue }
        
        // 2. 根目录直接匹配
        if pathHasValidModel(frameworkLocation) {
            UserDefaults.standard.setValue(frameworkLocation.rawPath, forKey: ModelPathKey)
            return frameworkLocation.rawPath
        }
        
        // 3. 尝试使用 Bundle 绕过沙盒目录遍历限制
        if let bundle = Bundle(url: frameworkLocation),
           let plistPath = bundle.path(forResource: "aufx-nnet-appl", ofType: "plist") {
            let modelDir = (plistPath as NSString).deletingLastPathComponent
            UserDefaults.standard.setValue(modelDir, forKey: ModelPathKey)
            return modelDir
        }
        
        // 4. 容错遍历（跳过无权限的系统文件夹，继续寻找子目录）
        if let enumerator = fileManager.enumerator(
            at: frameworkLocation,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { (_, _) -> Bool in
                return true // 忽略沙盒权限错误
            }
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "aufx-nnet-appl.plist" {
                    let modelDir = fileURL.deletingLastPathComponent().path
                    UserDefaults.standard.setValue(modelDir, forKey: ModelPathKey)
                    return modelDir
                }
            }
        }
    }

    return "" // 找不到交给底层系统的 fallback 处理
}
