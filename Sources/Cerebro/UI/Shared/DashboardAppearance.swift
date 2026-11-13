import UIKit

/// Every navigation stack the dashboard creates. It themes its own bars, and `DashboardTheme.register()`
/// reaches the views inside it, so the app's own views are never touched.
final class DashboardNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        DashboardTheme.style(self)
    }
}

/// How the theme reaches the views. Colours come from `DashboardTheme`, and nothing here picks its own.
@MainActor
extension DashboardTheme {
    /// Themes the views UIKit builds itself, such as table cells, search fields and segmented controls,
    /// but only inside `DashboardNavigationController`. Calling it again changes nothing.
    static func register() {
        let inside = [DashboardNavigationController.self]
        UITableViewCell.appearance(whenContainedInInstancesOf: inside).backgroundColor = card
        UISearchTextField.appearance(whenContainedInInstancesOf: inside).backgroundColor = field
        UIRefreshControl.appearance(whenContainedInInstancesOf: inside).tintColor = accent
        UIActivityIndicatorView.appearance(whenContainedInInstancesOf: inside).color = accent
        // The selected segment is light glass on iOS 26 and a light or grey pill before it, so its label
        // takes the accent, which reads on all of them, rather than white.
        UISegmentedControl.appearance(whenContainedInInstancesOf: inside)
            .setTitleTextAttributes([.foregroundColor: accent], for: .selected)
    }

    /// A list's colours. A plain list is all card, and a grouped one sets its cards on the background.
    static func style(_ tableView: UITableView) {
        tableView.backgroundColor = tableView.style == .plain ? card : background
        tableView.separatorColor = separator
    }

    /// A navigation stack's bars.
    static func style(_ navigation: UINavigationController) {
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = background
        bar.shadowColor = separator
        navigation.navigationBar.standardAppearance = bar
        navigation.navigationBar.scrollEdgeAppearance = bar
        navigation.navigationBar.compactAppearance = bar
        navigation.navigationBar.tintColor = accent
        let toolbar = UIToolbarAppearance()
        toolbar.configureWithOpaqueBackground()
        toolbar.backgroundColor = background
        toolbar.shadowColor = separator
        navigation.toolbar.standardAppearance = toolbar
        navigation.toolbar.scrollEdgeAppearance = toolbar
        navigation.toolbar.compactAppearance = toolbar
        navigation.toolbar.tintColor = accent
    }

    /// The tab bar, with the selected tab in the accent.
    static func style(_ tabBar: UITabBar) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.shadowColor = separator
        let layouts = [
            appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ]
        for layout in layouts {
            layout.selected.iconColor = accent
            layout.selected.titleTextAttributes = [.foregroundColor: accent]
        }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = accent
    }
}
