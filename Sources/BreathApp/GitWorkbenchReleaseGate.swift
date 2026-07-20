import Foundation

enum GitWorkbenchReleaseGate {
    static var isEnabled: Bool {
#if DEBUG
        true
#else
        ProcessInfo.processInfo.environment[
            "BREATH_ENABLE_GIT_WORKBENCH"
        ] == "1"
#endif
    }
}
