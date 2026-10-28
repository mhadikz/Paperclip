import Foundation

enum TimelineGrouping {
    struct Group: Identifiable {
        var id: String { title }
        let title: String
        let items: [ClipItem]
    }

    static func group(_ clips: [ClipItem]) -> [Group] {
        let cal = Calendar.current
        var today: [ClipItem] = []
        var yesterday: [ClipItem] = []
        var lastWeek: [ClipItem] = []
        var earlier: [ClipItem] = []
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast

        for clip in clips {
            if cal.isDateInToday(clip.createdAt) {
                today.append(clip)
            } else if cal.isDateInYesterday(clip.createdAt) {
                yesterday.append(clip)
            } else if clip.createdAt >= weekAgo {
                lastWeek.append(clip)
            } else {
                earlier.append(clip)
            }
        }

        return [
            Group(title: "Today", items: today),
            Group(title: "Yesterday", items: yesterday),
            Group(title: "Last Week", items: lastWeek),
            Group(title: "Earlier", items: earlier)
        ].filter { !$0.items.isEmpty }
    }
}
