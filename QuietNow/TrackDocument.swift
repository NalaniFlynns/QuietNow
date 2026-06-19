//
//  TrackDocument.swift
//  QuietNow
//

import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TrackDocument: FileDocument {
    // 修复 1：明确列出常见的精确音频 UTType，绕过 SwiftUI 泛型匹配 Bug，防止点击被吞
    static var readableContentTypes: [UTType] = [
        .audio,
        .mp3,
        .mpeg4Audio,
        .wav,
        UTType(filenameExtension: "flac") ?? .audio,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "aac") ?? .audio
    ]
    static var writableContentTypes: [UTType] = []

    let ingressQueue = DispatchQueue(label: "space.joscomputing.QuietNow.asset-ingress-queue")
    let ingressDelegate: AVIngressDelegate
    let audioAsset: AVURLAsset
    
    // 修复 2：增加一个错误收集器，防止静默闪退
    var initError: String? = nil

    init(configuration: ReadConfiguration) throws {
        if let fileContents = configuration.file.regularFileContents {
            audioAsset = AVURLAsset(url: URL(string: "asset-ingress://example")!)
            ingressDelegate = AVIngressDelegate(contents: fileContents, type: configuration.contentType)
            audioAsset.resourceLoader.setDelegate(ingressDelegate, queue: ingressQueue)
        } else {
            // 关键：不要在这里 throw 异常（throw 会导致点击后无反应），而是保存错误交给 UI 显示
            self.initError = "无法读取文件数据 (regularFileContents 为空)。请确保文件没有损坏，且已经完全下载到本地。"
            audioAsset = AVURLAsset(url: URL(string: "asset-ingress://error")!)
            ingressDelegate = AVIngressDelegate(contents: Data(), type: .audio)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}

struct ExportTrackDocument: FileDocument {
    static var readableContentTypes: [UTType] = []
    static var writableContentTypes: [UTType] = [.audio]

    let fileLocation: URL?

    init(configuration _: ReadConfiguration) throws {
        throw CocoaError(.fileReadNoPermission)
    }

    init(location: URL) {
        fileLocation = location
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        guard let fileLocation else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try FileWrapper(url: fileLocation, options: .immediate)
    }
}

struct TrackDocumentView: View {
    var file: TrackDocument
    @StateObject var currentTrack = PlayingTrack()

    @State private var trackLoaded = false
    @State private var errorText = ""

    var body: some View {
        // 修复 3：动态展示拦截下来的错误，不再卡在原界面
        if let initError = file.initError {
            VStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                Text("文件读取失败")
                    .font(.headline)
                    .padding(.top)
                Text(initError)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        } else if trackLoaded {
            PlayerView()
                .environmentObject(currentTrack)
        } else if errorText != "" {
            VStack {
                Image(systemName: "xmark.circle")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                Text("加载遇到错误：")
                    .font(.headline)
                    .padding(.top)
                Text(errorText)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        } else {
            ProgressView("正在加载音频...")
                .task {
                    do {
                        try await currentTrack.load(asset: file.audioAsset)
                        trackLoaded = true
                    } catch let e {
                        print("加载轨道异常: \(e)")
                        errorText = "模型或音频加载异常:\n\(e.localizedDescription)"
                    }
                }
                .padding()
        }
    }
}
