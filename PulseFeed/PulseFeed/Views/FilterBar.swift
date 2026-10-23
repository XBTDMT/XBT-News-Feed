import SwiftUI
import UniformTypeIdentifiers

struct FilterBar: View {
    @Binding var selected: String?
    /// Unread per category ("Crypto 4"); `total` labels the All chip ("All 23").
    var counts: [String: Int] = [:]
    var total: Int? = nil
    /// Categories that are switched on; chips for the others are hidden.
    var enabledCategories: Set<String> = Set(NewsCategory.all.map(\.id))
    @AppStorage("filterBarOrder") private var orderData: Data = Data()

    /// The sheet's order: All first, then Brief, then the categories in registry order.
    static let defaultOrder: [String] = ["all", "digest"] + NewsCategory.all.map(\.id) + ["starred", "saved"]

    private var chipOrder: [String] {
        Self.mergedOrder(stored: try? JSONDecoder().decode([String].self, from: orderData), enabled: enabledCategories)
    }

    /// The persisted drag order, with categories it never saw inserted before Starred (registry
    /// order) and categories that are switched off removed. Non-category chips always stay.
    static func mergedOrder(stored: [String]?, enabled: Set<String>) -> [String] {
        let categoryIDs = NewsCategory.all.map(\.id)
        var order = stored ?? defaultOrder
        let missing = categoryIDs.filter { !order.contains($0) }
        if !missing.isEmpty {
            let at = order.firstIndex(of: "starred") ?? order.endIndex
            order.insert(contentsOf: missing, at: at)
        }
        return order.filter { !categoryIDs.contains($0) || enabled.contains($0) }
    }

    private func setChipOrder(_ order: [String]) {
        orderData = (try? JSONEncoder().encode(order)) ?? Data()
    }

    @State private var draggedItem: String?

    private var chipInfo: [String: String] {
        var info = ["digest": "Brief", "all": "All", "starred": "Starred", "saved": "Saved"]
        for c in NewsCategory.all { info[c.id] = c.label }
        return info
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chipOrder, id: \.self) { tag in
                    let label = chipInfo[tag] ?? tag
                    chipView(label: label, tag: tag)
                        .onDrag {
                            draggedItem = tag
                            return NSItemProvider(object: tag as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: FilterDropDelegate(
                            item: tag,
                            items: chipOrder,
                            draggedItem: $draggedItem,
                            onReorder: { newOrder in setChipOrder(newOrder) }
                        ))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    /// The sheet's chip: 12pt, 9/4 padding, #0A84FF with white 600 text when selected, #F2F2F7 with
    /// 500 text otherwise; the count sits 4pt after the label, dimmed on the selected chip and grey
    /// (#8E8E93) on the others.
    @ViewBuilder
    private func chipView(label: String, tag: String) -> some View {
        let isSelected = (selected == tag) || (selected == nil && tag == "all")

        let count: Int? = tag == "all" ? total : counts[tag]
        Button {
            selected = (tag == "all") ? nil : tag
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(isSelected ? Color.white : NativeProPalette.text)
                if let count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : NativeProPalette.textTertiary)
                }
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isSelected ? NativeProPalette.blue : NativeProPalette.field, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FilterDropDelegate: DropDelegate {
    let item: String
    let items: [String]
    @Binding var draggedItem: String?
    let onReorder: ([String]) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem != item,
              let fromIndex = items.firstIndex(of: draggedItem),
              let toIndex = items.firstIndex(of: item)
        else { return }

        var updated = items
        updated.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        onReorder(updated)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
