import UIKit
import UniformTypeIdentifiers

/// Hearth in the iOS Share Sheet. Takes the shared link (a video, a recipe page) or text and
/// hands it to the app as `hearth://import?url=…` or `?text=…`; the app then fetches, reads and
/// shows its review screen. Shared photos or screenshots of a recipe are read here, on the
/// phone (PhotoText), and their text is handed over as `?text=…&source=photo`. Nothing is saved here.
///
/// A share extension has no official way to open its own app, so this walks the responder chain
/// to the host's `openURL:options:completionHandler:`. If that ever stops working, the shared
/// link or text is also copied, and the message says to open Hearth and paste it.
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Hearth's cream by day, Evening Hearth espresso at night.
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x1C / 255, green: 0x17 / 255, blue: 0x12 / 255, alpha: 1)
                : UIColor(red: 0xFB / 255, green: 0xF3 / 255, blue: 0xE4 / 255, alpha: 1)
        }
        label.text = "Sending to Hearth…"
        label.textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xF5 / 255, green: 0xED / 255, blue: 0xE3 / 255, alpha: 1)
                : UIColor(red: 0x22 / 255, green: 0x1C / 255, blue: 0x15 / 255, alpha: 1)
        }
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
            DispatchQueue.main.async {
                guard let self else { return }
                if link == nil, (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, self.hasImages {
                    self.readImages()
                } else {
                    self.handOff(link: link, text: text)
                }
            }
        }
    }

    private var imageProviders: [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    }

    private var hasImages: Bool { !imageProviders.isEmpty }

    /// Reads the text of the shared photos, in the order shared, and hands it to the app.
    private func readImages() {
        label.text = "Reading the recipe…"
        let providers = Array(imageProviders.prefix(10))
        var pictures = [Data?](repeating: nil, count: providers.count)
        let group = DispatchGroup()
        let lock = NSLock()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                lock.lock(); pictures[index] = data; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                do {
                    // Smaller than in the app: a share extension has little memory to work in.
                    let text = try await PhotoText.text(inImageData: pictures.compactMap { $0 }, maxPixel: 2200)
                    self.handOff(link: nil, text: text, source: "photo")
                } catch {
                    self.finish(message: error.localizedDescription)
                }
            }
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

    private func handOff(link: URL?, text: String?, source: String? = nil) {
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
                + (source.map { [URLQueryItem(name: "source", value: $0)] } ?? [])
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
