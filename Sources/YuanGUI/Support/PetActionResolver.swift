import Foundation

struct PetActionContext {
    let mode: PetMode
    let taskState: PetStore.TaskState
    let actionIndex: Int
    let isChatting: Bool
    let isFocusActive: Bool
    let isFocusCelebrating: Bool
    let isMusicPlaying: Bool
    let petMotionEnabled: Bool
    let ambientMessageVisible: Bool
    let smartReactionsEnabled: Bool
    let smartActionSuppressed: Bool
    let smartState: SmartPetState
    let transientSmartState: SmartPetState?
}

enum PetActionResolver {
    static func resolve(_ context: PetActionContext) -> PetAction {
        if context.isFocusCelebrating {
            return PetAction(file: "19-maintenance-success", label: "专注完成，好耶！")
        }
        switch context.taskState {
        case .maintenance:
            return PetAction(file: "18-maintenance-scan", label: "正在扫描")
        case .maintenanceSuccess:
            return PetAction(file: "19-maintenance-success", label: "清理完成")
        case .recycling(let frame):
            return PetAction(
                file: "15-eat-trash-\(min(max(frame, 1), 3))",
                label: "把文件吃掉啦"
            )
        case .idle:
            break
        }
        if context.isChatting { return context.mode.chatAction }
        if context.smartReactionsEnabled,
           context.smartState.isUrgent,
           let action = context.mode.smartAction(for: context.smartState) {
            return action
        }
        if context.isFocusActive { return context.mode.actions[0] }
        if context.smartReactionsEnabled,
           !context.smartActionSuppressed,
           let state = context.transientSmartState,
           let action = context.mode.smartAction(for: state) {
            return action
        }
        if context.isMusicPlaying { return context.mode.musicAction }
        if context.ambientMessageVisible, context.petMotionEnabled {
            return context.mode.chatAction
        }
        let actions = context.mode.actions
        return actions[min(max(context.actionIndex, 0), actions.count - 1)]
    }
}
