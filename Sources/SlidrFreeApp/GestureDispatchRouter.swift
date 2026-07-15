import SlidrFreeCore

/// The single action boundary for both normal input and safe previews.
/// Keeping the preview gate here prevents a new gesture type from bypassing
/// test mode and accidentally reaching a system action emitter.
struct GestureDispatchRouter {
    let preview: GestureTestController

    func actions(for gesture: RecognizedGesture, settings: AppSettings) -> [SystemAction] {
        guard !preview.intercept(gesture) else { return [] }
        return ActionDispatcher(settings: settings).actions(for: gesture)
    }
}
