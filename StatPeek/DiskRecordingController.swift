import AppKit

@MainActor
final class DiskRecordingController: NSObject {
    let recorder: DiskHistoryRecorder
    var onChange: ((String?) -> Void)?
    private(set) var errorMessage: String?
    private var timer: Timer?

    init(store: DiskHistoryStore) throws {
        recorder = try DiskHistoryRecorder(store: store)
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(recordIfDue),
                                                         name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func recordIfDue() {
        do {
            if try recorder.recordIfDue(at: Date(), read: DiskSpaceReader.read) {
                errorMessage = nil
                onChange?(nil)
            }
        } catch {
            errorMessage = error.localizedDescription
            onChange?(errorMessage)
        }
        timer?.invalidate()
        let next = recorder.nextRecordingDate ?? Date().addingTimeInterval(DiskHistoryRecorder.interval)
        let scheduled = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordIfDue() }
        }
        scheduled.tolerance = 1
        RunLoop.main.add(scheduled, forMode: .common)
        RunLoop.main.add(scheduled, forMode: .eventTracking)
        timer = scheduled
    }
}
