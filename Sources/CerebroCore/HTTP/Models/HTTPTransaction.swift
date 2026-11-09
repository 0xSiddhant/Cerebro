import Foundation

/// One finished request, already redacted.
public struct HTTPTransaction: Sendable, Identifiable, Equatable {
    /// Identifies this transaction.
    public let id: UUID

    /// What the app sent.
    public let request: CapturedRequest

    /// What came back, if anything did.
    public let response: CapturedResponse?

    /// Why the request didn't finish, if it didn't.
    public let failure: CapturedFailure?

    /// How long each stage took.
    public let timing: TransactionTiming?

    /// Which connection carried the request.
    public let connection: ConnectionDetails?

    /// How many bytes moved.
    public let size: TransferSize?

    /// Creates a transaction.
    public init(
        id: UUID = UUID(),
        request: CapturedRequest,
        response: CapturedResponse? = nil,
        failure: CapturedFailure? = nil,
        timing: TransactionTiming? = nil,
        connection: ConnectionDetails? = nil,
        size: TransferSize? = nil
    ) {
        self.id = id
        self.request = request
        self.response = response
        self.failure = failure
        self.timing = timing
        self.connection = connection
        self.size = size
    }

    /// How this transaction ended.
    public var outcome: TransactionOutcome {
        if let failure {
            return failure.isCancelled ? .cancelled : .failed
        }
        switch response?.statusCode ?? 0 {
        case 200..<300: return .success
        case 300..<400: return .redirection
        case 400..<500: return .clientError
        case 500...: return .serverError
        default: return .failed
        }
    }
}

/// How a transaction ended.
public enum TransactionOutcome: Sendable, Equatable {
    /// A 2xx response.
    case success

    /// A 3xx response.
    case redirection

    /// A 4xx response.
    case clientError

    /// A 5xx response.
    case serverError

    /// No usable response came back.
    case failed

    /// The app cancelled the request.
    case cancelled
}

/// What the app sent.
public struct CapturedRequest: Sendable, Equatable {
    /// The URL, with matching query parameters redacted.
    public let url: URL?

    /// The HTTP method.
    public let method: String

    /// The request headers.
    public let headers: [NamedValue]

    /// The query parameters.
    public let queryParameters: [NamedValue]

    /// The body, if there was one.
    public let body: CapturedBody?

    /// When the request started.
    public let startDate: Date

    /// Creates a request.
    public init(
        url: URL?,
        method: String,
        headers: [NamedValue] = [],
        queryParameters: [NamedValue] = [],
        body: CapturedBody? = nil,
        startDate: Date
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.queryParameters = queryParameters
        self.body = body
        self.startDate = startDate
    }
}

/// What came back.
public struct CapturedResponse: Sendable, Equatable {
    /// The HTTP status code.
    public let statusCode: Int

    /// The response headers.
    public let headers: [NamedValue]

    /// The decoded body, if there was one.
    public let body: CapturedBody?

    /// The MIME type the server reported.
    public let mimeType: String?

    /// The encoding URLSession removed on the way in, such as `gzip`.
    public let contentEncoding: String?

    /// When the response finished.
    public let endDate: Date

    /// Creates a response.
    public init(
        statusCode: Int,
        headers: [NamedValue] = [],
        body: CapturedBody? = nil,
        mimeType: String? = nil,
        contentEncoding: String? = nil,
        endDate: Date
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.mimeType = mimeType
        self.contentEncoding = contentEncoding
        self.endDate = endDate
    }
}

/// Why a request didn't finish.
public struct CapturedFailure: Sendable, Equatable {
    /// The error domain.
    public let domain: String

    /// The error code.
    public let code: Int

    /// The error's description.
    public let description: String

    /// Whether the app cancelled the request, rather than it failing.
    public var isCancelled: Bool {
        domain == NSURLErrorDomain && code == NSURLErrorCancelled
    }

    /// Creates a failure.
    public init(domain: String, code: Int, description: String) {
        self.domain = domain
        self.code = code
        self.description = description
    }
}

/// How long each stage of a request took, in seconds. A stage that didn't happen is `nil`.
public struct TransactionTiming: Sendable, Equatable {
    /// The DNS lookup.
    public let dns: TimeInterval?

    /// Connecting, including TLS.
    public let connect: TimeInterval?

    /// The TLS handshake.
    public let tls: TimeInterval?

    /// Sending the request.
    public let requestSent: TimeInterval?

    /// From the request being sent to the first response byte.
    public let firstByte: TimeInterval?

    /// The whole request.
    public let total: TimeInterval

    /// Creates a timing.
    public init(
        dns: TimeInterval? = nil,
        connect: TimeInterval? = nil,
        tls: TimeInterval? = nil,
        requestSent: TimeInterval? = nil,
        firstByte: TimeInterval? = nil,
        total: TimeInterval
    ) {
        self.dns = dns
        self.connect = connect
        self.tls = tls
        self.requestSent = requestSent
        self.firstByte = firstByte
        self.total = total
    }
}

/// Which connection carried a request.
public struct ConnectionDetails: Sendable, Equatable {
    /// The server's address.
    public let remoteAddress: String?

    /// The server's port.
    public let remotePort: Int?

    /// This device's address.
    public let localAddress: String?

    /// This device's port.
    public let localPort: Int?

    /// The HTTP version, such as `h2`.
    public let httpVersion: String?

    /// The TLS version, such as `TLS 1.3`.
    public let tlsVersion: String?

    /// Whether an existing connection was reused.
    public let isReused: Bool

    /// Whether the connection was cellular.
    public let isCellular: Bool

    /// Whether the connection was expensive.
    public let isExpensive: Bool

    /// Whether Low Data Mode applied.
    public let isConstrained: Bool

    /// Creates connection details.
    public init(
        remoteAddress: String? = nil,
        remotePort: Int? = nil,
        localAddress: String? = nil,
        localPort: Int? = nil,
        httpVersion: String? = nil,
        tlsVersion: String? = nil,
        isReused: Bool = false,
        isCellular: Bool = false,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.localAddress = localAddress
        self.localPort = localPort
        self.httpVersion = httpVersion
        self.tlsVersion = tlsVersion
        self.isReused = isReused
        self.isCellular = isCellular
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}

/// How many bytes moved, from request metrics.
public struct TransferSize: Sendable, Equatable {
    /// Header and body bytes sent.
    public let bytesSent: Int64

    /// Header and body bytes received on the wire.
    public let bytesReceived: Int64

    /// Response body bytes as they crossed the wire.
    public let wireBodyBytes: Int64

    /// Response body bytes after decoding.
    public let decodedBodyBytes: Int64

    /// Creates a size.
    public init(bytesSent: Int64, bytesReceived: Int64, wireBodyBytes: Int64, decodedBodyBytes: Int64) {
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.wireBodyBytes = wireBodyBytes
        self.decodedBodyBytes = decodedBodyBytes
    }

    /// How many times smaller the body was on the wire, such as `4.2`.
    public var compressionRatio: Double? {
        guard wireBodyBytes > 0, decodedBodyBytes > wireBodyBytes else { return nil }
        return Double(decodedBodyBytes) / Double(wireBodyBytes)
    }
}
