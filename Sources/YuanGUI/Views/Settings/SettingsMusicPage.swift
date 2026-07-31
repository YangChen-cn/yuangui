import AppKit
import SwiftUI

struct SettingsMusicPage: View {
    let music: MusicFeature
    @ObservedObject private var musicPlayback: MusicPlaybackStore
    @ObservedObject private var lyricsPresentation: LyricsPresentationStore
    @ObservedObject var externalAudioInterruption: ExternalAudioInterruptionController
    @ObservedObject private var bilibiliAccount: BilibiliAccountStore
    @Environment(\.appActions) private var appActions
    @State private var isBilibiliLoginPresented = false

    init(
        music: MusicFeature,
        externalAudioInterruption: ExternalAudioInterruptionController
    ) {
        self.music = music
        _musicPlayback = ObservedObject(wrappedValue: music.playback)
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
        self.externalAudioInterruption = externalAudioInterruption
        _bilibiliAccount = ObservedObject(wrappedValue: music.bilibiliAccountStore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: "音乐",
                subtitle: "管理播放来源、桌面歌词与外部声音协作",
                systemImage: "music.note",
                accent: .purple
            )
            Form {
                Section("播放器") {
                    Picker("默认播放来源", selection: Binding(
                        get: { musicPlayback.source },
                        set: music.setSource
                    )) {
                        ForEach(MusicSource.allCases) {
                            Label($0.title, systemImage: $0.systemImage).tag($0)
                        }
                    }
                    Toggle("显示桌面悬浮歌词", isOn: Binding(
                        get: { lyricsPresentation.isVisible },
                        set: { _ in music.toggleLyricsVisible() }
                    ))
                    Toggle("轻量跟唱（歌词气泡与轻微律动）", isOn: Binding(
                        get: { lyricsPresentation.lightSingAlongEnabled },
                        set: music.setLightSingAlongEnabled
                    ))
                    Toggle("锁定悬浮歌词并允许点击穿透", isOn: Binding(
                        get: { lyricsPresentation.isPanelLocked },
                        set: music.setLyricsPanelLocked
                    ))
                    Toggle("显示桌面歌词文字阴影", isOn: Binding(
                        get: { lyricsPresentation.shadowEnabled },
                        set: music.setLyricsShadowEnabled
                    ))
                    Toggle("增强桌面歌词背景对比度", isOn: Binding(
                        get: { lyricsPresentation.backgroundVisible },
                        set: music.setLyricsBackgroundVisible
                    ))
                    LabeledContent("桌面歌词细条透明度") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { lyricsPresentation.backgroundOpacity },
                                    set: music.setLyricsBackgroundOpacity
                                ),
                                in: 0.12...0.60,
                                step: 0.01
                            )
                            Text(
                                lyricsPresentation.backgroundOpacity,
                                format: .percent.precision(.fractionLength(0))
                            )
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 42, alignment: .trailing)
                        }
                    }
                    LabeledContent("桌面歌词字号") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { lyricsPresentation.fontSize },
                                    set: music.setLyricsFontSize
                                ),
                                in: 14...42,
                                step: 1
                            )
                            Text("\(Int(lyricsPresentation.fontSize))")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    Picker("桌面歌词字体", selection: Binding(
                        get: { lyricsPresentation.fontStyle },
                        set: music.setLyricsFontStyle
                    )) {
                        ForEach(LyricsFontStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    ColorPicker(
                        "桌面歌词颜色",
                        selection: Binding(
                            get: { Color(nsColor: lyricsPresentation.color) },
                            set: { music.setLyricsColor(NSColor($0)) }
                        ),
                        supportsOpacity: true
                    )
                    Text("关闭轻量跟唱后，播放期间只显示轻量音乐状态；番茄钟专注时会自动隐藏桌宠歌词气泡。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("外部声音") {
                    Toggle("其他应用播放声音时暂停音乐", isOn: Binding(
                        get: { externalAudioInterruption.isEnabled },
                        set: externalAudioInterruption.setEnabled
                    ))
                    Toggle("外部声音结束后自动继续", isOn: Binding(
                        get: { externalAudioInterruption.resumesAfterExternalAudio },
                        set: externalAudioInterruption.setResumesAfterExternalAudio
                    ))
                    .disabled(!externalAudioInterruption.isEnabled)
                    Text("其他应用连续播放约 1 秒后才暂停；安静约 2.5 秒后才尝试恢复。系统提示音和短暂通知不会触发。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Apple Music") {
                    HStack {
                        Text(musicPlayback.appleMusicRunning ? "Music App 正在运行" : "Music App 尚未运行")
                        Spacer()
                        Button("连接") { music.connectAppleMusic() }
                        Button("权限设置", action: music.openAutomationSettings)
                    }
                    Text("YuanGUI 只控制系统 Music App，不提取或重新播放 Apple Music 音频。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("哔哩哔哩") {
                    HStack {
                        Label(
                            bilibiliAccount.account.map { "已登录：\($0.name)" } ?? "未登录",
                            systemImage: bilibiliAccount.account == nil
                                ? "person.crop.circle.badge.questionmark"
                                : "person.crop.circle.badge.checkmark"
                        )
                        Spacer()
                        Button(bilibiliAccount.account == nil ? "扫码登录" : "账号管理") {
                            isBilibiliLoginPresented = true
                        }
                    }
                    Text("登录后可读取账号有权访问的播放器字幕。登录 Cookie 与刷新令牌仅保存在本机应用数据中，不会读取账号密码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("打开完整音乐播放器") {
                    appActions.open(.music)
                }
                .buttonStyle(.borderedProminent)
            }
            .formStyle(.grouped)
        }
        .sheet(isPresented: $isBilibiliLoginPresented) {
            BilibiliLoginSheet(music: music, isPresented: $isBilibiliLoginPresented)
        }
    }
}
