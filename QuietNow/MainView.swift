import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct MainView: View {
    // 控制文件选择器是否弹出
    @State private var isPickerPresented = false
    // 全局音频轨道管理器
    @StateObject private var currentTrack = PlayingTrack()
    
    // 界面状态控制
    @State private var trackLoaded = false
    @State private var errorText = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 状态 1：正在加载（解析模型和音频）
                if isLoading {
                    ProgressView("正在处理音频并加载 AI 模型...")
                        .scaleEffect(1.2)
                } 
                // 状态 2：加载成功，显示原作者的播放调节页
                else if trackLoaded {
                    PlayerView()
                        .environmentObject(currentTrack)
                } 
                // 状态 3：没有任何文件（初始主界面）或者发生错误
                else {
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
            // 绑定文件选择器
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, UTType(filenameExtension: "flac") ?? .audio, UTType(filenameExtension: "m4a") ?? .audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result: result)
            }
        }
    }

    /// 处理用户选中的文件
    func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            
            // 1. 获取安全访问权限 (iOS 沙盒要求)
            guard selectedURL.startAccessingSecurityScopedResource() else {
                errorText = "没有权限读取该文件，请把文件移至iCloud或本地文件夹后重试。"
                return
            }
            
            isLoading = true
            
            Task {
                // 将文件安全地拷贝到 App 的内部缓存中，防止权限随时失效或 OOM 崩溃
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(selectedURL.lastPathComponent)
                
                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: selectedURL, to: tempURL)
                    
                    // 用完后释放原文件的安全权限
                    selectedURL.stopAccessingSecurityScopedResource()
                    
                    // 2. 将内部文件 URL 喂给原作者的音频加载器
                    let asset = AVURLAsset(url: tempURL)
                    try await currentTrack.load(asset: asset)
                    
                    // 3. 成功后切换界面到 PlayerView
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
