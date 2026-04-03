import UIKit

final class ServerFormViewController: UITableViewController {

    private let existingServer: N8NServer?

    private let nameField = UITextField()
    private let urlField = UITextField()
    private let apiKeyField = UITextField()

    init(server: N8NServer?) {
        self.existingServer = server
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = existingServer == nil ? "Server toevoegen" : "Server bewerken"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self, action: #selector(save)
        )

        configure(field: nameField, placeholder: "Mijn n8n server", isSecure: false)
        configure(field: urlField, placeholder: "https://n8n.example.com", isSecure: false)
        configure(field: apiKeyField, placeholder: "API-sleutel", isSecure: true)
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        apiKeyField.autocapitalizationType = .none
        apiKeyField.autocorrectionType = .no

        if let server = existingServer {
            nameField.text = server.name
            urlField.text = server.baseURL
            apiKeyField.text = server.apiKey
        }
    }

    private func configure(field: UITextField, placeholder: String, isSecure: Bool) {
        field.placeholder = placeholder
        field.isSecureTextEntry = isSecure
        field.frame = CGRect(x: 16, y: 0, width: 300, height: 44)
        field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    // MARK: - Table view

    private let labels = ["Naam", "Server URL", "API-sleutel"]
    private lazy var fields = [nameField, urlField, apiKeyField]

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = labels[indexPath.row]
        cell.contentView.addSubview(fields[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Verbindingsinstellingen"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "De API-sleutel vind je in n8n onder Instellingen > API."
    }

    // MARK: - Save

    @objc private func save() {
        guard
            let name = nameField.text, !name.isEmpty,
            let urlText = urlField.text, !urlText.isEmpty,
            let apiKey = apiKeyField.text, !apiKey.isEmpty
        else {
            showAlert(title: "Veld ontbreekt", message: "Vul alle velden in.")
            return
        }

        let cleanURL = urlText.hasSuffix("/") ? String(urlText.dropLast()) : urlText

        if var server = existingServer {
            server.name = name
            server.baseURL = cleanURL
            server.apiKey = apiKey
            ServerStore.shared.update(server)
        } else {
            let server = N8NServer(name: name, baseURL: cleanURL, apiKey: apiKey)
            ServerStore.shared.add(server)
        }
        navigationController?.popViewController(animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
