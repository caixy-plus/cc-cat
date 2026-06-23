import Foundation

enum AdministratorExecutorError: LocalizedError {
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let message):
            return message.isEmpty ? "管理员授权失败或已取消" : message
        }
    }
}

actor AdministratorExecutor {
    func run(commands: [String]) throws {
        guard !commands.isEmpty else { return }
        let shellCommand = "set -e; " + commands.joined(separator: "; ")
        let script = "do shell script \"\(appleScriptEscaped(shellCommand))\" with administrator privileges"

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw AdministratorExecutorError.authorizationFailed(String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

