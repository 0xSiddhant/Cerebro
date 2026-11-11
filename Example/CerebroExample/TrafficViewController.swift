import UIKit

/// Fires every kind of test traffic on launch, so the dashboard has something to show.
/// Tap a row to send that traffic again.
final class TrafficViewController: UITableViewController {
    private static let cellIdentifier = "TrafficCell"

    private var results: [TrafficSample: String] = [:]

    init() {
        super.init(style: .insetGrouped)
        title = "Cerebro Example"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TrafficViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        TrafficSample.allCases.filter { $0.hint == nil }.forEach(run)
        // Also fires for a download an earlier launch started, if it's still running.
        BackgroundTransfers.onProgress = { [weak self] progress in
            self?.show(progress, for: .backgroundLargeDownload)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        TrafficSample.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sample = TrafficSample.allCases[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)

        var content = UIListContentConfiguration.subtitleCell()
        content.text = sample.title
        content.secondaryText = results[sample] ?? sample.hint
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        run(TrafficSample.allCases[indexPath.row])
    }

    private func run(_ sample: TrafficSample) {
        show("Running…", for: sample)

        Task {
            do {
                show(try await sample.run(), for: sample)
            } catch {
                show(error.localizedDescription, for: sample)
            }
        }
    }

    private func show(_ result: String, for sample: TrafficSample) {
        results[sample] = result
        tableView.reloadData()
    }
}
