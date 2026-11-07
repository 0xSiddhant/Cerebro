#if SWIFT_PACKAGE
@_exported import CerebroCore
#endif

/// The host app's one entry point. Plan 1 fills these in.
public enum Cerebro {
    /// Starts capture. Call it as early as you can, because sessions created before it aren't captured.
    public static func start(_ configuration: CerebroConfiguration = CerebroConfiguration()) {}

    /// Stops capture.
    public static func stop() {}

    /// Opens the dashboard, for example from the app's own debug menu.
    public static func present() {}
}
