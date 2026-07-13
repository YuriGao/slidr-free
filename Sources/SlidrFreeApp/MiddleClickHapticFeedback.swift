import AppKit

protocol MiddleClickHapticFeedbackPerforming: AnyObject {
    func performSuccess()
}

final class AppKitMiddleClickHapticFeedback: MiddleClickHapticFeedbackPerforming {
    private let isEnabled: () -> Bool
    private let deliverOnMain: (@escaping () -> Void) -> Void
    private let perform: () -> Void

    init(
        isEnabled: @escaping () -> Bool,
        deliverOnMain: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        },
        perform: @escaping () -> Void = {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .generic,
                performanceTime: .now
            )
        }
    ) {
        self.isEnabled = isEnabled
        self.deliverOnMain = deliverOnMain
        self.perform = perform
    }

    func performSuccess() {
        deliverOnMain { [isEnabled, perform] in
            guard isEnabled() else { return }
            perform()
        }
    }
}
