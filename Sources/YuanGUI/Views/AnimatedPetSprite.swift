import AppKit
import SwiftUI

struct PetMotionPose: Equatable {
    var scale: CGFloat = 1
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotationDegrees: Double = 0
    var opacity: Double = 1

    static let rest = PetMotionPose()
    static let intro = PetMotionPose(scale: 0.98, y: 3, opacity: 0.88)
}

enum PetMotionStyle: CaseIterable, Equatable {
    case gentle
    case wave
    case bounce
    case pounce
    case sleepy
    case pulse
    case chomp

    var accentPose: PetMotionPose {
        switch self {
        case .gentle:
            return PetMotionPose(scale: 1.025, y: -3, rotationDegrees: -0.7)
        case .wave:
            return PetMotionPose(scale: 1.02, x: 3, y: -2, rotationDegrees: 2.2)
        case .bounce:
            return PetMotionPose(scale: 1.04, y: -9, rotationDegrees: -1.2)
        case .pounce:
            return PetMotionPose(scale: 1.045, x: 8, y: -5, rotationDegrees: 1.8)
        case .sleepy:
            return PetMotionPose(scale: 0.985, x: -2, y: 4, rotationDegrees: -1.6)
        case .pulse:
            return PetMotionPose(scale: 1.035, y: -2)
        case .chomp:
            return PetMotionPose(scale: 1.045, y: 3, rotationDegrees: 1.2)
        }
    }
}

enum PetMotionProfile {
    static func style(for action: PetAction) -> PetMotionStyle {
        let file = action.file
        if file.contains("eat-trash") { return .chomp }
        if file.contains("pounce") || file.contains("play") { return .pounce }
        if file.contains("hop") || file.contains("alert") || file.contains("maintenance-success") {
            return .bounce
        }
        if file.contains("wave") || file.contains("groom") || file.contains("pet")
            || file.contains("hug") || file.contains("cuddle") || file.contains("finger-heart") {
            return .wave
        }
        if file.contains("sleep") || file.contains("yawn") || file.contains("bedtime")
            || file.contains("low-battery") {
            return .sleepy
        }
        if file.contains("charging") || file.contains("memory-pressure")
            || file.contains("system-meter") || file.contains("maintenance-scan") {
            return .pulse
        }
        return .gentle
    }
}

struct AnimatedPetSprite: View {
    let mode: PetMode
    let action: PetAction
    let motionEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pose = PetMotionPose.rest
    @State private var motionTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image = SpriteLoader.image(mode: mode, action: action) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(.secondary)
            }
        }
        .id("\(mode.id)-\(action.id)")
        .scaleEffect(pose.scale)
        .offset(x: pose.x, y: pose.y)
        .rotationEffect(.degrees(pose.rotationDegrees))
        .opacity(pose.opacity)
        .onAppear { playMotion() }
        .onChange(of: action.id) { _, _ in playMotion() }
        .onChange(of: mode) { _, _ in playMotion() }
        .onChange(of: motionEnabled) { _, enabled in
            enabled ? playMotion() : stopMotion()
        }
        .onDisappear { stopMotion() }
    }

    private var shouldAnimate: Bool {
        motionEnabled && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func playMotion() {
        motionTask?.cancel()
        guard shouldAnimate else {
            pose = .rest
            return
        }
        let accent = PetMotionProfile.style(for: action).accentPose
        pose = .intro
        motionTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.18)) { pose = accent }
            try? await Task.sleep(nanoseconds: 190_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) { pose = .rest }
        }
    }

    private func stopMotion() {
        motionTask?.cancel()
        motionTask = nil
        pose = .rest
    }
}
