import UIKit

final class ServerListViewController: UITableViewController {

    private var servers: [N8NServer] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "n8n Servers"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self, action: #selector(addServer)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        servers = ServerStore.shared.servers
        tableView.reloadData()
    }

    // MARK: - Table view

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if servers.isEmpty {
            let label = UILabel()
            label.text = "Geen servers.\nTik + om een server toe te voegen."
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .lightGray
            label.font = .systemFont(ofSize: 16)
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
        return servers.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let server = servers[indexPath.row]
        cell.textLabel?.text = server.name
        cell.detailTextLabel?.text = server.baseURL
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let vc = WorkflowListViewController(server: servers[indexPath.row])
        navigationController?.pushViewController(vc, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        if editingStyle == .delete {
            ServerStore.shared.delete(at: indexPath.row)
            servers.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    // MARK: - Actions

    @objc private func addServer() {
        let vc = ServerFormViewController(server: nil)
        navigationController?.pushViewController(vc, animated: true)
    }
}
