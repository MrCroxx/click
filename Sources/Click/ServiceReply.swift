import Foundation
import ClickCore

/// XPC can fail, reply late, or never reply. Complete the caller exactly once.
final class ServiceReply: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Result<Void, Error>) -> Void)?
    init(timeout: TimeInterval = 6, completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
            self.finish(.failure(ClickError("Keyboard Service did not respond. Turn it off and on in Settings, then retry.")))
        }
    }
    func finish(_ result: Result<Void, Error>) {
        lock.lock(); let callback = completion; completion = nil; lock.unlock()
        callback?(result)
    }
}
