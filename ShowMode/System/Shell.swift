import Foundation

enum Shell {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Result {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    /// Exécute une commande et attend sa fin. Passé le délai, le processus est arrêté.
    @discardableResult
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> Result {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        // Lecture en parallèle : une sortie volumineuse ne doit pas bloquer le processus.
        let reader = DispatchGroup()
        var data = Data()
        reader.enter()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            reader.leave()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            finished.wait()
            reader.wait()
            let command = "\(path) \(arguments.joined(separator: " "))"
            throw Failure(message: String(localized: "Délai dépassé : \(command)"))
        }
        reader.wait()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
