import Foundation
import ObjectiveC

/// Puts Cerebro's protocols into `.default` and `.ephemeral` configurations by swizzling their getters.
enum SessionConfigurationInjector {
    private static let swaps = [
        (
            #selector(getter: URLSessionConfiguration.default),
            #selector(URLSessionConfiguration.cerebroDefaultConfiguration)
        ),
        (
            #selector(getter: URLSessionConfiguration.ephemeral),
            #selector(URLSessionConfiguration.cerebroEphemeralConfiguration)
        ),
    ]

    /// Exchanges the getters. Calling it again exchanges them back, so `stop` undoes `start`.
    static func exchangeGetters() {
        for (original, replacement) in swaps {
            guard let originalMethod = class_getClassMethod(URLSessionConfiguration.self, original),
                let replacementMethod = class_getClassMethod(URLSessionConfiguration.self, replacement)
            else { continue }
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }
}

extension URLSessionConfiguration {
    // While exchanged, these names point at the original getters, so neither of these recurses.

    @objc fileprivate class func cerebroDefaultConfiguration() -> URLSessionConfiguration {
        cerebroDefaultConfiguration().injecting(CustomURLProtocol.self)
    }

    @objc fileprivate class func cerebroEphemeralConfiguration() -> URLSessionConfiguration {
        cerebroEphemeralConfiguration().injecting(EphemeralURLProtocol.self)
    }

    private func injecting(_ protocolClass: AnyClass) -> URLSessionConfiguration {
        protocolClasses = [protocolClass] + (protocolClasses ?? [])
        return self
    }
}
