//
//  PlayingTrack.swift
//  QuietNow
//
//  Created by Spotlight Deveaux on 2023-03-26.
//

import AVFoundation
import Foundation
import SwiftUI

/// The initial vocal level we want to begin with.
enum PlaybackDefaults {
    public static let initialVocalLevel: Float32 = 85.0
}

// 1. 添加 @MainActor，保证所有的 UI 和 AVPlayerItem 状态更新都在主线程安全执行
@MainActor
class PlayingTrack: ObservableObject {
    @Published public var title = "Unknown title"
    @Published public var artist = "-"
    @Published public var album = "-"
    @Published public var artwork = Image(systemName: "music.quarternote.3")
    @Published public var playerItem: AVPlayerItem?
    private var audioMix: AVAudioMix?

    func load(asset: AVAsset) async throws {
        audioMix = try await createAudioMix(for: asset, initialLevel: PlaybackDefaults.initialVocalLevel)
        playerItem = AVPlayerItem(asset: asset)
        playerItem!.audioMix = audioMix

        let assetMetadata = try await asset.load(.commonMetadata)
        for metadata in assetMetadata {
            guard let keyName = metadata.commonKey else { continue }
            guard let identifierValue = try await metadata.load(.value) else { continue }

            switch keyName {
            case .commonKeyTitle: 
                title = identifierValue as! String
            case .commonKeyAlbumName: 
                album = identifierValue as! String
            case .commonKeyArtist: 
                artist = identifierValue as! String
            case .commonKeyArtwork: 
                artwork = agnosticImage(data: identifierValue as! Data)
            default: 
                break
            }
        }
    }

    func adjust(attenuationLevel: Float32) {
        guard let audioMix else { return }
        audioMix.adjust(attenuationLevel: attenuationLevel)
        print("Attenuation level is now \(attenuationLevel)")
    }

    func export(progress currentProgress: Binding<Float>, attenuationLevel: Float32) async throws -> URL {
        guard let asset = playerItem?.asset else {
            throw PlaybackError.songNotFound
        }

        let temporaryLocation = URL.temporaryDirectory.appending(component: "\(UUID().uuidString).m4a")
        let exportAudioMix = try await createAudioMix(for: asset, initialLevel: attenuationLevel)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw PlaybackError.exportFailed
        }
        exportSession.audioMix = exportAudioMix
        exportSession.outputURL = temporaryLocation
        exportSession.outputFileType = .m4a

        // 2. 启动异步导出任务
        Task {
            await exportSession.export()
        }

        // 3. 废弃 Timer，使用 Swift 6 推荐的 async 循环，彻底解决 Sendable 报错
        while exportSession.status == .waiting || exportSession.status == .exporting {
            currentProgress.wrappedValue = exportSession.progress
            // 暂停 0.5 秒后再刷新进度
            try? await Task.sleep(nanoseconds: 500_000_000) 
        }

        switch exportSession.status {
        case .failed, .cancelled:
            print("Error occurred whilst exporting: \(exportSession.error?.localizedDescription ?? "Empty error")")
            currentProgress.wrappedValue = 0.0
        case .completed:
            print("Export complete.")
            currentProgress.wrappedValue = 0.0
        default:
            print("Export session in state \(exportSession.status)")
            currentProgress.wrappedValue = 0.0
        }

        return temporaryLocation
    }
}

extension AVAudioMix {
    func adjust(attenuationLevel: Float32) {
        let currentTap = inputParameters.first!.audioTapProcessor!
        let metadata = unsafeBitCast(MTAudioProcessingTapGetStorage(currentTap), to: TapMetadata.self)
        let audioUnit = metadata.audioUnit!
        do {
            try audioUnit.setParameter(parameter: 0, scope: .global, value: attenuationLevel, offset: 0)
        } catch let e {
            print("Error adjusting vocal attenuation level: \(e)")
        }
    }
}
