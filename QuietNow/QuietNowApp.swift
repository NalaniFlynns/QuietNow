//
//  QuietNowApp.swift
//  QuietNow
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

@main
struct QuietNowApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

// 我们把 MainView 直接写在入口文件里，这样就不需要修改 Xcode 工程目录了
struct MainView: View {
    @State private var isPickerPresented = false
    @StateObject private var currentTrack = PlayingTrack()
    
    @State private var trackLoaded = false
    @State private var errorText = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("正在处理音频并加载 AI 模型...")
                        .scaleEffect(1.2)
                } else if trackLoaded {
                    PlayerView()
                        .environmentObject(currentTrack)
                } else {
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .padding(.bottom, 10)
                    
                    Text("QuietNow 声音隔离")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("请选择要处理的音频文件")
                        .foregroundColor(.gray)
                    
                    if !errorText.isEmpty {
                        Text(errorText)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    Button(action: {
                        errorText = ""
                        isPickerPresented = true
                    }) {
                        Text("选择音频文件")
                            .font(.headline)
                            .padding()
                            .frame(width: 220)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                    }
                    .padding(.top, 20)
                }
            }
            .padding()
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, UTType(filenameExtension: "flac") ?? .audio, UTType(filenameExtension: "m4a") ?? .audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result: result)
            }
        }
    }

    func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            guard selectedURL.startAccessingSecurityScopedResource() else {
                errorText = "没有权限读取该文件，请把文件移至本地文件夹后重试。"
                return
            }
            
            isLoading = true
            
            Task {
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(selectedURL.lastPathComponent)
                
                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: selectedURL, to: tempURL)
                    selectedURL.stopAccessingSecurityScopedResource()
                    
                    let asset = AVURLAsset(url: tempURL)
                    try await currentTrack.load(asset: asset)
                    
                    await MainActor.run {
                        isLoading = false
                        trackLoaded = true
                    }
                } catch {
                    selectedURL.stopAccessingSecurityScopedResource()
                    await MainActor.run {
                        isLoading = false
                        errorText = "加载失败: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            errorText = "选择文件出错: \(error.localizedDescription)"
        }
    }
}
