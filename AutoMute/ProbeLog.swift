import OSLog

enum ProbeLog {
    static let lifecycle = Logger(subsystem: "local.AutoMute", category: "lifecycle")
    static let devices = Logger(subsystem: "local.AutoMute", category: "devices")
    static let mute = Logger(subsystem: "local.AutoMute", category: "mute")
}
