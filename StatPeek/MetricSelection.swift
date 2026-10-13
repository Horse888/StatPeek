import Foundation

final class MetricSelection {
    private let defaults: UserDefaults
    private let key = "visibleMetrics"
    private(set) var selected: Set<Metric>
    private var savedColors: [String: String]

    init(defaults: UserDefaults = .standard, legacyDefaults: [String: Any]? = nil) {
        self.defaults = defaults
        savedColors = defaults.dictionary(forKey: "metricColors") as? [String: String]
            ?? legacyDefaults?["metricColors"] as? [String: String] ?? [:]
        if let saved = defaults.stringArray(forKey: key) ?? legacyDefaults?[key] as? [String] {
            selected = Set(saved.compactMap(Metric.init(rawValue:)))
        } else {
            selected = Set(Metric.allCases)
        }
        // Import the prototype's preferences once without overwriting current choices.
        if defaults.object(forKey: key) == nil, legacyDefaults?[key] != nil {
            defaults.set(Metric.allCases.filter { selected.contains($0) }.map(\.rawValue), forKey: key)
        }
        if defaults.object(forKey: "metricColors") == nil, !savedColors.isEmpty {
            defaults.set(savedColors, forKey: "metricColors")
        }
    }

    func toggle(_ metric: Metric) {
        if selected.contains(metric) { selected.remove(metric) }
        else { selected.insert(metric) }
        defaults.set(Metric.allCases.filter { selected.contains($0) }.map(\.rawValue), forKey: key)
    }

    func color(for metric: Metric) -> MetricColor {
        savedColors[metric.rawValue].flatMap(MetricColor.init(rawValue:))
            ?? MetricColor.defaultColor(for: metric)
    }

    func setColor(_ color: MetricColor, for metric: Metric) {
        guard let validated = MetricColor(rawValue: color.rawValue) else { return }
        savedColors[metric.rawValue] = validated.rawValue
        defaults.set(savedColors, forKey: "metricColors")
    }
}
