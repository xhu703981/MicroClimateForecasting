import Foundation
import Combine

// MARK: - Session State

enum SessionState {
    case idle
    case creating
    case active(sessionId: String)
    case ending
    case error(String)
}

// MARK: - SessionManager

final class SessionManager: ObservableObject {

    static let shared = SessionManager()

    @Published var state: SessionState = .idle
    @Published var currentSession: ExperimentSessionOut?
    @Published var uploadCount: Int = 0
    @Published var lastUploadTime: Date?

    // Form fields (bound to UI)
    @Published var subjectId: String = ""
    @Published var bodySite: String = ""
    @Published var conditionLabel: String = ""
    @Published var note: String = ""

    var isSessionActive: Bool {
        if case .active = state { return true }
        return false
    }

    var currentSessionId: String? {
        if case .active(let id) = state { return id }
        return nil
    }

    private init() {}

    // MARK: - Session Lifecycle

    func startSession(completion: @escaping (Bool) -> Void) {
        state = .creating

        SensorAPIClient.shared.createExperimentSession(
            subjectId: subjectId.isEmpty ? nil : subjectId,
            bodySite: bodySite.isEmpty ? nil : bodySite,
            conditionLabel: conditionLabel.isEmpty ? nil : conditionLabel,
            note: note.isEmpty ? nil : note
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let session):
                    self.currentSession = session
                    self.state = .active(sessionId: session.session_id)
                    self.uploadCount = 0
                    self.lastUploadTime = nil
                    print("[Session] Started: \(session.session_id)")
                    completion(true)
                case .failure(let err):
                    self.state = .error(err.localizedDescription)
                    completion(false)
                }
            }
        }
    }

    func endSession() {
        guard let id = currentSessionId else { return }
        state = .ending
        SensorAPIClient.shared.endExperimentSession(sessionId: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.currentSession = nil
            self?.state = .idle
            print("[Session] Ended: \(id)")
        }
    }

    // MARK: - Data Ingestion (called from BLEManager)

    func ingestReading(tempC: Double, humPct: Double, presHpa: Double) {
        guard let sessionId = currentSessionId else {
            print("[Session] No active session — reading dropped")
            return
        }
        SensorAPIClient.shared.sendSensorReading(
            sessionId: sessionId,
            tempC: tempC,
            humPct: humPct,
            presHpa: presHpa
        )
        DispatchQueue.main.async { [weak self] in
            self?.uploadCount += 1
            self?.lastUploadTime = Date()
        }
    }
}

// MARK: - Body Site Options (for picker)

extension SessionManager {
    static let bodySiteOptions = [
        "Forearm", "Hand (dorsal)", "Hand (palmar)", "Wrist",
        "Upper arm", "Chest", "Back", "Forehead", "Other"
    ]
    static let conditionOptions = [
        "Rest", "Exercise", "Post-exercise", "Heat stress",
        "Occlusion", "Baseline", "Other"
    ]
}
