import Foundation

/// Turns a raw exchange into a redacted transaction. Secrets stop here.
struct TransactionBuilder: Sendable {
    let processor: BodyProcessor
    let redactor: Redactor

    /// `eventStream` is what has been parsed of an event stream's response so far.
    func transaction(from exchange: RawExchange, eventStream: CapturedEventStream? = nil) -> HTTPTransaction {
        let response = exchange.response as? HTTPURLResponse
        return HTTPTransaction(
            id: exchange.id,
            request: request(from: exchange),
            response: response.map { self.response(from: $0, in: exchange) },
            failure: exchange.error.map(failure),
            timing: exchange.metrics?.timing,
            connection: exchange.metrics?.connection,
            size: exchange.metrics?.size,
            eventStream: eventStream
        )
    }

    private func request(from exchange: RawExchange) -> CapturedRequest {
        let request = exchange.request
        let url = redactor.redact(url: request.url)
        let fields = request.allHTTPHeaderFields ?? [:]
        let method = request.httpMethod ?? "GET"
        let context = BodyContext(
            url: url,
            method: method,
            contentType: fields.first { $0.key.lowercased() == "content-type" }?.value,
            direction: .request
        )
        let encoding = fields.first { $0.key.lowercased() == "content-encoding" }?.value
        return CapturedRequest(
            url: url,
            method: method,
            headers: redactor.redact(headers: fields),
            queryParameters: redactor.queryParameters(of: url),
            body: requestBody(of: exchange, context: context, encoding: encoding),
            startDate: exchange.startDate
        )
    }

    private func requestBody(of exchange: RawExchange, context: BodyContext, encoding: String?) -> CapturedBody? {
        guard let raw = exchange.requestBody else {
            let byteCount = Int(exchange.metrics?.requestBodyBytes ?? 0)
            return byteCount > 0
                ? CapturedBody(content: .notStored, byteCount: byteCount, contentType: context.contentType) : nil
        }
        return processor.process(
            raw,
            context: context,
            declared: Decompressor.compression(fromContentEncoding: encoding)
        )
    }

    private func response(from response: HTTPURLResponse, in exchange: RawExchange) -> CapturedResponse {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let name = field.key as? String {
                result[name] = String(describing: field.value)
            }
        }
        let context = BodyContext(
            url: redactor.redact(url: exchange.request.url),
            method: exchange.request.httpMethod ?? "GET",
            contentType: response.mimeType,
            direction: .response
        )
        let body: CapturedBody?
        if exchange.isEventStream {
            // The parsed events are what's stored, so the bytes aren't kept a second time.
            body = nil
        } else if let raw = exchange.responseBody {
            body = processor.process(raw, context: context)
        } else {
            let byteCount = Int(exchange.metrics?.size.decodedBodyBytes ?? 0)
            body = CapturedBody(content: .notStored, byteCount: byteCount, contentType: response.mimeType)
        }
        return CapturedResponse(
            statusCode: response.statusCode,
            headers: redactor.redact(headers: fields),
            body: body,
            mimeType: response.mimeType,
            contentEncoding: response.value(forHTTPHeaderField: "Content-Encoding"),
            endDate: exchange.endDate
        )
    }

    private func failure(from error: any Error) -> CapturedFailure {
        let error = error as NSError
        return CapturedFailure(domain: error.domain, code: error.code, description: error.localizedDescription)
    }
}
