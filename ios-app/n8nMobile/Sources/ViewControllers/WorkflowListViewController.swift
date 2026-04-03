import UIKit

final class WorkflowListViewController: UITableViewController {

    private let server: N8NServer
    private var workflows: [Workflow] = []
    private var client: N8NAPIClient
    private let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)

    init(server: N8NServer) {
        self.server = server
        self.client = N8NAPIClient(server: server)
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = server.name
        tableView.register(WorkflowCell.self, forCellReuseIdentifier: WorkflowCell.reuseID)

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(loadWorkflows)),
            UIBarButtonItem(customView: activityIndicator)
        ]

        loadWorkflows()
    }

    @objc private func loadWorkflows() {
        activityIndicator.startAnimating()
        client.fetchWorkflows { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()
                switch result {
                case .success(let list):
                    self.workflows = list
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showAlert(title: "Fout", message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Table view

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if workflows.isEmpty && !activityIndicator.isAnimating {
            let label = UILabel()
            label.text = "Geen workflows gevonden."
            label.textAlignment = .center
            label.textColor = .lightGray
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
        return workflows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: WorkflowCell.reuseID, for: indexPath) as! WorkflowCell
        cell.configure(with: workflows[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 60 }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let vc = WorkflowDetailViewController(workflow: workflows[indexPath.row], server: server)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - WorkflowCell

final class WorkflowCell: UITableViewCell {

    static let reuseID = "WorkflowCell"

    private let statusDot = UIView()
    private let nameLabel = UILabel()
    private let idLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        statusDot.layer.cornerRadius = 6
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusDot)

        nameLabel.font = .systemFont(ofSize: 16, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        idLabel.font = .systemFont(ofSize: 12)
        idLabel.textColor = .lightGray
        idLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(idLabel)

        NSLayoutConstraint.activate([
            statusDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusDot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 12),
            statusDot.heightAnchor.constraint(equalToConstant: 12),

            nameLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            idLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            idLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2)
        ])
    }

    func configure(with workflow: Workflow) {
        nameLabel.text = workflow.name
        idLabel.text = "ID: \(workflow.id)"
        statusDot.backgroundColor = workflow.active ? .systemGreen : .lightGray
        accessoryType = .disclosureIndicator
    }
}
