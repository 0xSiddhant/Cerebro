/// A common header that carries a credential. Select the ones to redact in `RedactionRules`.
public enum SensitiveHeader: String, CaseIterable, Sendable {
    /// `Authorization`, which carries a bearer token or login credentials.
    case authorization = "Authorization"

    /// `Proxy-Authorization`, which carries the credentials for a proxy.
    case proxyAuthorization = "Proxy-Authorization"

    /// `Cookie`, which carries the app's cookies, often including its session.
    case cookie = "Cookie"

    /// `Set-Cookie`, which carries the cookies a server hands out.
    case setCookie = "Set-Cookie"

    /// `Api-Key`, which carries an API key.
    case apiKey = "Api-Key"

    /// `X-Api-Key`, which carries an API key.
    case xAPIKey = "X-Api-Key"

    /// `X-Auth-Token`, which carries a session or authentication token.
    case xAuthToken = "X-Auth-Token"

    /// `X-Access-Token`, which carries an access token.
    case xAccessToken = "X-Access-Token"

    /// `X-CSRF-Token`, which carries a token that guards against cross-site request forgery.
    case xCSRFToken = "X-CSRF-Token"

    /// `X-XSRF-Token`, which carries the same kind of token under the name some frameworks use.
    case xXSRFToken = "X-XSRF-Token"

    /// `X-Amz-Security-Token`, which carries a temporary AWS session token.
    case xAmzSecurityToken = "X-Amz-Security-Token"

    /// `X-Goog-Api-Key`, which carries a Google API key.
    case xGoogAPIKey = "X-Goog-Api-Key"
}

/// What to redact. Nothing is redacted until it's selected here. Names are matched without regard to case.
public struct RedactionRules: Sendable {
    /// Common credential headers to redact. Empty by default, so these headers are stored as sent.
    public var sensitiveHeaders: Set<SensitiveHeader>

    /// Header names to redact, for names `SensitiveHeader` doesn't have.
    public var headers: Set<String>

    /// Body field names to redact: JSON keys at any depth, and form-encoded fields. Setting these makes
    /// Cerebro parse those bodies at capture. Any other text can't be redacted field by field, so it's
    /// withheld if it names a key. Binary bodies are stored as sent.
    public var jsonKeys: Set<String>

    /// Query parameters to redact.
    public var queryParameters: Set<String>

    /// Creates a set of rules. Every argument defaults to redacting nothing.
    public init(
        sensitiveHeaders: Set<SensitiveHeader> = [],
        headers: Set<String> = [],
        jsonKeys: Set<String> = [],
        queryParameters: Set<String> = []
    ) {
        self.sensitiveHeaders = sensitiveHeaders
        self.headers = headers
        self.jsonKeys = jsonKeys
        self.queryParameters = queryParameters
    }
}
