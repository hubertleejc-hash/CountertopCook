import SwiftUI
import PhotosUI
import VisionKit

/// Import from photos: pick photos or screenshots of a recipe, or scan a page with the camera.
/// The text is read on the phone (see PhotoText), then the review screen opens in this sheet
/// like any other import. Nothing is saved until the cook taps Save there.
struct PhotoImportView: View {
    let onSaved: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    let scanNow: Bool
    @State private var scanning = false
    @State private var reading = false
    @State private var readError: String?
    @State private var draft: RecipeDraft?

    init(scanNow: Bool = false, onSaved: @escaping (Recipe) -> Void) {
        self.onSaved = onSaved
        self.scanNow = scanNow
    }

    var body: some View {
        if let draft {
            RecipeEditorView(review: draft, onSaved: onSaved)
        } else {
            NavigationStack {
                Form {
                    Section {
                        PhotosPicker(selection: $picked, maxSelectionCount: 10, selectionBehavior: .ordered,
                                     matching: .images) {
                            Label("Choose photos or screenshots", systemImage: "photo.on.rectangle.angled")
                                .frame(minHeight: 44)
                        }
                        .disabled(reading)
                        .accessibilityIdentifier("photoImportPick")
                        if DocumentScanner.isSupported {
                            Button {
                                scanning = true
                            } label: {
                                Label("Scan a page with the camera", systemImage: "doc.viewfinder")
                                    .frame(minHeight: 44)
                            }
                            .disabled(reading)
                            .accessibilityIdentifier("photoImportScan")
                        }
                        if reading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Reading the recipe…")
                            }
                            .accessibilityIdentifier("photoImportProgress")
                        }
                        if let readError {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                                Text(readError)
                            }
                            .font(Theme.body(13, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("photoImportError")
                        }
                    } header: {
                        Text("Photos")
                    } footer: {
                        Text("A cookbook page, a recipe card, a handwritten note, or screenshots of the recipe from a video or a post. Pick several to read them as one recipe, in the order you tap them. The text is read on this iPhone, and you review it before anything is saved.")
                    }.warmRows()
                }
                .warmList()
                .navigationTitle("Import from Photos")
                .navigationBarTitleDisplayMode(.inline)
                .font(Theme.body())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onChange(of: picked) { _, items in
                    guard !items.isEmpty else { return }
                    read { try await loadData(items) }
                }
                .task {
                    // + → Scan a recipe page: the camera opens once this sheet has finished sliding up.
                    guard scanNow, DocumentScanner.isSupported else { return }
                    try? await Task.sleep(for: .milliseconds(450))
                    scanning = true
                }
                .fullScreenCover(isPresented: $scanning) {
                    DocumentScanner { pages in
                        scanning = false
                        guard !pages.isEmpty else { return }
                        read { pages.compactMap { $0.jpegData(compressionQuality: 0.9) } }
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    private func loadData(_ items: [PhotosPickerItem]) async throws -> [Data] {
        var pictures: [Data] = []
        for item in items {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoText.Failure.notAnImage }
            pictures.append(data)
        }
        return pictures
    }

    private func read(_ pictures: @escaping () async throws -> [Data]) {
        guard !reading else { return }
        reading = true
        readError = nil
        Task {
            do {
                let text = try await PhotoText.text(inImageData: try await pictures())
                draft = LinkImport.draft(fromText: text, sourceName: "Photo")
            } catch {
                readError = error.localizedDescription
            }
            picked = []
            reading = false
        }
    }
}

/// VisionKit's document camera: finds the page's edges, flattens it and hands back each page.
struct DocumentScanner: UIViewControllerRepresentable {
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    /// Called once with the scanned pages; empty when the scan was cancelled or failed.
    let done: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            done([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            done([])
        }
    }
}
