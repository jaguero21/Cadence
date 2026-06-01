import SwiftUI
import SwiftData

@MainActor
@Observable
final class DailyLogViewModel {
    var currentStep: LogStep = .mood
    var isDone: Bool = false
    var saveError: String?

    func nextStep() {
        withAnimation(CadenceAnimation.spring) {
            if let next = LogStep(rawValue: currentStep.rawValue + 1) {
                currentStep = next
            } else {
                isDone = true
            }
        }
    }

    func previousStep() {
        withAnimation(CadenceAnimation.spring) {
            if let prev = LogStep(rawValue: currentStep.rawValue - 1) {
                currentStep = prev
            }
        }
    }

    @discardableResult
    func save(log: DailyLog, context: ModelContext) -> Bool {
        do {
            try context.save()
        } catch {
            saveError = "Your log couldn't be saved. Please try again."
            return false
        }
        log.isComplete = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationService.shared.removeNotification(id: NotificationID.streakRisk)
        return true
    }
}

enum LogStep: Int, CaseIterable {
    case mood = 0
    case bodyMetrics
    case basics
    case note
    case done

    var isMetricStep: Bool { self == .bodyMetrics }

    var title: String {
        switch self {
        case .mood:        return "Overall Mood"
        case .bodyMetrics: return "Body Metrics"
        case .basics:      return "Basics Done Today"
        case .note:        return "One-Line Note"
        case .done:        return "All done!"
        }
    }

    var icon: String {
        switch self {
        case .mood:        return "face.smiling"
        case .bodyMetrics: return "waveform.path.ecg"
        case .basics:      return "checklist"
        case .note:        return "pencil.line"
        case .done:        return "checkmark.circle.fill"
        }
    }
}
