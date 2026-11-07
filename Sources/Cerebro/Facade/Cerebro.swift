#if SWIFT_PACKAGE
@_exported import CerebroCore
#endif

/// The host app's one entry point. Plan 1 fills these in.
public enum Cerebro {
    public static func start(_ configuration: CerebroConfiguration = CerebroConfiguration()) {}

    public static func stop() {}

    public static func present() {}
}
