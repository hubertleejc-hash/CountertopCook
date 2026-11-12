import SwiftUI
import UIKit

/// The hinge state Cook Mode lays itself out for, read from `UIHingeInteraction`.
/// `.none` means no hinge: a normal iPhone or iPad, or an SDK without the fold APIs.
enum FoldPosture: String {
    case none, closed, partiallyOpen, fullyOpen, unknown

    var isUnfolded: Bool { self == .partiallyOpen || self == .fullyOpen }
}

/// Reports the hinge posture of the screen Cook Mode is on. On SDKs without the fold APIs it
/// does nothing, so the posture stays `.none` and Cook Mode keeps its stacked layout.
struct HingeProbe: View {
    @Binding var posture: FoldPosture

    var body: some View {
        #if FOLD_APIS
        if #available(iOS 27.1, *) {
            HingeProbeView(posture: $posture).frame(width: 1, height: 1)
        }
        #endif
    }
}

#if FOLD_APIS

/// A 1-pt view carrying a `UIHingeInteraction`. Its accessibility label ("foldState") is the
/// posture, so UI tests can confirm which state the app detected.
@available(iOS 27.1, *)
private struct HingeProbeView: UIViewRepresentable {
    @Binding var posture: FoldPosture

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "foldState"
        view.accessibilityLabel = FoldPosture.none.rawValue
        let coordinator = context.coordinator
        let interaction = UIHingeInteraction { [weak view] _, update in
            let posture = Self.posture(update.hinge)
            view?.accessibilityLabel = posture.rawValue
            // Not during a SwiftUI update: hand the change over on the next main-queue turn.
            DispatchQueue.main.async { coordinator.report?(posture) }
        }
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let binding = $posture
        context.coordinator.report = { if binding.wrappedValue != $0 { binding.wrappedValue = $0 } }
    }

    private static func posture(_ hinge: UIHinge?) -> FoldPosture {
        guard let hinge else { return .none }
        switch hinge.status {
        case .closed: return .closed
        case .partiallyOpen: return .partiallyOpen
        case .fullyOpen: return .fullyOpen
        default: return .unknown
        }
    }

    final class Coordinator {
        var report: ((FoldPosture) -> Void)?
    }
}

/// Recipe and timers in a `UIArrangementViewController` split arrangement, for an unfolded
/// iPhone Duo. The arrangement puts the primary view leading (or on top) and the secondary
/// trailing (or below). The gap between them comes from the hinge's reserved region.
@available(iOS 27.1, *)
struct FoldSplitView<Primary: View, Secondary: View>: UIViewControllerRepresentable {
    let primary: Primary
    let secondary: Secondary
    /// Called when the hinge's direction is known or changes: true when it runs top to bottom
    /// (panes side by side), false when it runs across (panes stacked, as on a tabletop), nil
    /// when this screen has no hinge region at all (the outer screen).
    /// Book pose: a soft shade either side of the spine (decorative, on the hinge region).
    var bookFold = false
    var onHingeAxis: ((Bool?) -> Void)? = nil

    func makeUIViewController(context: Context) -> FoldSplitController {
        let controller = FoldSplitController(primary: AnyView(primary), secondary: AnyView(secondary))
        controller.onHingeAxis = onHingeAxis
        controller.setBookFold(bookFold)
        return controller
    }

    func updateUIViewController(_ controller: FoldSplitController, context: Context) {
        controller.onHingeAxis = onHingeAxis
        controller.setBookFold(bookFold)
        controller.update(primary: AnyView(primary), secondary: AnyView(secondary))
    }
}

@available(iOS 27.1, *)
final class FoldSplitController: UIViewController {
    private let arrangement = UIArrangementViewController()
    private let primaryHost: UIHostingController<AnyView>
    private let secondaryHost: UIHostingController<AnyView>
    private let hingeView = HingeGapView()
    var onHingeAxis: ((Bool?) -> Void)?
    /// What was last reported: nothing yet, or the axis (nil for no hinge region).
    private var reported: Bool??
    /// The recipe half's paler tone, laid over the warm root up to the hinge's centre line.
    private let recipeSide = UIView()

    init(primary: AnyView, secondary: AnyView) {
        primaryHost = UIHostingController(rootView: primary)
        secondaryHost = UIHostingController(rootView: secondary)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(primary: AnyView, secondary: AnyView) {
        primaryHost.rootView = primary
        secondaryHost.rootView = secondary
    }

    override func loadView() {
        let root = RegionTrackingView()
        root.onRegionsChanged = { [weak self] in self?.view.setNeedsLayout() }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Two tones under the panes, as in reference-design.png: pale recipe half, warm timers
        // half, meeting at the hinge's centre line. Panes and hinge are clear; no divider.
        view.backgroundColor = Theme.timersSideUI
        recipeSide.backgroundColor = Theme.recipeSideUI
        recipeSide.isUserInteractionEnabled = false
        view.addSubview(recipeSide)
        for host in [primaryHost, secondaryHost] {
            host.view.backgroundColor = .clear
        }
        addChild(arrangement)
        arrangement.view.frame = view.bounds
        arrangement.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arrangement.view.backgroundColor = .clear
        view.addSubview(arrangement.view)
        arrangement.didMove(toParent: self)
        arrangement.setViewController(primaryHost, for: .primary)
        arrangement.setViewController(secondaryHost, for: .secondary)
        arrangement.updateArrangement(.split)
        view.addSubview(hingeView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHinge()
    }

    /// Places the gap on the hinge's division region and keeps each pane's content off it.
    private func layoutHinge() {
        // Fully open, the fold is an inactive region, still with a frame. Partially open, it is
        // active. Prefer an active one.
        let regions = view.reservedRegions(kind: .division, options: .includeInactive)
        let region = regions.first(where: \.isActive) ?? regions.first
        guard let region, !region.frame.isNull, region.frame.width > 0 || region.frame.height > 0 else {
            recipeSide.frame = primaryHost.view.convert(primaryHost.view.bounds, to: view)
            report(nil)
            hingeView.isHidden = true
            setInsets(.zero, on: primaryHost)
            setInsets(.zero, on: secondaryHost)
            return
        }
        // The region's frame already includes the system's margins. Keep at least Cook Mode's
        // usual gap, centred on the real hinge, so the two panes are clearly apart.
        let vertical = region.frame.height >= region.frame.width
        let minimum = CookModeView.hingeGap
        let hinge = vertical
            ? region.frame.insetBy(dx: min(0, (region.frame.width - minimum) / 2), dy: 0)
            : region.frame.insetBy(dx: 0, dy: min(0, (region.frame.height - minimum) / 2))
        hingeView.isHidden = false
        hingeView.frame = hinge
        report(vertical)
        // Pale tone on the recipe's side of the hinge's centre line; the root is the warm tone.
        let recipe = primaryHost.view.convert(primaryHost.view.bounds, to: view)
        let (first, second) = vertical
            ? view.bounds.divided(atDistance: hinge.midX - view.bounds.minX, from: .minXEdge)
            : view.bounds.divided(atDistance: hinge.midY - view.bounds.minY, from: .minYEdge)
        let recipeFirst = vertical ? recipe.midX < hinge.midX : recipe.midY < hinge.midY
        recipeSide.frame = recipeFirst ? first : second
        hingeView.vertical = vertical
        let primaryState = arrangement.state(for: .primary)
        let secondaryState = arrangement.state(for: .secondary)
        hingeView.accessibilityValue = [
            "active=\(region.isActive)",
            "axis=\(vertical ? "vertical" : "horizontal")",
            "region=\(Int(region.frame.minX)),\(Int(region.frame.minY)),\(Int(region.frame.width)),\(Int(region.frame.height))",
            "primaryHidden=\(primaryState?.isHidden ?? true)",
            "secondaryHidden=\(secondaryState?.isHidden ?? true)",
            "splitAxis=\(secondaryState.map { $0.splitAxis == .vertical ? "vertical" : "horizontal" } ?? "none")",
            "fold=\(hingeView.bookFold ? "book" : "none")",
        ].joined(separator: " ")
        view.bringSubviewToFront(hingeView)
        let hosts = [primaryHost, secondaryHost]
        var extra = hosts.map { insets(clearing: hinge, in: $0) }
        // Same-size cards: a status bar or camera inset on one outer edge would leave that pane
        // narrower, so the other pane gets the same amount on its own outer edge.
        let room = zip(hosts, extra).map { host, added -> CGFloat in
            let free = host.view.bounds.inset(by: systemInsets(of: host)).inset(by: added)
            return vertical ? free.width : free.height
        }
        if let target = room.min() {
            for i in hosts.indices where room[i] > target + 0.5 {
                let pane = hosts[i].view.convert(hosts[i].view.bounds, to: view)
                let difference = room[i] - target
                if vertical {
                    if pane.midX < hinge.midX { extra[i].left += difference } else { extra[i].right += difference }
                } else {
                    if pane.midY < hinge.midY { extra[i].top += difference } else { extra[i].bottom += difference }
                }
            }
        }
        for (host, insets) in zip(hosts, extra) {
            setInsets(insets, on: host)
        }
    }

    func setBookFold(_ on: Bool) {
        guard hingeView.bookFold != on else { return }
        hingeView.bookFold = on
        view.setNeedsLayout()
    }

    /// Tells SwiftUI the hinge's direction, once per change and outside the layout pass.
    private func report(_ vertical: Bool?) {
        if let reported, reported == vertical { return }
        reported = .some(vertical)
        let callback = onHingeAxis
        DispatchQueue.main.async { callback?(vertical) }
    }

    /// Extra safe-area insets that keep a pane's content off the part of `hinge` it overlaps.
    /// Zero when the arrangement has already placed the pane clear of the hinge.
    private func insets(clearing hinge: CGRect, in host: UIViewController) -> UIEdgeInsets {
        let pane = host.view!
        let bounds = pane.bounds
        let overlap = pane.convert(hinge, from: view).intersection(bounds)
        guard !overlap.isNull, !overlap.isEmpty else { return .zero }
        let system = systemInsets(of: host)
        var result = UIEdgeInsets.zero
        if overlap.height >= overlap.width {
            if overlap.midX >= bounds.midX {
                result.right = max(0, bounds.maxX - overlap.minX - system.right)
            } else {
                result.left = max(0, overlap.maxX - bounds.minX - system.left)
            }
        } else if overlap.midY >= bounds.midY {
            result.bottom = max(0, bounds.maxY - overlap.minY - system.bottom)
        } else {
            result.top = max(0, overlap.maxY - bounds.minY - system.top)
        }
        return result
    }

    /// The system's own safe-area inset on each edge, without the extra one set here.
    private func systemInsets(of host: UIViewController) -> UIEdgeInsets {
        let safe = host.view.safeAreaInsets, extra = host.additionalSafeAreaInsets
        return UIEdgeInsets(top: max(0, safe.top - extra.top), left: max(0, safe.left - extra.left),
                            bottom: max(0, safe.bottom - extra.bottom), right: max(0, safe.right - extra.right))
    }

    private func setInsets(_ insets: UIEdgeInsets, on host: UIViewController) {
        if host.additionalSafeAreaInsets != insets { host.additionalSafeAreaInsets = insets }
    }
}

/// Root view of the split. UIKit reruns `updateConstraints` when the reserved regions read
/// there change (fold opened or closed), which triggers a fresh hinge layout.
@available(iOS 27.1, *)
private final class RegionTrackingView: UIView {
    var onRegionsChanged: (() -> Void)?

    // Without this UIKit may never call updateConstraints on a view with no constraints.
    override class var requiresConstraintBasedLayout: Bool { true }

    override func updateConstraints() {
        _ = reservedRegions(kind: .division, options: .includeInactive)
        onRegionsChanged?()
        super.updateConstraints()
    }
}

/// The strip over the hinge: invisible (the cream page shows through) and not interactive, so
/// nothing tappable sits here. UI tests find it as "hingeGap" and read the region from its value.
@available(iOS 27.1, *)
private final class HingeGapView: UIView {
    var vertical = true { didSet { setNeedsLayout() } }
    /// Book pose: a soft shade either side of the spine, darkest at the hinge's centre line.
    /// Only a colour gradient: nothing on it can be tapped (the view takes no touches).
    var bookFold = false { didSet { fold.isHidden = !bookFold } }
    private let fold = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "hingeGap"
        accessibilityLabel = "Hinge"
        fold.colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.07).cgColor,
                       UIColor(white: 0, alpha: 0).cgColor]
        fold.locations = [0, 0.5, 1]
        fold.isHidden = true
        layer.addSublayer(fold)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        fold.frame = bounds
        fold.startPoint = vertical ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 0.5, y: 0)
        fold.endPoint = vertical ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0.5, y: 1)
    }
}

#endif
