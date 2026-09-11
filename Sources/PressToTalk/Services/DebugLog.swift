import Foundation

/// Appends a line to the file named by TALKKEY_DEBUG_LOG, when set. Lets a
/// build launched through LaunchServices (no stdout) report what it did.
enum DebugLog {
    static let path = ProcessInfo.processInfo.environment["TALKKEY_DEBUG_LOG"]

    static func append(_ line: String) {
        print(line)
        guard let path else { return }
        let data = (line + "\n").data(using: .utf8)!
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
