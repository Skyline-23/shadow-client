import Darwin
import Foundation
import ShadowClientFeatureHome

actor ShadowClientmacOSMoonlightSessionConnectionClient: ShadowClientRemoteSessionConnectionClient {
    let presentationMode: ShadowClientRemoteSessionPresentationMode = .externalRuntime

    private var activeProcess: Process?
    private static let startupProbeDelay: Duration = .milliseconds(350)

    func connect(to sessionURL: String, host: String, appTitle: String) async throws {
        await disconnect()

        guard let executable = Self.resolveExecutable() else {
            throw ShadowClientGameStreamError.requestFailed(
                "Moonlight runtime not found. Install Moonlight.app or set SHADOW_CLIENT_MOONLIGHT_BIN."
            )
        }

        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackHost = Self.hostFromSessionURL(sessionURL) ?? normalizedHost
        let targetHost = normalizedHost.isEmpty ? fallbackHost : normalizedHost
        guard !targetHost.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed(
                "Moonlight launch failed because the target host is empty."
            )
        }

        let targetApp = appTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Desktop"
            : appTitle

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "stream",
            targetHost,
            targetApp,
            "--display-mode",
            "windowed",
            "--absolute-mouse",
            "--capture-system-keys",
            "never",
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] terminatedProcess in
            Task {
                await self?.clearActiveProcess(ifSameAs: terminatedProcess)
            }
        }

        do {
            try process.run()
        } catch {
            throw ShadowClientGameStreamError.requestFailed(error.localizedDescription)
        }

        activeProcess = process

        try await verifyStartup(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
    }

    func disconnect() async {
        guard let process = activeProcess else {
            return
        }
        activeProcess = nil

        if process.isRunning {
            process.terminate()
            let didTerminateGracefully = await waitForExit(
                of: process,
                timeout: .milliseconds(800)
            )

            if !didTerminateGracefully, process.isRunning {
                Self.forceTerminate(process)
                _ = await waitForExit(of: process, timeout: .milliseconds(250))
            }
        }
    }

    private static func resolveExecutable() -> String? {
        let appBinary = "/Applications/Moonlight.app/Contents/MacOS/moonlight"
        if FileManager.default.isExecutableFile(atPath: appBinary) {
            return appBinary
        }

        if let explicit = ProcessInfo.processInfo.environment["SHADOW_CLIENT_MOONLIGHT_BIN"] {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
                return trimmed
            }
        }

        return nil
    }

    private static func hostFromSessionURL(_ sessionURL: String) -> String? {
        let trimmed = sessionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate = trimmed.contains("://") ? trimmed : "rtsp://\(trimmed)"
        guard let parsed = URL(string: candidate),
              let host = parsed.host,
              !host.isEmpty
        else {
            return nil
        }

        return host
    }

    private func clearActiveProcess(ifSameAs process: Process) {
        guard let activeProcess, activeProcess === process else {
            return
        }
        self.activeProcess = nil
    }

    private func verifyStartup(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) async throws {
        try? await Task.sleep(for: Self.startupProbeDelay)
        guard !Task.isCancelled else {
            return
        }

        guard process.isRunning else {
            let stderr = Self.readPipeOutput(stderrPipe)
            let stdout = Self.readPipeOutput(stdoutPipe)
            let details = Self.summarizeLaunchFailure(
                stderr: stderr,
                stdout: stdout,
                exitCode: process.terminationStatus
            )

            if let activeProcess, activeProcess === process {
                self.activeProcess = nil
            }
            throw ShadowClientGameStreamError.requestFailed(details)
        }
    }

    private func waitForExit(
        of process: Process,
        timeout: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while process.isRunning {
            if clock.now >= deadline {
                return false
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return true
    }

    private static func forceTerminate(_ process: Process) {
        let pid = process.processIdentifier
        guard pid > 0 else {
            return
        }

        _ = kill(pid, SIGKILL)
    }

    private static func readPipeOutput(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            return ""
        }

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func summarizeLaunchFailure(
        stderr: String,
        stdout: String,
        exitCode: Int32
    ) -> String {
        if !stderr.isEmpty {
            return "Moonlight stream exited early (\(exitCode)): \(stderr)"
        }

        if !stdout.isEmpty {
            return "Moonlight stream exited early (\(exitCode)): \(stdout)"
        }

        return "Moonlight stream exited before session startup (exit code \(exitCode))."
    }
}
