import UIKit

/// The alerts the Files tab asks and answers with.
@MainActor
enum FileAlerts {
    /// Shows why an action failed: the system's own text, or Cerebro's reason for refusing.
    static func showFailure(_ error: any Error, from presenter: UIViewController) {
        let alert = UIAlertController(
            title: "That didn't work", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    /// Asks for a name, with the part before the extension selected, as the Files app does.
    static func askForName(
        title: String,
        initial: String,
        confirm: String,
        from presenter: UIViewController,
        then use: @escaping @MainActor (String) -> Void
    ) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = initial
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
            field.addAction(
                UIAction { _ in
                    let stem = (initial as NSString).deletingPathExtension
                    let end = field.position(from: field.beginningOfDocument, offset: stem.utf16.count)
                    field.selectedTextRange = end.flatMap { field.textRange(from: field.beginningOfDocument, to: $0) }
                },
                for: .editingDidBegin
            )
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: confirm, style: .default) { [weak alert] _ in
                use(alert?.textFields?.first?.text ?? "")
            }
        )
        presenter.present(alert, animated: true)
    }

    /// Asks before something that can't be undone.
    static func confirmDestruction(
        title: String,
        message: String,
        confirm: String,
        from presenter: UIViewController,
        then destroy: @escaping @MainActor () -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: confirm, style: .destructive) { _ in destroy() })
        presenter.present(alert, animated: true)
    }
}
