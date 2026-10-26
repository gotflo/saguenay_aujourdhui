import SwiftUI
import UIKit
import WidgetKit

// Widget « Aujourd'hui ».
//
// L'app Flutter écrit dans le groupe d'apps la suite des sept prochains jours,
// une entrée par changement. Chaque entrée devient une entrée de timeline
// WidgetKit : iOS affiche la bonne au bon moment sans réveiller l'app. Passé
// la fin de la suite, le widget demande d'ouvrir l'app plutôt que d'afficher
// une information périmée.

private let appGroup = "group.ca.saguenayaujourdhui"

struct TodayEntry: TimelineEntry {
    let date: Date
    let label: String
    let title: String
    let detail: String
    let kind: String?
    let critical: Bool
    let place: String
    let second: String?
    let upcoming: [(String, String)]

    static let sample = TodayEntry(
        date: Date(),
        label: "Cette nuit",
        title: "Pas d’auto dans la rue cette nuit",
        detail: "Interdit de minuit à 7 h.",
        kind: "parking",
        critical: false,
        place: "Racine Est",
        second: "Collecte · Ordures",
        upcoming: [("Demain 19 h", "Sors le bac bleu")]
    )

    static func stale(at date: Date, place: String) -> TodayEntry {
        TodayEntry(
            date: date,
            label: "À mettre à jour",
            title: "Ouvre l’app un instant",
            detail: "Ton widget a besoin des infos de la semaine qui vient.",
            kind: nil,
            critical: false,
            place: place,
            second: nil,
            upcoming: []
        )
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let entries = loadEntries()
        let now = Date()
        completion(entries.last(where: { $0.date <= now }) ?? entries.first ?? .sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entries = loadEntries()
        completion(Timeline(entries: entries.isEmpty ? [.sample] : entries, policy: .never))
    }

    private func loadEntries() -> [TodayEntry] {
        let defaults = UserDefaults(suiteName: appGroup)
        let place = defaults?.string(forKey: "place") ?? ""
        guard
            let raw = defaults?.string(forKey: "timeline"),
            let data = raw.data(using: .utf8),
            let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        let dated: [(Date, [String: Any])] = items.compactMap { item in
            guard let at = (item["at"] as? NSNumber)?.doubleValue else { return nil }
            return (Date(timeIntervalSince1970: at / 1000), item)
        }
        var entries: [TodayEntry] = []
        for (index, (date, item)) in dated.enumerated() {
            entries.append(
                TodayEntry(
                    date: date,
                    label: item["label"] as? String ?? "Aujourd’hui",
                    title: item["title"] as? String ?? "",
                    detail: item["body"] as? String ?? "",
                    kind: item["kind"] as? String,
                    critical: item["critical"] as? Bool ?? false,
                    place: place,
                    second: item["second"] as? String,
                    upcoming: upcoming(after: index, in: dated, from: date, current: item["title"] as? String)
                )
            )
        }
        if let raw = defaults?.string(forKey: "until"), let until = Double(raw) {
            entries.append(.stale(at: Date(timeIntervalSince1970: until / 1000), place: place))
        }
        return entries
    }

    /// Les trois prochains changements qui comptent dans les 36 heures, sans les bus.
    private func upcoming(
        after index: Int,
        in dated: [(Date, [String: Any])],
        from date: Date,
        current: String?
    ) -> [(String, String)] {
        var out: [(String, String)] = []
        var seen: Set<String> = [current ?? ""]
        for (at, item) in dated.dropFirst(index + 1) {
            if at.timeIntervalSince(date) > 36 * 3600 { break }
            guard let kind = item["kind"] as? String, kind != "bus",
                  let title = item["title"] as? String, !seen.contains(title)
            else { continue }
            seen.insert(title)
            out.append((moment(at, from: date), title))
            if out.count == 3 { break }
        }
        return out
    }

    /// « 21 h », « Demain 7 h », « mar. 7 h 46 ».
    private func moment(_ at: Date, from now: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: at)
        let minute = calendar.component(.minute, from: at)
        let clock = minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: at)
        ).day ?? 0
        let names = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
        let day = days == 0 ? "" : days == 1 ? "Demain" : names[calendar.component(.weekday, from: at) - 1]
        // À minuit, le jour suffit : « mar. », pas « mar. 0 h ».
        if hour == 0 && minute == 0 && !day.isEmpty { return day }
        return day.isEmpty ? clock : "\(day) \(clock)"
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        content
            .accessibilityElement(children: .combine)
            .widgetURL(link)
            .widgetBackground(family)
    }

    @ViewBuilder private var content: some View {
        if family == .accessoryRectangular {
            // Écran verrouillé : l'essentiel, dans la teinte choisie par iOS.
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label).font(.caption2.bold()).widgetAccentable()
                Text(entry.title).font(.headline).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            home
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 3) {
            if family != .systemSmall {
                HStack {
                    Text("Aujourd’hui").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(entry.label).font(.caption.bold()).foregroundStyle(labelColor).widgetAccentable().padding(.top, 6)
            Text(entry.title).font(.headline).lineLimit(family == .systemSmall ? 3 : 2)
            if family != .systemSmall {
                Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if family == .systemLarge && !entry.upcoming.isEmpty {
                Text("À venir").font(.caption2.bold()).foregroundStyle(.secondary).padding(.top, 10)
                ForEach(Array(entry.upcoming.enumerated()), id: \.offset) { _, next in
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.0).font(.caption).foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
                        Text(next.1).font(.caption).lineLimit(1)
                    }
                }
            }
            if let second = entry.second, family != .systemSmall {
                Spacer(minLength: 4)
                Text(second).font(.caption.bold()).lineLimit(1)
            }
        }
    }

    /// Ouvre la fiche de l'information affichée. `homeWidget` permet au paquet
    /// home_widget de reconnaître un lancement depuis le widget.
    private var link: URL? {
        guard let kind = entry.kind else { return URL(string: "aujourdhui://detail?homeWidget") }
        return URL(string: "aujourdhui://detail/\(kind)?homeWidget")
    }

    private var labelColor: Color {
        if entry.critical { return Color(red: 0.77, green: 0.19, blue: 0.17) }
        switch entry.kind {
        case "water": return Color(red: 0.04, green: 0.43, blue: 0.61)
        case "weather": return Color(red: 0.31, green: 0.42, blue: 0.52)
        case "power": return Color(red: 0.72, green: 0.20, blue: 0.42)
        case "parking": return Color(red: 0.70, green: 0.34, blue: 0.0)
        case "collection": return Color(red: 0.08, green: 0.48, blue: 0.29)
        case "bus": return Color(red: 0.18, green: 0.37, blue: 0.82)
        case "roadwork": return Color(red: 0.56, green: 0.37, blue: 0.06)
        default: return .secondary
        }
    }
}

private extension View {
    /// `containerBackground` n'existe qu'à partir d'iOS 17. Sur l'écran
    /// verrouillé, pas de fond : iOS pose le sien.
    @ViewBuilder func widgetBackground(_ family: WidgetFamily) -> some View {
        let lockScreen = family == .accessoryRectangular
        if #available(iOS 17.0, *) {
            if lockScreen {
                containerBackground(.clear, for: .widget)
            } else {
                containerBackground(for: .widget) { SoftGlass() }
            }
        } else if lockScreen {
            self
        } else {
            padding().background(SoftGlass())
        }
    }
}

/// Le fond de l'app : la couleur du système et, dans un coin, un halo du
/// jaune de Saguenay Aujourd'hui. Avec iOS 26, le mode « verre » du système
/// prend le relais.
private struct SoftGlass: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
            RadialGradient(
                colors: [Color(red: 1, green: 0.82, blue: 0.17).opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 220
            )
        }
    }
}

@main
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Aujourd’hui")
        .description("Ce qui te concerne aujourd’hui à Saguenay.")
        .supportedFamilies(families)
    }

    private var families: [WidgetFamily] {
        if #available(iOS 16.0, *) {
            return [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]
        }
        return [.systemSmall, .systemMedium, .systemLarge]
    }
}
