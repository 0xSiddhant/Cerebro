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

    /// A list's colours: its rows are cards on the page's background, as on every screen.
    static func style(_ tableView: UITableView) {
        tableView.backgroundColor = background
        tableView.separatorColor = separator
        // A grouped list leaves a tall gap above its first card when it has no header view. A screen that
        // sets its own, such as System Info's summary card, replaces this one.
        if tableView.style != .plain, tableView.tableHeaderView == nil {
            let none = CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNonzeroMagnitude)
            tableView.tableHeaderView = UIView(frame: none)
        }
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
