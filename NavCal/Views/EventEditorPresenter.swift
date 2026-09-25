import EventKit
import EventKitUI
import UIKit

/// Presents the system `EKEventEditViewController` for creating or editing an event.
///
/// The controller is presented with UIKit from the front-most view controller, the
/// presentation EventKitUI is designed for. It saves the event itself; `onComplete` reports
/// whether it was saved, deleted or canceled so the caller can refresh.
///
/// The editor cancels itself immediately when the device has no writable calendar, so callers
/// should check `EKEventStore.writableEventCalendars` first.
@MainActor
final class EventEditorPresenter: NSObject, EKEventEditViewDelegate, UIAdaptivePresentationControllerDelegate {
    private var onComplete: ((EKEventEditViewAction) -> Void)?
    private weak var controller: EKEventEditViewController?

    /// True while the editor is on screen.
    var isPresenting: Bool { controller != nil }

    /// Shows the editor for a new event on `day`. Ignored if one is already showing.
    func present(store: EKEventStore, day: Date, onComplete: @escaping (EKEventEditViewAction) -> Void) {
        present(store: store, event: Self.draftEvent(in: store, on: day), onComplete: onComplete)
    }

    /// Shows the editor for an existing `event`, which can also be deleted from there.
    /// Ignored if one is already showing.
    func present(store: EKEventStore, event: EKEvent, onComplete: @escaping (EKEventEditViewAction) -> Void) {
        guard !isPresenting else { return }
        guard let presenter = Self.frontMostViewController() else {
            onComplete(.canceled)
            return
        }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = self

        self.controller = controller
        self.onComplete = onComplete

        presenter.present(controller, animated: true) { [weak self, weak controller] in
            // Hear about swipe-to-dismiss, which doesn't go through the edit delegate.
            controller?.presentationController?.delegate = self
        }
    }

    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        MainActor.assumeIsolated {
            self.controller = nil
            onComplete = nil
        }
    }

    /// A one-hour event in the user's default calendar: at the next full hour when `day` is
    /// today, otherwise at 9 AM on `day`.
    nonisolated static func draftEvent(in store: EKEventStore, on day: Date, now: Date = .now) -> EKEvent {
        let event = EKEvent(eventStore: store)
        let calendar = Calendar.current
        let start = if calendar.isDate(day, inSameDayAs: now) {
            calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        } else {
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        event.startDate = start
        event.endDate = start.addingTimeInterval(60 * 60)
        event.calendar = store.calendarForNewEvents
        return event
    }

    // MARK: - EKEventEditViewDelegate

    nonisolated func eventEditViewController(
        _ controller: EKEventEditViewController,
        didCompleteWith action: EKEventEditViewAction
    ) {
        MainActor.assumeIsolated {
            let completion = onComplete
            self.controller = nil
            onComplete = nil
            controller.dismiss(animated: true) {
                completion?(action)
            }
        }
    }

    // MARK: - Helpers

    private static func frontMostViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
