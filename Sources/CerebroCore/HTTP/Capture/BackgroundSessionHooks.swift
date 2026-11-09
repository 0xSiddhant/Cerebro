import Foundation
import ObjectiveC
import os

/// Puts a `BackgroundSessionProxy` in front of the app's delegate on every background session, because
/// a `URLProtocol` never runs for one. Every other session is left alone.
enum BackgroundSessionHooks {
    private typealias Factory =
        @convention(c) (AnyObject, Selector, URLSessionConfiguration, AnyObject?, OperationQueue?) -> URLSession
    private typealias FactoryHook =
        @convention(block) (AnyObject, URLSessionConfiguration, AnyObject?, OperationQueue?) -> URLSession
    private typealias DelegateGetter = @convention(c) (AnyObject, Selector) -> AnyObject?

    /// Safety for `@unchecked Sendable`: both are opaque runtime pointers that never change.
    private struct InstalledHook: @unchecked Sendable {
        let method: Method
        let original: IMP
    }

    private static let installed = OSAllocatedUnfairLock<InstalledHook?>(initialState: nil)
    private static let classesHidingProxy = OSAllocatedUnfairLock<Set<ObjectIdentifier>>(initialState: [])

    /// `URLSession(configuration:)` goes through this same method, so one hook covers both.
    static func install() {
        let selector = NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:")
        guard let method = class_getClassMethod(URLSession.self, selector) else { return }
        let original = method_getImplementation(method)
        let makeSession = unsafeBitCast(original, to: Factory.self)
        let hook: FactoryHook = { sessionClass, configuration, delegate, queue in
            guard configuration.identifier != nil else {
                return makeSession(sessionClass, selector, configuration, delegate, queue)
            }
            let proxy = BackgroundSessionProxy(target: delegate)
            let session = makeSession(sessionClass, selector, configuration, proxy, queue)
            hideProxy(on: type(of: session))
            return session
        }
        method_setImplementation(method, imp_implementationWithBlock(hook))
        let hookToRestore = InstalledHook(method: method, original: original)
        installed.withLock { $0 = hookToRestore }
    }

    /// Only stops new sessions getting a proxy. A session's delegate can't be replaced, so existing ones
    /// keep theirs, and the getter hook has to stay for them.
    static func uninstall() {
        let hook = installed.withLock { hook -> InstalledHook? in
            defer { hook = nil }
            return hook
        }
        if let hook {
            method_setImplementation(hook.method, hook.original)
        }
    }

    /// Without this, code that casts `session.delegate` back to its own class would break. The class comes
    /// from a real session, so no private name is needed, and a missing method just means no hook.
    ///
    /// A session whose app passed no delegate keeps reporting its proxy. Reporting `nil` while a proxy is
    /// really installed over-released the session when it was invalidated.
    private static func hideProxy(on sessionClass: AnyClass) {
        guard classesHidingProxy.withLock({ $0.insert(ObjectIdentifier(sessionClass)).inserted }) else { return }
        let selector = NSSelectorFromString("delegate")
        guard let inherited = class_getInstanceMethod(sessionClass, selector) else { return }
        let original = unsafeBitCast(method_getImplementation(inherited), to: DelegateGetter.self)
        let hook: @convention(block) (AnyObject) -> AnyObject? = { session in
            let delegate = original(session, selector)
            if let proxy = delegate as? BackgroundSessionProxy, let target = proxy.target {
                return target
            }
            return delegate
        }
        class_replaceMethod(
            sessionClass, selector, imp_implementationWithBlock(hook), method_getTypeEncoding(inherited))
    }
}
