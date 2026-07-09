import SwiftUI
import SwiftData
import OSLog

@MainActor
@Observable
final class DailyLogViewModel {
    private static let log = Logger(subsystem: "com.carpecadence", category: "DailyLog")
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

    // notifications defaults to nil and is resolved to the shared service inside
    // this @MainActor body — referencing the @MainActor singleton in a default
    // argument would be evaluated in a nonisolated context (Swift 6 error).
    @discardableResult
    func save(log: DailyLog, context: any ModelPersisting, notifications: (any NotificationServiceProtocol)? = nil) -> Bool {
        let notifications = notifications ?? NotificationService.shared
        let wasComplete = log.isComplete
        log.isComplete = true
        do {
            try context.save()
        } catch {
            log.isComplete = wasComplete
            Self.log.error("Failed to save daily log: \(error.localizedDescription)")
            saveError = String(localized: "Your log couldn't be saved. Please try again.")
            return false
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        notifications.removeNotification(id: NotificationID.streakRisk)
        return true
    }
}

enum LogStep: Int, CaseIterable {
    case mood = 0
    case bodyMetrics
    case basics
    case symptoms
    case factors
    case peaksAndValleys
    case intentions
    case note
    case done

    var isMetricStep: Bool { self == .bodyMetrics }

    var title: String {
        switch self {
        case .mood:           return "Overall Mood"
        case .bodyMetrics:    return "Body Metrics"
        case .basics:         return "Basics Done Today"
        case .symptoms:       return "Symptoms"
        case .factors:        return "Possible Triggers"
        case .peaksAndValleys: return "Peaks & Valleys"
        case .intentions:     return "Intentions for Tomorrow"
        case .note:           return "One-Line Note"
        case .done:           return "All done!"
        }
    }

    var icon: String {
        switch self {
        case .mood:           return "face.smiling"
        case .bodyMetrics:    return "waveform.path.ecg"
        case .basics:         return "checklist"
        case .symptoms:       return "bandage"
        case .factors:        return "exclamationmark.triangle"
        case .peaksAndValleys: return "arrow.up.arrow.down.circle"
        case .intentions:     return "sunrise.fill"
        case .note:           return "pencil.line"
        case .done:           return "checkmark.circle.fill"
        }
    }
}
