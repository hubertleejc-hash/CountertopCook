import Foundation
import CoreGraphics

/// Puts the text read from a photo of a recipe back in reading order.
///
/// Recipe cards are laid out in blocks: a title, an ingredient grid of two or three columns,
/// a grid of numbered step panels with a picture above each. Reading such a card line by line
/// across the whole width mixes the panels up ("4 Boil the noodles 5 Drain 6 Prepare…"). This
/// reads it the way a person does, with a recursive XY-cut: split the page at wide empty bands,
/// top to bottom first, then left to right, until each block is a single column, and read
/// each block line by line.
public enum TextLayout {
    /// One piece of text the recogniser found, with its box in pixels (origin top left).
    public struct Box: Equatable {
        public var text: String
        public var rect: CGRect
        public init(text: String, rect: CGRect) { self.text = text; self.rect = rect }
    }

    /// The text of the boxes in reading order: one line per row of a block, blocks one after another.
    public static func readingOrder(_ boxes: [Box]) -> String {
        let boxes = boxes.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.rect.height > 0 }
        guard !boxes.isEmpty else { return "" }
        // The size of ordinary text on this page: the median line height.
        let heights = boxes.map(\.rect.height).sorted()
        let lineHeight = heights[heights.count / 2]
        var lines: [String] = []
        cut(boxes, lineHeight: lineHeight, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func cut(_ boxes: [Box], lineHeight: CGFloat, depth: Int, into lines: inout [String]) {
        guard boxes.count > 1, depth < 24 else {
            lines.append(contentsOf: rows(boxes))
            return
        }
        // 1. Wide empty bands across the page (a picture between rows of text, a gap between
        //    sections): cut there first, top to bottom.
        let horizontal = gaps(boxes.map { ($0.rect.minY, $0.rect.maxY) })
        if let groups = split(boxes, at: horizontal.filter { $0.width > lineHeight * 1.2 }, vertical: false) {
            for group in groups { cut(group, lineHeight: lineHeight, depth: depth + 1, into: &lines) }
            return
        }
        // 2. Columns: empty bands down the block, wider than a couple of spaces.
        let vertical = gaps(boxes.map { ($0.rect.minX, $0.rect.maxX) })
        if let groups = split(boxes, at: vertical.filter { $0.width > lineHeight * 1.1 }, vertical: true) {
            for group in groups { cut(group, lineHeight: lineHeight, depth: depth + 1, into: &lines) }
            return
        }
        // 3. Rows of text: the small gaps between lines. Each row may still hold several cells
        //    (an ingredient grid), which the next round splits into columns.
        if let groups = split(boxes, at: horizontal.filter { $0.width > lineHeight * 0.15 }, vertical: false),
           groups.count > 1 {
            for group in groups { cut(group, lineHeight: lineHeight, depth: depth + 1, into: &lines) }
            return
        }
        lines.append(contentsOf: rows(boxes))
    }

    private struct Gap { var start: CGFloat; var end: CGFloat; var width: CGFloat { end - start } }

    /// The empty bands between the boxes' extents along one axis.
    private static func gaps(_ spans: [(CGFloat, CGFloat)]) -> [Gap] {
        let sorted = spans.sorted { $0.0 < $1.0 }
        var result: [Gap] = []
        guard var reach = sorted.first?.1 else { return [] }
        for (start, end) in sorted.dropFirst() {
            if start > reach { result.append(Gap(start: reach, end: start)) }
            reach = max(reach, end)
        }
        return result
    }

    /// The boxes in groups between the gaps, in order; nil when there is no gap to cut at.
    private static func split(_ boxes: [Box], at cuts: [Gap], vertical: Bool) -> [[Box]]? {
        guard !cuts.isEmpty else { return nil }
        let marks = cuts.map { ($0.start + $0.end) / 2 }.sorted()
        var groups = [[Box]](repeating: [], count: marks.count + 1)
        for box in boxes {
            let centre = vertical ? box.rect.midX : box.rect.midY
            let index = marks.firstIndex { centre < $0 } ?? marks.count
            groups[index].append(box)
        }
        let filled = groups.filter { !$0.isEmpty }
        return filled.count > 1 ? filled : nil
    }

    /// A block with no gaps left: top to bottom, and boxes at the same height joined left to right.
    static func rows(_ boxes: [Box]) -> [String] {
        let sorted = boxes.sorted { $0.rect.midY < $1.rect.midY }
        var rows: [[Box]] = []
        for box in sorted {
            if let last = rows.last?.last,
               abs(last.rect.midY - box.rect.midY) < min(last.rect.height, box.rect.height) * 0.5 {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }
        return rows.map { row in
            row.sorted { $0.rect.minX < $1.rect.minX }.map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }
    }
}
