import Foundation
import Network

/// Live coin prices over a market-data WebSocket (Gemini, or Binance in the private build), AC power only
/// and only while a coin is chosen. Off AC the engine's CoinGecko poll supplies prices, so nothing runs here.
actor WebSocketManager {
    /// One session for the life of the actor (the previous code created one per reconnect and
    /// never invalidated them).
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<PriceUpdate>.Continuation?
    private var reconnectDelay: TimeInterval = 1.0
    private var consecutiveFailures = 0
    private var isRunning = false
    private var isThrottled = false
    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable = true
    private var reconnectTask: Task<Void, Never>?
    private var lifetimeTask: Task<Void, Never>?
    private var wsActivity: NSObjectProtocol?

    /// What to stream; nil = no coin chosen, the socket stays shut.
    private var spec: (any CryptoStreamSpec)?

    // MARK: - Public API

    /// Starts the stream. Does not connect; call `connectIfAppropriate()` once the power tier is known.
    func start() -> AsyncStream<PriceUpdate> {
        let (stream, continuation) = AsyncStream<PriceUpdate>.makeStream()
        self.continuation = continuation
        isRunning = true
        startNetworkMonitor()
        return stream
    }

    /// Points the stream at the chosen coins and provider. The same stream again changes nothing; a new one
    /// reconnects; nil disconnects and stays off.
    func configure(_ newSpec: (any CryptoStreamSpec)?) async {
        let same = spec?.url == newSpec?.url && spec?.subscribeMessage == newSpec?.subscribeMessage
        guard !same else { return }
        spec = newSpec
        disconnect()
        if newSpec != nil { await connectIfAppropriate() }
    }

    func stop() {
        isRunning = false
        disconnect()
        stopNetworkMonitor()
        continuation?.finish()
        continuation = nil
    }

    /// AC: connect (holding an activity assertion so App Nap does not sever the socket).
    /// Battery/critical: disconnect and stay quiet; prices come from the engine's polls.
    func connectIfAppropriate() async {
        guard isRunning, spec != nil else { return }
        let tier = await MainActor.run { PowerMonitor.shared.tier }
        if tier == .ac {
            isThrottled = false
            if wsActivity == nil {
                wsActivity = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: "Live crypto price WebSocket")
            }
            if task == nil { connect() }
        } else {
            guard !isThrottled else { return }
            isThrottled = true
            print("PulseFeed: [WS] \(tier) — WebSocket off, prices via CoinGecko poll")
            disconnect()
        }
    }

    func handleSleep() {
        disconnect(keepActivity: true)
    }

    func handleWake() {
        guard isRunning, !isThrottled else { return }
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self.isRunning, !self.isThrottled else { return }
            self.connect()
        }
    }

    // MARK: - Connection

    private func connect() {
        guard isRunning, isNetworkAvailable, !isThrottled, task == nil, let spec else { return }
        let task = session.webSocketTask(with: spec.url)
        self.task = task
        task.resume()
        if let subscribe = spec.subscribeMessage {
            task.send(.string(subscribe)) { error in
                if let error { print("PulseFeed: [WS] subscribe failed: \(error.localizedDescription)") }
            }
        }
        receiveLoop(task: task)
        scheduleLifetimeReconnect()
        print("PulseFeed: [WS] connecting to \(spec.name)")
    }

    /// Ends the socket and every pending timer. `keepActivity` leaves the App Nap assertion in
    /// place across sleep so the wake reconnect is not napped.
    private func disconnect(keepActivity: Bool = false) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        lifetimeTask?.cancel()
        lifetimeTask = nil
        if !keepActivity, let activity = wsActivity {
            ProcessInfo.processInfo.endActivity(activity)
            wsActivity = nil
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            Task {
                switch result {
                case .success(let message):
                    await self.handleMessage(message, from: task)
                    await self.receiveLoop(task: task)
                case .failure(let error):
                    await self.handleDisconnect(task: task, error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message, from task: URLSessionWebSocketTask) {
        guard task === self.task else { return }
        if consecutiveFailures > 0 || reconnectDelay > 1.0 {
            consecutiveFailures = 0
            reconnectDelay = 1.0
        }
        let text: String
        switch message {
        case .string(let str): text = str
        case .data(let data):
            guard let str = String(data: data, encoding: .utf8) else { return }
            text = str
        @unknown default: return
        }
        for update in spec?.parse(text) ?? [] { continuation?.yield(update) }
    }

    private func handleDisconnect(task: URLSessionWebSocketTask, error: Error) {
        guard task === self.task else { return }  // stale socket, already replaced
        self.task = nil
        lifetimeTask?.cancel()
        lifetimeTask = nil
        guard isRunning, isNetworkAvailable, !isThrottled else { return }

        consecutiveFailures += 1
        // 1, 2, 4 ... 30 s, then 5 minutes once it is clearly not coming back.
        let delay = consecutiveFailures > 8 ? 300.0 : min(reconnectDelay, 30.0)
        let jitter = Double.random(in: 0...delay * 0.1)
        reconnectDelay *= 2
        if consecutiveFailures == 1 || consecutiveFailures % 10 == 0 {
            print("PulseFeed: [WS] disconnected (\(error.localizedDescription)); retry in \(Int(delay))s, failures=\(consecutiveFailures)")
        }
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay + jitter))
            guard !Task.isCancelled else { return }
            self.connect()
        }
    }

    /// Binance closes connections after 24 hours; reconnect proactively at 23.5 (harmless for Gemini).
    private func scheduleLifetimeReconnect() {
        lifetimeTask?.cancel()
        lifetimeTask = Task {
            try? await Task.sleep(for: .seconds(23.5 * 3600))
            guard !Task.isCancelled, self.isRunning, !self.isThrottled else { return }
            self.disconnect(keepActivity: true)
            self.connect()
        }
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        self.networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { await self.handleNetworkChange(isAvailable: path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.pulsefeed.network"))
    }

    private func stopNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    private func handleNetworkChange(isAvailable: Bool) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = isAvailable
        if isAvailable && !wasAvailable && isRunning && !isThrottled {
            consecutiveFailures = 0
            reconnectDelay = 1.0
            connect()
        } else if !isAvailable {
            disconnect(keepActivity: true)
        }
    }
}
