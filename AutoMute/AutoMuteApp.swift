import AppKit

@main
struct AutoMuteApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        exit(delegate.exitCode)
    }
}
