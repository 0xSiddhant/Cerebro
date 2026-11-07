import Foundation

/// Turns a raw exchange into a redacted transaction. Secrets stop here.
struct TransactionBuilder: Sendable {
    let processor: BodyProcessor
    let redactor: Redactor

    func transaction(from exchange: RawExchange) -> HTTPTransaction {
        let response = exchange.response as? HTTPURLResponse
        return HTTPTransaction(
            id: exchange.id,
            request: request(from: exchange),
            response: response.map { self.response(from: $0, in: exchange) },
            failure: exchange.error.map(failure),
            timing: exchange.metrics?.timing,
            connection: exchange.metrics?.connection,
            size: exchange.metrics?.size
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
            body: processor.process(
                exchange.requestBody,
                context: context,
                declared: Decompressor.compression(fromContentEncoding: encoding)
            ),
            startDate: exchange.startDate
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
        return CapturedResponse(
            statusCode: response.statusCode,
            headers: redactor.redact(headers: fields),
            body: exchange.responseBody.map { processor.process($0, context: context) }
                ?? notStoredBody(byteCount: exchange.metrics?.size.decodedBodyBytes, contentType: response.mimeType),
            mimeType: response.mimeType,
            contentEncoding: response.value(forHTTPHeaderField: "Content-Encoding"),
            endDate: exchange.endDate
        )
    }

    /// Download task bodies are never stored, so only their size is known.
    private func notStoredBody(byteCount: Int64?, contentType: String?) -> CapturedBody {
        CapturedBody(content: .notStored, byteCount: Int(byteCount ?? 0), contentType: contentType)
    }

    private func failure(from error: any Error) -> CapturedFailure {
        let error = error as NSError
        return CapturedFailure(domain: error.domain, code: error.code, description: error.localizedDescription)
    }
}
