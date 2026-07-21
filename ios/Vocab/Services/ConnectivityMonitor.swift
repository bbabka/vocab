import Foundation
import Network

/// One shared `NWPathMonitor` (Reader instantiates one per store; Vocab only
/// needs a single reconnect signal to trigger an outbox drain, so it's
/// consolidated here). Fires `onReconnect` on the transition from
/// unreachable → reachable, not on every path update.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.jakubsvehla.vocab.connectivity")
    private var onReconnect: (@Sendable () -> Void)?
    private var started = false

    func start(onReconnect: @escaping @Sendable () -> Void) {
        guard !started else { return }
        started = true
        self.onReconnect = onReconnect

        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = reachable
                if !wasConnected && reachable {
                    self.onReconnect?()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
