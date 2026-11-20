import Foundation
import Darwin

extension Process {
    func gracefulTerminate(timeout: TimeInterval = 3.0) {
        guard isRunning else { return }
        let pid = processIdentifier
        terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            if self?.isRunning == true {
                kill(pid, SIGKILL)
            }
        }
    }
}
