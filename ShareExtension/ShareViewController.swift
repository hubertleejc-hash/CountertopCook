import UIKit
import UniformTypeIdentifiers

/// Hearth in the iOS Share Sheet. Takes the shared link (a YouTube video, a recipe page) or
/// text and hands it to the app as `hearth://import?url=…` or `?text=…`; the app then fetches,
/// reads and shows its review screen. Nothing is saved here.
///
/// A share extension has no official way to open its own app, so this walks the responder chain
/// to the host's `openURL:options:completionHandler:`. If that ever stops working, the shared
/// link or text is also copied, and the message says to open Hearth and paste it.
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0xFB / 255, green: 0xF3 / 255, blue: 0xE4 / 255, alpha: 1)
        label.text = "Sending to Hearth…"
        label.textColor = UIColor(red: 0x22 / 255, green: 0x1C / 255, blue: 0x15 / 255, alpha: 1)
        label.font = .preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadSharedContent { [weak self] link, text in
            DispatchQueue.main.async { self?.handOff(link: link, text: text) }
        }
    }

    /// The first shared web link, and the first shared plain text, if any.
    private func loadSharedContent(_ done: @escaping (URL?, String?) -> Void) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        var link: URL?
        var text: String?
        let lock = NSLock()
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                lock.lock(); link = item as? URL ?? (item as? String).flatMap(URL.init(string:)); lock.unlock()
                group.leave()
            }
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                lock.lock(); text = item as? String; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { done(link, text) }
    }

    private func handOff(link: URL?, text: String?) {
        var components = URLComponents()
        components.scheme = "hearth"
        components.host = "import"
        // Apps like YouTube share the link as text ("Watch this https://youtu.be/…").
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let link, link.scheme?.hasPrefix("http") == true {
            components.queryItems = [URLQueryItem(name: "url", value: link.absoluteString)]
            UIPasteboard.general.string = link.absoluteString
        } else if !trimmed.isEmpty {
            // Keep the hand-off small; long text is pasted in the app instead.
            components.queryItems = [URLQueryItem(name: "text", value: String(trimmed.prefix(6000)))]
            UIPasteboard.general.string = trimmed
        } else {
            finish(message: "Nothing to import here. Share a link or some text.")
            return
        }
        if let url = components.url, open(url) {
            finish(message: nil)
        } else {
            finish(message: "Copied. Open Hearth and paste it into Import.")
        }
    }

    /// Asks the host application to open `url`, by finding it on the responder chain.
    private func open(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector), let implementation = current.method(for: selector) {
                unsafeBitCast(implementation, to: OpenURL.self)(current, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func finish(message: String?) {
        guard let message else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
