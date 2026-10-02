import Foundation
import Darwin

extension Process {
    func gracefulTerminate(timeout: TimeInterval = 3.0, completion: (() -> Void)? = nil) {
        guard isRunning else {
            completion?()
            return
        }
        let pid = processIdentifier
        terminate()
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if kill(pid, 0) != 0 {
                    DispatchQueue.main.async { completion?() }
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
            DispatchQueue.main.async { completion?() }
        }
    }
}
