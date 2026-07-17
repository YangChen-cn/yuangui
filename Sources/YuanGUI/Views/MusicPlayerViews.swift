import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct MusicArtworkView: View {
    let track: MusicTrack?
    var size: CGFloat = 54

    var body: some View {
        Group {
            if let url = displayCoverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(.white.opacity(0.28), lineWidth: 0.7))
    }

    private var displayCoverURL: URL? {
        guard let url = track?.coverURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return track?.coverURL
        }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        return components.url
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.pink.opacity(0.72), .purple.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: track?.source.systemImage ?? "music.note")
                .font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

struct MusicTransportControls: View {
    @ObservedObject var music: MusicStore
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 15 : 22) {
            Button(action: music.previous) { Image(systemName: "backward.fill") }
            Button(action: music.playPause) {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 15 : 20, weight: .bold))
                    .frame(width: compact ? 27 : 38, height: compact ? 27 : 38)
                    .background(.primary.opacity(0.10), in: Circle())
            }
            Button(action: music.next) { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.plain)
        .disabled(!music.canControl && music.source == .bilibili && music.playlist.isEmpty)
    }
}

struct MusicProgressView: View {
    @ObservedObject var music: MusicStore
    var body: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { music.position }, set: music.seek), in: 0...max(music.duration, 1))
                .controlSize(.mini)
                .disabled(music.duration <= 0)
            HStack {
                Text(formatTime(music.position)); Spacer(); Text(formatTime(music.duration))
            }
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

struct MiniMusicPlayerView: View {
    @ObservedObject var music: MusicStore
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MusicArtworkView(track: music.currentTrack, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(music.currentTrack?.title ?? "暂无播放内容").font(.headline).lineLimit(1)
                    Text(music.currentTrack?.artist ?? music.source.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Label(music.source.title, systemImage: music.source.systemImage)
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            MusicProgressView(music: music)
            HStack {
                Button { music.toggleLyricsVisible() } label: {
                    Image(systemName: music.lyricsVisible ? "quote.bubble.fill" : "quote.bubble")
                }.help(music.lyricsVisible ? "隐藏桌面歌词" : "显示桌面歌词")
                Button { music.setLyricsPanelLocked(!music.lyricsPanelLocked) } label: {
                    Image(systemName: music.lyricsPanelLocked ? "lock.fill" : "lock.open")
                }.help(music.lyricsPanelLocked ? "解锁桌面歌词" : "锁定桌面歌词")
                Spacer()
                MusicTransportControls(music: music, compact: true)
                Spacer()
                Button { music.showFullPlayer() } label: { Image(systemName: "list.bullet") }.help("打开完整播放器")
            }.buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 300)
    }
}

struct MusicStatusCard: View {
    @ObservedObject var music: MusicStore
    @State private var searchTitle = ""
    @State private var searchArtist = ""
    @State private var selectedLibraryID = "queue"

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                nowPlayingSection
                if music.source == .bilibili { bilibiliLibrarySection }
                else { appleMusicQueueSection }
                playbackSettingsSection
            }
            .padding(.horizontal, 1)
            .padding(.bottom, 2)
        }
        .onAppear(perform: syncSearchFields)
        .onChange(of: music.currentTrack?.id) { _, _ in syncSearchFields() }
        .onChange(of: music.source) { _, _ in
            selectedLibraryID = "queue"
            syncSearchFields()
        }
    }

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(music.currentTrack == nil ? "音乐" : "正在播放", systemImage: music.source.systemImage)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                if let track = music.currentTrack, track.source == .bilibili {
                    Button { music.toggleFavorite(track) } label: {
                        Image(systemName: music.isFavorite(track) ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(music.isFavorite(track) ? .pink : .secondary)
                    .help(music.isFavorite(track) ? "取消收藏当前歌曲" : "收藏当前歌曲")
                }
                Button { music.showFullPlayer() } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain)
                    .help("打开完整播放器")
            }
            if let track = music.currentTrack {
                HStack(spacing: 11) {
                    MusicArtworkView(track: track, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label(music.source.title, systemImage: music.source.systemImage)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                MusicProgressView(music: music)
                HStack {
                    MusicTransportControls(music: music, compact: true)
                    Spacer()
                    Toggle("桌面歌词", isOn: Binding(
                        get: { music.lyricsVisible },
                        set: { _ in music.toggleLyricsVisible() }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            } else {
                Text("暂无播放内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(music.source == .appleMusic ? "打开 Apple Music" : "导入 B 站歌曲…") {
                    if music.source == .appleMusic { music.connectAppleMusic() }
                    else { music.showFullPlayer() }
                }
                .controlSize(.small)
            }
        }
        .musicDashboardSection()
    }

    private var playbackSettingsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("播放与歌词", systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Picker("播放源", selection: Binding(get: { music.source }, set: music.setSource)) {
                ForEach(MusicSource.allCases) { source in
                    Label(source.title, systemImage: source.systemImage).tag(source)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Text("歌词偏移").font(.caption)
                Slider(
                    value: Binding(get: { music.currentLyricOffset }, set: music.setLyricOffset),
                    in: -30...30,
                    step: 0.1
                )
                .disabled(music.currentTrack == nil)
                Text(String(format: "%+.1fs", music.currentLyricOffset))
                    .font(.system(size: 9, design: .monospaced))
                    .frame(width: 45, alignment: .trailing)
            }
            if music.source == .bilibili, music.currentTrack != nil {
                VStack(alignment: .leading, spacing: 5) {
                    Text("歌曲信息与歌词匹配")
                        .font(.caption.weight(.semibold))
                    HStack {
                        TextField("歌曲名", text: $searchTitle)
                        TextField("歌手", text: $searchArtist)
                    }
                    HStack {
                        Button {
                            music.searchLyrics(title: searchTitle, artist: searchArtist)
                        } label: {
                            if music.isSearchingLyrics { ProgressView().controlSize(.mini) }
                            else { Label("匹配歌词并更新信息", systemImage: "text.magnifyingglass") }
                        }
                        .disabled(music.isSearchingLyrics || searchTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    .controlSize(.small)
                    if let message = music.lyricsSearchMessage {
                        Text(message)
                            .font(.system(size: 9))
                            .foregroundStyle(message.hasPrefix("已匹配") ? Color.green : Color.orange)
                    }
                }
            }
        }
        .musicDashboardSection()
    }

    private var bilibiliLibrarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Bilibili 资料库", systemImage: "music.note.list")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                if let track = music.currentTrack, track.source == .bilibili {
                    Menu {
                        if music.savedPlaylists.isEmpty { Text("尚未创建歌单") }
                        else {
                            ForEach(music.savedPlaylists) { playlist in
                                Button(playlist.name) { music.add(track, to: playlist) }
                            }
                        }
                    } label: { Image(systemName: "text.badge.plus") }
                    .menuStyle(.borderlessButton)
                    .frame(width: 22)
                    .help("把当前歌曲加入歌单")
                }
            }
            Menu {
                Button("当前播放列表（\(music.playlist.count)）") { selectedLibraryID = "queue" }
                Button("收藏歌曲（\(music.favoriteTracks.count)）") { selectedLibraryID = "favorites" }
                if !music.savedPlaylists.isEmpty { Divider() }
                ForEach(music.savedPlaylists) { playlist in
                    Button("\(playlist.name)（\(music.tracks(in: playlist).count)）") {
                        selectedLibraryID = "playlist:\(playlist.id.uuidString)"
                    }
                }
            } label: {
                HStack {
                    Text(selectedLibraryTitle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)

            if selectedLibraryTracks.isEmpty {
                Text("这个列表里还没有歌曲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(selectedLibraryTracks.prefix(4))) { track in
                    Button { music.play(track) } label: {
                        HStack(spacing: 8) {
                            MusicArtworkView(track: track, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                                Text(track.artist).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(formatTime(track.duration))
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Image(systemName: music.currentTrack?.id == track.id && music.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(music.currentTrack?.id == track.id ? .pink : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if selectedLibraryTracks.count > 4 {
                    Text("还有 \(selectedLibraryTracks.count - 4) 首，请在完整资料库中查看")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
            Button("打开完整资料库…") { music.showFullPlayer() }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .musicDashboardSection()
    }

    private var appleMusicQueueSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.house.fill")
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Music 播放队列")
                    .font(.caption.weight(.semibold))
                Text("队列和资料库继续由 Music App 管理。")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("打开 Music") { music.openAppleMusic() }
                .controlSize(.small)
        }
        .musicDashboardSection()
    }

    private var selectedLibraryTracks: [MusicTrack] {
        if selectedLibraryID == "favorites" { return music.favoriteTracks }
        if selectedLibraryID.hasPrefix("playlist:"),
           let id = UUID(uuidString: String(selectedLibraryID.dropFirst("playlist:".count))),
           let playlist = music.savedPlaylists.first(where: { $0.id == id }) {
            return music.tracks(in: playlist)
        }
        return music.playlist
    }

    private var selectedLibraryTitle: String {
        if selectedLibraryID == "favorites" { return "收藏歌曲（\(music.favoriteTracks.count)）" }
        if selectedLibraryID.hasPrefix("playlist:"),
           let id = UUID(uuidString: String(selectedLibraryID.dropFirst("playlist:".count))),
           let playlist = music.savedPlaylists.first(where: { $0.id == id }) {
            return "\(playlist.name)（\(music.tracks(in: playlist).count)）"
        }
        return "当前播放列表（\(music.playlist.count)）"
    }

    private func syncSearchFields() {
        searchTitle = music.currentTrack?.title ?? ""
        searchArtist = music.currentTrack?.artist ?? ""
    }
}

private extension View {
    func musicDashboardSection() -> some View {
        padding(10)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.24), lineWidth: 0.6))
    }
}

struct MusicPlayerView: View {
    @ObservedObject var music: MusicStore
    @State private var selectedTrackID: String?
    @State private var selectedCollectionID = "all"
    @State private var isCreatingPlaylist = false
    @State private var newPlaylistName = ""
    @State private var isSearchingLyrics = false
    @State private var isBilibiliLoginPresented = false
    @State private var lyricsSearchTitle = ""
    @State private var lyricsSearchArtist = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("播放来源", selection: Binding(get: { music.source }, set: music.setSource)) {
                ForEach(MusicSource.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 310)
            .padding(.vertical, 10)
            Divider()
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 330)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { selectedTrackID = music.currentTrack?.id }
        .alert("新建歌单", isPresented: $isCreatingPlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") { createPlaylist() }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        } message: {
            Text("歌单只保存在这台 Mac 上。")
        }
        .sheet(isPresented: $isSearchingLyrics) {
            LyricsSearchSheet(
                music: music,
                title: $lyricsSearchTitle,
                artist: $lyricsSearchArtist,
                isPresented: $isSearchingLyrics
            )
        }
        .sheet(isPresented: $isBilibiliLoginPresented) {
            BilibiliLoginSheet(music: music, isPresented: $isBilibiliLoginPresented)
        }
    }

    @ViewBuilder private var sidebar: some View {
        if music.source == .appleMusic {
            List {
                Section("Apple Music") {
                    Label(music.appleMusicRunning ? "Music 正在运行" : "Music 尚未运行", systemImage: "music.note")
                    Button("打开 Music App") { music.openAppleMusic() }
                }
            }.listStyle(.sidebar)
        } else {
            VStack(spacing: 0) {
                HStack {
                    TextField("粘贴 URL 或输入 BV 号", text: $music.importText)
                        .onSubmit(music.importBilibili)
                    Button { music.importBilibili() } label: {
                        music.isImporting ? AnyView(ProgressView().controlSize(.small)) : AnyView(Image(systemName: "plus"))
                    }.disabled(music.isImporting || music.importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(10)
                List(selection: $selectedTrackID) {
                    Section("资料库") {
                        collectionButton("播放列表", systemImage: "music.note.list", id: "all", count: music.playlist.count)
                        collectionButton("收藏", systemImage: "heart.fill", id: "favorites", count: music.favoriteTracks.count)
                    }
                    Section {
                        ForEach(music.savedPlaylists) { savedPlaylist in
                            collectionButton(savedPlaylist.name, systemImage: "music.note.house", id: "playlist:\(savedPlaylist.id.uuidString)", count: music.tracks(in: savedPlaylist).count)
                                .contextMenu {
                                    Button("删除歌单", role: .destructive) {
                                        music.deletePlaylist(savedPlaylist)
                                        if selectedCollectionID == "playlist:\(savedPlaylist.id.uuidString)" { selectedCollectionID = "all" }
                                    }
                                }
                        }
                        Button { isCreatingPlaylist = true } label: { Label("新建歌单", systemImage: "plus") }
                    } header: { Text("我的歌单") }

                    Section(collectionTitle) {
                    ForEach(displayedTracks) { track in
                        HStack(spacing: 8) {
                            Image(systemName: music.currentTrack?.id == track.id && music.isPlaying ? "speaker.wave.2.fill" : "music.note")
                                .foregroundStyle(music.currentTrack?.id == track.id ? .pink : .secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).lineLimit(1)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(track.id)
                        .contextMenu {
                            Button("播放") { music.play(track) }
                            Button(music.isFavorite(track) ? "取消收藏" : "收藏") { music.toggleFavorite(track) }
                            if !music.savedPlaylists.isEmpty {
                                Menu("加入歌单") {
                                    ForEach(music.savedPlaylists) { savedPlaylist in
                                        Button(savedPlaylist.name) { music.add(track, to: savedPlaylist) }
                                    }
                                }
                            }
                            if let selectedSavedPlaylist {
                                Button("从此歌单移除") { music.remove(track, from: selectedSavedPlaylist) }
                            }
                            Button("从资料库移除", role: .destructive) { music.remove(track) }
                        }
                        .onTapGesture(count: 2) { music.play(track) }
                    }
                    }
                }.listStyle(.sidebar)
                HStack {
                    Text("\(displayedTracks.count) 首").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if selectedCollectionID == "all", !music.playlist.isEmpty {
                        Button("清空") { music.clearPlaylist() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.padding(10)
            }
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topTrailing) {
                    MusicArtworkView(track: music.currentTrack, size: 190)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .frame(maxWidth: .infinity)
                    if music.source == .bilibili {
                        bilibiliAccountButton
                    }
                }
                VStack(spacing: 4) {
                    Text(music.currentTrack?.title ?? emptyTitle).font(.system(size: 24, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                    Text(music.currentTrack?.artist ?? music.source.title).foregroundStyle(.secondary)
                    if let album = music.currentTrack?.album, !album.isEmpty { Text(album).font(.caption).foregroundStyle(.tertiary) }
                }
                MusicProgressView(music: music).frame(maxWidth: 480)
                MusicTransportControls(music: music)
                if music.source == .bilibili, let track = music.currentTrack {
                    Button { music.toggleFavorite(track) } label: {
                        Label(music.isFavorite(track) ? "已收藏" : "收藏", systemImage: music.isFavorite(track) ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                    .tint(.pink)
                }
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(get: { music.volume }, set: music.setVolume), in: 0...1).frame(width: 160)
                    if music.source == .bilibili {
                        Picker("播放模式", selection: Binding(get: { music.playMode }, set: music.setPlayMode)) {
                            ForEach(MusicPlayMode.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                        }.labelsHidden().frame(width: 120)
                    }
                }
                if let line = music.currentLyric?.text {
                    Text(line).font(.system(size: 17, weight: .semibold, design: .rounded)).multilineTextAlignment(.center).padding(.top, 4)
                    if let next = music.nextLyric?.text { Text(next).font(.subheadline).foregroundStyle(.secondary) }
                } else { Text("暂无歌词").foregroundStyle(.secondary) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { lyricsActionButtons }
                    VStack(alignment: .leading, spacing: 7) { lyricsActionButtons }
                }
                lyricsAdjustments
                if let error = music.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    if music.source == .appleMusic { Button("打开自动化权限设置") { music.openAutomationSettings() } }
                }
            }
            .padding(28).frame(maxWidth: .infinity)
        }
    }

    private var bilibiliAccountButton: some View {
        Button { isBilibiliLoginPresented = true } label: {
            HStack(spacing: 7) {
                if let account = music.bilibiliAccount {
                    AsyncImage(url: account.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())

                    Text(account.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 78)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                    Text("登录哔哩哔哩")
                        .font(.callout.weight(.semibold))
                }
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .help(music.bilibiliAccount.map { "已登录：\($0.name)，点击管理账号" } ?? "扫码登录哔哩哔哩")
    }

    private var emptyTitle: String { music.source == .appleMusic ? "连接 Apple Music" : "从左侧导入并选择歌曲" }

    @ViewBuilder
    private var lyricsActionButtons: some View {
        Button(music.lyricsVisible ? "隐藏桌面歌词" : "显示桌面歌词") { music.toggleLyricsVisible() }
        Button("导入 LRC 文件") { chooseLRC() }
        Button("重设歌曲信息并匹配歌词") { prepareLyricsSearch() }
    }

    private var lyricsAdjustments: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("歌词偏移")
                Slider(
                    value: Binding(get: { music.currentLyricOffset }, set: music.setLyricOffset),
                    in: -30...30,
                    step: 0.1
                )
                .frame(width: 210)
                .disabled(music.currentTrack == nil)
                Text(String(format: "%+.1f 秒", music.currentLyricOffset))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 68, alignment: .trailing)
                Button("归零") { music.setLyricOffset(0) }
                    .disabled(abs(music.currentLyricOffset) < 0.001)
            }
            Text("正数会让歌词延后出现，负数会让歌词提前出现。偏移按歌曲保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("桌面歌词字号", systemImage: "textformat.size")
                Slider(
                    value: Binding(get: { music.lyricsFontSize }, set: music.setLyricsFontSize),
                    in: 14...42,
                    step: 1
                )
                .frame(width: 150)
                Text("\(Int(music.lyricsFontSize))")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 24)
                Picker("字体", selection: Binding(
                    get: { music.lyricsFontStyle },
                    set: music.setLyricsFontStyle
                )) {
                    ForEach(LyricsFontStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .labelsHidden()
                .frame(width: 100)
                ColorPicker(
                    "颜色",
                    selection: Binding(
                        get: { Color(nsColor: music.lyricsColor) },
                        set: { music.setLyricsColor(NSColor($0)) }
                    ),
                    supportsOpacity: true
                )
                .fixedSize()
                Toggle("锁定并点击穿透", isOn: Binding(
                    get: { music.lyricsPanelLocked },
                    set: music.setLyricsPanelLocked
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var selectedSavedPlaylist: SavedMusicPlaylist? {
        guard selectedCollectionID.hasPrefix("playlist:"),
              let id = UUID(uuidString: String(selectedCollectionID.dropFirst("playlist:".count))) else { return nil }
        return music.savedPlaylists.first { $0.id == id }
    }

    private var displayedTracks: [MusicTrack] {
        if selectedCollectionID == "favorites" { return music.favoriteTracks }
        if let selectedSavedPlaylist { return music.tracks(in: selectedSavedPlaylist) }
        return music.playlist
    }

    private var collectionTitle: String {
        if selectedCollectionID == "favorites" { return "收藏歌曲" }
        return selectedSavedPlaylist?.name ?? "播放列表"
    }

    private func collectionButton(_ title: String, systemImage: String, id: String, count: Int) -> some View {
        Button { selectedCollectionID = id } label: {
            HStack {
                Label(title, systemImage: systemImage).lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedCollectionID == id ? Color.accentColor : Color.primary)
    }

    private func createPlaylist() {
        if let created = music.createPlaylist(named: newPlaylistName) {
            selectedCollectionID = "playlist:\(created.id.uuidString)"
        }
        newPlaylistName = ""
    }

    private func chooseLRC() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        if panel.runModal() == .OK, let url = panel.url { music.importLRC(from: url) }
    }

    private func prepareLyricsSearch() {
        lyricsSearchTitle = music.currentTrack?.title ?? ""
        lyricsSearchArtist = music.currentTrack?.artist ?? ""
        isSearchingLyrics = true
    }
}

struct BilibiliLoginSheet: View {
    @ObservedObject var music: MusicStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("哔哩哔哩账号", systemImage: "person.crop.circle")
                    .font(.title2.bold())
                Spacer()
            }

            if let account = music.bilibiliAccount {
                VStack(spacing: 10) {
                    AsyncImage(url: account.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable().foregroundStyle(.secondary)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    Text(account.name).font(.headline)
                    Text("已登录，可读取账号有权访问的播放器字幕。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("退出账号", role: .destructive) { music.logoutBilibili() }
                    Spacer()
                    Button("完成") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Group {
                    if let value = music.bilibiliQRCodeURL, let image = qrImage(from: value) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 190, height: 190)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if music.bilibiliLoginPhase == .requestingQRCode {
                        ProgressView("正在生成二维码…")
                            .frame(width: 210, height: 210)
                    } else {
                        Image(systemName: "qrcode")
                            .font(.system(size: 100, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 210, height: 210)
                    }
                }

                Text(loginStatusText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(loginStatusColor)
                Text("请使用哔哩哔哩手机客户端扫码并确认。YuanGUI 不会读取或保存账号密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    Button("取消") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(music.bilibiliQRCodeURL == nil ? "生成二维码" : "刷新二维码") {
                        music.startBilibiliLogin()
                    }
                    .disabled(music.bilibiliLoginPhase == .requestingQRCode)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            if music.bilibiliAccount == nil,
               music.bilibiliLoginPhase != .requestingQRCode,
               music.bilibiliLoginPhase != .waitingForScan,
               music.bilibiliLoginPhase != .waitingForConfirmation {
                music.startBilibiliLogin()
            }
        }
        .onDisappear {
            if music.bilibiliAccount == nil { music.cancelBilibiliLogin() }
        }
    }

    private var loginStatusText: String {
        switch music.bilibiliLoginPhase {
        case .loggedOut: return "尚未登录"
        case .requestingQRCode: return "正在连接哔哩哔哩…"
        case .waitingForScan: return "等待扫码"
        case .waitingForConfirmation: return "已扫码，请在手机上确认"
        case .expired: return "二维码已失效，请刷新"
        case .loggedIn: return "登录成功"
        case .failed(let message): return message
        }
    }

    private var loginStatusColor: Color {
        switch music.bilibiliLoginPhase {
        case .failed, .expired: return .orange
        case .waitingForConfirmation: return .blue
        default: return .secondary
        }
    }

    private func qrImage(from value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else {
            return nil
        }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

private struct LyricsSearchSheet: View {
    @ObservedObject var music: MusicStore
    @Binding var title: String
    @Binding var artist: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重设歌曲信息并搜索歌词")
                .font(.title2.bold())
            Text("可以把 B 站视频标题和 UP 主改成真实歌曲名、歌手，再从 LRCLIB 匹配同步歌词。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                TextField("歌曲名", text: $title)
                TextField("歌手", text: $artist)
            }
            .formStyle(.grouped)
            if let message = music.lyricsSearchMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("已匹配") ? .green : .orange)
            }
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button {
                    music.searchLyrics(title: title, artist: artist)
                } label: {
                    if music.isSearchingLyrics { ProgressView().controlSize(.small) }
                    else { Text("匹配并更新") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(music.isSearchingLyrics || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 430)
    }
}

struct PetMusicLyricBubble: View {
    let text: String
    var alertText: String? = nil
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "music.note").foregroundStyle(.pink).font(.headline)
            Text(text).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(2)
            if let alertText {
                Label(alertText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.orange.opacity(0.12), in: Capsule())
                    .fixedSize()
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.42), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .frame(maxWidth: 350)
    }
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00" }
    return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}
