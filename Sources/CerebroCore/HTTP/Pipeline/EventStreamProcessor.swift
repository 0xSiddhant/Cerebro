import Foundation

/// Applies event-stream activity to the store in the order it arrived. One task owns it, so a stream
/// can't finish before its last event is applied.
///
/// A busy stream reaches the store at most once per update interval: the first new event publishes at
/// once and asks for a flush, and whatever arrives before that flush waits for it. A quiet stream
/// schedules nothing.
struct EventStreamProcessor {
    private struct OpenStream {
        let opening: HTTPTransaction
        var assembler: EventStreamAssembler
        var hasUnpublishedChanges = false
        var isFlushScheduled = false
    }

    private let builder: TransactionBuilder
    private let store: TransactionStore
    private let console: ConsoleLogger

    /// Sends a `.flush` for a stream back through the same queue, after the update interval.
    private let scheduleFlush: @Sendable (UUID) -> Void
    private var streams: [UUID: OpenStream] = [:]

    init(
        builder: TransactionBuilder,
        store: TransactionStore,
        console: ConsoleLogger,
        scheduleFlush: @escaping @Sendable (UUID) -> Void
    ) {
        self.builder = builder
        self.store = store
        self.console = console
        self.scheduleFlush = scheduleFlush
    }

    mutating func handle(_ activity: RawStreamActivity) async {
        let id = activity.id
        switch activity.content {
        case .opened(let exchange):
            let assembler = EventStreamAssembler(
                processor: builder.processor,
                url: builder.redactor.redact(url: exchange.request.url),
                method: exchange.request.httpMethod ?? "GET",
                openedAt: activity.date
            )
            let opening = builder.transaction(from: exchange, eventStream: assembler.stream(.open))
            streams[id] = OpenStream(opening: opening, assembler: assembler)
            await store.append(opening)
        case .chunk(let data, let backlog):
            let didChange = streams[id]?.assembler.receive(data, at: activity.date) ?? false
            backlog.finish(bytes: data.count)
            if didChange {
                await noteChange(to: id)
            }
        case .overflowed:
            streams[id]?.assembler.loseFraming()
            await noteChange(to: id)
        case .flush:
            streams[id]?.isFlushScheduled = false
            if streams[id]?.hasUnpublishedChanges == true {
                await publish(id)
            }
        case .finished(let exchange):
            guard let stream = streams.removeValue(forKey: id) else { return }
            let finished = builder.transaction(from: exchange, eventStream: stream.assembler.stream(.completed))
            // Logged once, here, so a live stream never prints over and over.
            if await store.update(finished) {
                console.log(finished)
            }
        }
    }

    private mutating func noteChange(to id: UUID) async {
        guard let stream = streams[id] else { return }
        if stream.isFlushScheduled {
            streams[id]?.hasUnpublishedChanges = true
        } else {
            await publish(id)
        }
    }

    private mutating func publish(_ id: UUID) async {
        guard let stream = streams[id] else { return }
        streams[id]?.hasUnpublishedChanges = false
        streams[id]?.isFlushScheduled = true
        scheduleFlush(id)
        let updated = stream.opening.updating(
            eventStream: stream.assembler.stream(.open),
            lastReceived: stream.assembler.lastReceived
        )
        // The store dropped the request to make room, so there's nothing left to keep up to date.
        if await !store.update(updated) {
            streams[id] = nil
        }
    }
}

extension HTTPTransaction {
    fileprivate func updating(eventStream: CapturedEventStream, lastReceived: Date) -> HTTPTransaction {
        HTTPTransaction(
            id: id,
            request: request,
            response: response.map {
                CapturedResponse(
                    statusCode: $0.statusCode,
                    headers: $0.headers,
                    body: $0.body,
                    mimeType: $0.mimeType,
                    contentEncoding: $0.contentEncoding,
                    endDate: lastReceived
                )
            },
            failure: failure,
            timing: timing,
            connection: connection,
            size: size,
            eventStream: eventStream
        )
    }
}
