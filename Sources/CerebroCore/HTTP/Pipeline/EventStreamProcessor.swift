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

        func transaction(_ state: CapturedEventStream.State) -> HTTPTransaction {
            opening.updating(eventStream: assembler.stream(state), lastReceived: assembler.lastReceived)
        }
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
            await finish(id, with: exchange)
        }
    }

    private mutating func finish(_ id: UUID, with exchange: RawExchange) async {
        guard var stream = streams.removeValue(forKey: id) else { return }
        var finished = builder.transaction(from: exchange, eventStream: stream.assembler.stream(.completed))
        var result = await store.update(finished)
        if case .cleared(let date) = result {
            stream.assembler.forgetEvents(before: date)
            // A stream that ends with nothing new since the clear has nothing to show.
            guard stream.assembler.hasEvents else { return }
            finished = builder.transaction(from: exchange, eventStream: stream.assembler.stream(.completed))
            await store.append(finished)
            result = .updated
        }
        // Logged once, here, so a live stream never prints over and over.
        if result == .updated {
            console.log(finished)
        }
    }

    /// Capture stopped, so no stream's end can arrive any more. Each one still open is closed with what
    /// it has, or it would read as live for good and never be saved.
    mutating func finishAll() async {
        for (id, stream) in streams {
            await store.update(stream.transaction(.completed))
            streams[id] = nil
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
        switch await store.update(stream.transaction(.open)) {
        case .updated:
            break
        case .evicted:
            // The store dropped the request to make room, so there's nothing left to keep up to date.
            streams[id] = nil
        case .cleared(let date):
            // The list was cleared, and the stream is still running, so it comes back with only what
            // has arrived since.
            streams[id]?.assembler.forgetEvents(before: date)
            if let restarted = streams[id]?.transaction(.open) {
                await store.append(restarted)
            }
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
