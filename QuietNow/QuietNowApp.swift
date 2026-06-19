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
            // 🚀 核心修复：把 allowedContentTypes 改成 [.item]，允许点击任何文件，彻底解决灰色点不动的问题
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.item], 
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
            
            // 🚀 核心修复 2：我们自己来手动验证是不是音频文件
            let validExtensions = ["mp3", "m4a", "wav", "flac", "aac", "alac", "ogg"]
            guard validExtensions.contains(selectedURL.pathExtension.lowercased()) else {
                errorText = "格式不支持！请选择有效的音频文件 (如 MP3, M4A, FLAC, WAV)。"
                return
            }
            
            guard selectedURL.startAccessingSecurityScopedResource() else {
                errorText = "没有权限读取该文件，请把文件移至“我的 iPhone”本地文件夹后重试。"
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
