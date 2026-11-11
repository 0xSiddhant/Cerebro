import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The way into sessions saved by earlier launches, the same from the HTTP and Sockets tabs.
@MainActor
enum PreviousSessions {
    /// Safety for `@unchecked Sendable`: UIKit makes this on the main actor and it's only called there.
    private struct MenuCompletion: @unchecked Sendable {
        let finish: ([UIMenuElement]) -> Void
    }

    /// A bar button whose menu lists the saved sessions. The list is read when the menu opens, and a
    /// session's file only when it's chosen, so nothing is loaded for a menu nobody uses.
    static func button(
        archive: SessionArchive,
        open: @escaping @MainActor @Sendable (StoredSession) -> Void
    ) -> UIBarButtonItem {
        let sessions = UIDeferredMenuElement.uncached { completion in
            let completion = MenuCompletion(finish: completion)
            Task { @MainActor in
                let references = await archive.previousSessions()
                completion.finish(actions(for: references, in: archive, open: open))
            }
        }
        let button = UIBarButtonItem(
            image: UIImage(systemName: "clock.arrow.circlepath"),
            menu: UIMenu(title: "Previous sessions", children: [sessions])
        )
        button.accessibilityLabel = "Previous sessions"
        return button
    }

    /// What a previous session's screen is called, so it can't be mistaken for the live one.
    static func title(for session: StoredSession) -> String {
        "Previous: " + DisplayFormat.sessionStart(session.reference.startDate)
    }

    private static func actions(
        for references: [StoredSessionReference],
        in archive: SessionArchive,
        open: @escaping @MainActor @Sendable (StoredSession) -> Void
    ) -> [UIMenuElement] {
        guard !references.isEmpty else {
            return [UIAction(title: "No previous session", attributes: .disabled) { _ in }]
        }
        return references.map { reference in
            UIAction(title: DisplayFormat.sessionStart(reference.startDate), image: UIImage(systemName: "clock")) { _ in
                Task { @MainActor in
                    open(await archive.load(reference))
                }
            }
        }
    }
}
