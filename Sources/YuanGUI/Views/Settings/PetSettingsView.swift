import SwiftUI

struct PetSettingsView: View {
    @ObservedObject var pet: PetStore
    @ObservedObject var loginItem: LoginItemStore
    let showPet: () -> Void

    @State private var advancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
                SettingsPageHeader(
                    title: "桌宠",
                    subtitle: "让元圭与 VCC 以你喜欢的方式陪伴在桌面上",
                    systemImage: "pawprint.fill"
                )
                petPreview
                appearanceSection
                companionSection
                reminderSection
                desktopBehaviorSection
                advancedSection
                footer
            }
            .padding(.bottom, 8)
        }
        .onAppear(perform: loginItem.refresh)
    }

    private var petPreview: some View {
        HStack(spacing: 14) {
            DashboardPetAvatarView(mode: pet.mode)
                .scaleEffect(1.08)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalizer.string(pet.mode.title))
                    .font(.headline)
                Text("\(AppLocalizer.string("大小")) \(Int((pet.petScale * 100).rounded()))% · \(AppLocalizer.string(pet.dashboardStyle.title))")
                    .foregroundStyle(.secondary)
                Label(
                    AppLocalizer.string(pet.showsSystemStatus ? "迷你状态已显示" : "迷你状态已隐藏"),
                    systemImage: pet.showsSystemStatus ? "checkmark.circle.fill" : "circle"
                )
                .font(.caption)
                .foregroundStyle(pet.showsSystemStatus ? Color.accentColor : Color.secondary)
            }
            Spacer()
            Button("显示桌宠", action: showPet)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.07), in: .rect(cornerRadius: SettingsDesign.sectionRadius))
    }

    private var appearanceSection: some View {
        SettingsSectionCard(title: "外观", systemImage: "paintpalette") {
            Picker("当前角色", selection: Binding(
                get: { pet.mode },
                set: { pet.setMode($0); showPet() }
            )) {
                ForEach(PetMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            LabeledContent("桌宠大小") {
                HStack {
                    Slider(
                        value: Binding(get: { pet.petScale }, set: pet.setPetScale),
                        in: PetLayout.minimumScale...PetLayout.maximumScale,
                        step: 0.05
                    )
                    Text("\(Int((pet.petScale * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Picker("状态面板风格", selection: Binding(
                get: { pet.dashboardStyle },
                set: pet.setDashboardStyle
            )) {
                ForEach(DashboardStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("帧动画", isOn: Binding(
                get: { pet.petMotionEnabled },
                set: pet.setPetMotionEnabled
            ))
            Toggle("空闲时自动轮播普通动作", isOn: Binding(
                get: { pet.idleAnimationEnabled },
                set: pet.setIdleAnimationEnabled
            ))
        }
    }

    private var companionSection: some View {
        SettingsSectionCard(title: "陪伴", systemImage: "heart") {
            Toggle("根据系统、天气和时间智能改变动作", isOn: Binding(
                get: { pet.smartReactionsEnabled },
                set: pet.setSmartReactionsEnabled
            ))
            Toggle("桌宠主动和你说话", isOn: Binding(
                get: { pet.ambientChatterEnabled },
                set: pet.setAmbientChatterEnabled
            ))
            if pet.ambientChatterEnabled {
                LabeledContent("日常对白频率") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(pet.ambientChatterIntervalMinutes) },
                                set: { pet.setAmbientChatterIntervalMinutes(Int($0.rounded())) }
                            ),
                            in: 1...120,
                            step: 1
                        )
                        Text("\(pet.ambientChatterIntervalMinutes) 分钟")
                            .monospacedDigit()
                            .frame(width: 66, alignment: .trailing)
                    }
                }
                Toggle("天气刷新后主动播报", isOn: Binding(
                    get: { pet.weatherAnnouncementsEnabled },
                    set: pet.setWeatherAnnouncementsEnabled
                ))
            }
            Toggle("夜深了提醒", isOn: Binding(
                get: { pet.bedtimeReminderEnabled },
                set: pet.setBedtimeReminderEnabled
            ))
            if pet.bedtimeReminderEnabled {
                bedtimeRange
            }
        }
    }

    private var bedtimeRange: some View {
        LabeledContent("提醒时段") {
            HStack {
                hourPicker("开始", selection: Binding(
                    get: { pet.bedtimeStartMinutes },
                    set: pet.setBedtimeStartMinutes
                ))
                Text("至")
                    .foregroundStyle(.secondary)
                hourPicker("结束", selection: Binding(
                    get: { pet.bedtimeEndMinutes },
                    set: pet.setBedtimeEndMinutes
                ))
            }
        }
    }

    private var reminderSection: some View {
        SettingsSectionCard(title: "提醒", systemImage: "bell") {
            Toggle("低电量提醒", isOn: Binding(
                get: { pet.lowBatteryAlertsEnabled },
                set: pet.setLowBatteryAlertsEnabled
            ))
            if pet.lowBatteryAlertsEnabled || pet.memoryPressureAlertsEnabled {
                Picker("提醒方式", selection: Binding(
                    get: { pet.urgentReminderMode },
                    set: pet.setUrgentReminderMode
                )) {
                    ForEach(UrgentReminderMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var desktopBehaviorSection: some View {
        SettingsSectionCard(title: "桌面行为", systemImage: "desktopcomputer") {
            Toggle("登录时自动启动", isOn: Binding(
                get: { loginItem.isEnabled },
                set: loginItem.setEnabled
            ))
            loginItemStatus
            Toggle("在桌宠上方显示迷你状态气泡", isOn: Binding(
                get: { pet.showsSystemStatus },
                set: pet.setSystemStatusVisible
            ))
            Toggle("锁定桌宠并允许鼠标点击穿透", isOn: Binding(
                get: { pet.interactionLocked },
                set: pet.setInteractionLocked
            ))
        }
    }

    @ViewBuilder
    private var loginItemStatus: some View {
        if loginItem.status == .requiresApproval {
            HStack {
                Label("需要在系统设置中批准登录项", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                Button("打开系统设置", action: loginItem.openSystemSettings)
            }
        } else if let message = loginItem.message {
            Text(AppLocalizer.string(message))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !loginItem.isInApplicationsFolder {
            Text("建议先把 YuanGUI.app 放入“应用程序”文件夹，再开启自启。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var advancedSection: some View {
        SettingsSectionCard(title: "高级设置", systemImage: "slider.horizontal.3") {
            DisclosureGroup("系统压力提醒", isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: SettingsDesign.compactSpacing) {
                    Toggle("内存紧张提醒", isOn: Binding(
                        get: { pet.memoryPressureAlertsEnabled },
                        set: pet.setMemoryPressureAlertsEnabled
                    ))
                    Text("内存占用达到 90%，或系统报告严重内存压力时提醒。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if pet.urgentReminderMode == .interval,
                       pet.lowBatteryAlertsEnabled || pet.memoryPressureAlertsEnabled {
                        Stepper(
                            "紧急提醒间隔：\(pet.urgentReminderIntervalMinutes) 分钟",
                            value: Binding(
                                get: { pet.urgentReminderIntervalMinutes },
                                set: pet.setUrgentReminderIntervalMinutes
                            ),
                            in: 5...120,
                            step: 5
                        )
                    }
                }
                .padding(.top, SettingsDesign.compactSpacing)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("恢复默认大小（75%）") {
                pet.setPetScale(PetLayout.defaultScale)
            }
            Spacer()
            Button("显示桌宠", action: showPet)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 2)
    }

    private func hourPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(AppLocalizer.string(title), selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour * 60)
            }
        }
        .labelsHidden()
        .frame(width: 92)
    }
}
