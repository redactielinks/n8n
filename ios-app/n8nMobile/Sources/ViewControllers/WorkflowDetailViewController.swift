import UIKit

final class WorkflowDetailViewController: UIViewController {

    private let workflow: Workflow
    private let server: N8NServer
    private var client: N8NAPIClient

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let statusBadge = UILabel()
    private let webhookPathField = UITextField()
    private let triggerButton = UIButton(type: .system)
    private let responseView = UITextView()

    init(workflow: Workflow, server: N8NServer) {
        self.workflow = workflow
        self.server = server
        self.client = N8NAPIClient(server: server)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = workflow.name
        view.backgroundColor = .white
        setupScrollView()
        setupContent()
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.layoutMargins = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }

    private func setupContent() {
        // Status row
        let statusRow = UIStackView()
        statusRow.axis = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .center

        let statusTitle = makeLabel("Status:", font: .systemFont(ofSize: 15, weight: .medium))
        statusBadge.text = workflow.active ? " Actief " : " Inactief "
        statusBadge.font = .systemFont(ofSize: 13, weight: .semibold)
        statusBadge.textColor = .white
        statusBadge.backgroundColor = workflow.active ? .systemGreen : .lightGray
        statusBadge.layer.cornerRadius = 4
        statusBadge.clipsToBounds = true
        statusRow.addArrangedSubview(statusTitle)
        statusRow.addArrangedSubview(statusBadge)
        statusRow.addArrangedSubview(UIView())
        stackView.addArrangedSubview(statusRow)

        // Info rows
        stackView.addArrangedSubview(infoRow(label: "ID", value: workflow.id))
        if let created = workflow.createdAt {
            stackView.addArrangedSubview(infoRow(label: "Aangemaakt", value: formatDate(created)))
        }
        if let updated = workflow.updatedAt {
            stackView.addArrangedSubview(infoRow(label: "Bijgewerkt", value: formatDate(updated)))
        }

        stackView.addArrangedSubview(separator())

        // Webhook trigger section
        stackView.addArrangedSubview(makeLabel("Webhook activeren", font: .systemFont(ofSize: 17, weight: .semibold)))
        stackView.addArrangedSubview(makeLabel(
            "Voer het webhook-pad in (bijv. mijn-workflow) en tik Activeren.",
            font: .systemFont(ofSize: 13),
            color: .gray
        ))

        webhookPathField.placeholder = "webhook-pad"
        webhookPathField.borderStyle = .roundedRect
        webhookPathField.autocapitalizationType = .none
        webhookPathField.autocorrectionType = .no
        webhookPathField.keyboardType = .URL
        webhookPathField.clearButtonMode = .whileEditing
        stackView.addArrangedSubview(webhookPathField)

        triggerButton.setTitle("Webhook activeren", for: .normal)
        triggerButton.backgroundColor = UIColor(red: 1.0, green: 0.46, blue: 0.0, alpha: 1.0)
        triggerButton.setTitleColor(.white, for: .normal)
        triggerButton.layer.cornerRadius = 8
        triggerButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        triggerButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        triggerButton.addTarget(self, action: #selector(triggerWebhook), for: .touchUpInside)
        stackView.addArrangedSubview(triggerButton)

        stackView.addArrangedSubview(makeLabel("Reactie:", font: .systemFont(ofSize: 14, weight: .medium)))

        responseView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        responseView.isEditable = false
        responseView.layer.borderColor = UIColor.lightGray.cgColor
        responseView.layer.borderWidth = 1
        responseView.layer.cornerRadius = 6
        responseView.text = "—"
        responseView.textColor = .darkGray
        responseView.heightAnchor.constraint(equalToConstant: 120).isActive = true
        stackView.addArrangedSubview(responseView)
    }

    // MARK: - Actions

    @objc private func triggerWebhook() {
        guard let path = webhookPathField.text, !path.isEmpty else {
            responseView.text = "Voer een webhook-pad in."
            return
        }
        triggerButton.isEnabled = false
        triggerButton.setTitle("Bezig...", for: .normal)
        responseView.text = "Verzoek versturen..."

        client.triggerWebhook(path: path) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.triggerButton.isEnabled = true
                self.triggerButton.setTitle("Webhook activeren", for: .normal)
                switch result {
                case .success(let response):
                    self.responseView.text = response
                    self.responseView.textColor = .systemGreen
                case .failure(let error):
                    self.responseView.text = error.localizedDescription
                    self.responseView.textColor = .systemRed
                }
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        let lbl = makeLabel(label + ":", font: .systemFont(ofSize: 14, weight: .medium))
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let val = makeLabel(value, font: .systemFont(ofSize: 14))
        val.textColor = .darkGray
        val.numberOfLines = 0
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(val)
        return row
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor = .black) -> UILabel {
        let lbl = UILabel()
        lbl.text = text
        lbl.font = font
        lbl.textColor = color
        lbl.numberOfLines = 0
        return lbl
    }

    private func separator() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.9, alpha: 1)
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            display.locale = Locale(identifier: "nl_NL")
            return display.string(from: date)
        }
        return iso
    }
}
