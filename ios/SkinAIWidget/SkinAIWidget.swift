import SwiftUI
import WidgetKit

private let skinAIAppGroup = "group.com.example.flutterApplication1"

private struct SkinAIEntry: TimelineEntry {
  let date: Date
  let data: SkinAIWidgetData
}

private struct SkinAIWidgetData: Decodable {
  var style = "dailyProgress"
  var accentColor: Int64 = 0xFF168CFF
  var theme = "system"
  var compact = false
  var showProgress = true
  var showTasks = true
  var dataPeriod = "daily"
  var completedToday = 0
  var totalToday = 0
  var progressToday = 0
  var nextTask = ""
  var weeklyCompleted = 0
  var weeklyTotal = 0
  var weeklyProgress = 0
  var streak = 0
  var consistency = 0
  var weeklyDailyProgress: [Int] = []
  var labels: [String: String] = [:]
  var tasks = "[]"

  private enum CodingKeys: String, CodingKey {
    case style, accentColor, theme, compact, showProgress, showTasks, dataPeriod
    case completedToday, totalToday, progressToday, nextTask
    case weeklyCompleted, weeklyTotal, weeklyProgress, weeklyDailyProgress
    case streak, consistency, labels, tasks
  }

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    style = try values.decodeIfPresent(String.self, forKey: .style) ?? "dailyProgress"
    accentColor = try values.decodeIfPresent(Int64.self, forKey: .accentColor) ?? 0xFF168CFF
    theme = try values.decodeIfPresent(String.self, forKey: .theme) ?? "system"
    compact = try values.decodeIfPresent(Bool.self, forKey: .compact) ?? false
    showProgress = try values.decodeIfPresent(Bool.self, forKey: .showProgress) ?? true
    showTasks = try values.decodeIfPresent(Bool.self, forKey: .showTasks) ?? true
    dataPeriod = try values.decodeIfPresent(String.self, forKey: .dataPeriod) ?? "daily"
    completedToday = try values.decodeIfPresent(Int.self, forKey: .completedToday) ?? 0
    totalToday = try values.decodeIfPresent(Int.self, forKey: .totalToday) ?? 0
    progressToday = try values.decodeIfPresent(Int.self, forKey: .progressToday) ?? 0
    nextTask = try values.decodeIfPresent(String.self, forKey: .nextTask) ?? ""
    weeklyCompleted = try values.decodeIfPresent(Int.self, forKey: .weeklyCompleted) ?? 0
    weeklyTotal = try values.decodeIfPresent(Int.self, forKey: .weeklyTotal) ?? 0
    weeklyProgress = try values.decodeIfPresent(Int.self, forKey: .weeklyProgress) ?? 0
    weeklyDailyProgress = try values.decodeIfPresent([Int].self, forKey: .weeklyDailyProgress) ?? []
    streak = try values.decodeIfPresent(Int.self, forKey: .streak) ?? 0
    consistency = try values.decodeIfPresent(Int.self, forKey: .consistency) ?? 0
    labels = try values.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
    tasks = try values.decodeIfPresent(String.self, forKey: .tasks) ?? "[]"
  }

  static func read() -> SkinAIWidgetData {
    guard
      let raw = UserDefaults(suiteName: skinAIAppGroup)?.string(
        forKey: "skinai_snapshot"
      ),
      let data = raw.data(using: .utf8),
      let snapshot = try? JSONDecoder().decode(SkinAIWidgetData.self, from: data)
    else {
      return SkinAIWidgetData()
    }
    return snapshot
  }

  func label(_ key: String, _ fallback: String) -> String {
    labels[key] ?? fallback
  }

  var progress: Int {
    (dataPeriod == "weekly" ? weeklyProgress : progressToday).clamped(to: 0...100)
  }

  var accent: Color {
    Color(
      .sRGB,
      red: Double((accentColor >> 16) & 0xFF) / 255,
      green: Double((accentColor >> 8) & 0xFF) / 255,
      blue: Double(accentColor & 0xFF) / 255,
      opacity: 1
    )
  }
}

private struct SkinAIProvider: TimelineProvider {
  func placeholder(in context: Context) -> SkinAIEntry {
    SkinAIEntry(date: Date(), data: SkinAIWidgetData())
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (SkinAIEntry) -> Void
  ) {
    completion(SkinAIEntry(date: Date(), data: .read()))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<SkinAIEntry>) -> Void
  ) {
    let entry = SkinAIEntry(date: Date(), data: .read())
    completion(
      Timeline(
        entries: [entry],
        policy: .after(Date().addingTimeInterval(30 * 60))
      )
    )
  }
}

private struct SkinAIWidgetView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.widgetFamily) private var family
  let entry: SkinAIEntry

  private var isDark: Bool {
    entry.data.theme == "dark"
      || (entry.data.theme == "system" && colorScheme == .dark)
      || entry.data.style == "eveningRoutine"
  }

  private var foreground: Color {
    isDark ? Color.white : Color(red: 0.08, green: 0.12, blue: 0.20)
  }

  private var secondary: Color {
    isDark ? Color(red: 0.69, green: 0.74, blue: 0.82) : Color.secondary
  }

  private var background: Color {
    isDark ? Color(red: 0.08, green: 0.11, blue: 0.17) : Color.white
  }

  var body: some View {
    contents
      .padding(entry.data.compact ? 11 : 15)
      .background(background)
      .widgetURL(
        URL(
          string: entry.data.style == "weeklyRoutine"
            ? "skinai://routine/weekly"
            : "skinai://routine/daily"
        )
      )
  }

  @ViewBuilder
  private var contents: some View {
    Group {
      switch entry.data.style {
      case "morningRoutine":
        morning
      case "eveningRoutine":
        evening
      case "weeklyRoutine":
        weekly
      case "minimal":
        minimal
      case "statistics":
        statistics
      case "quickActions":
        actions
      default:
        daily
      }
    }
  }

  private var daily: some View {
    VStack(alignment: .leading, spacing: 10) {
      heading(entry.data.label("dailyProgress", "Today's progress"))
      Spacer(minLength: 0)
      HStack(spacing: 12) {
        ZStack {
          Circle().stroke(entry.data.accent.opacity(0.18), lineWidth: 6)
          Circle()
            .trim(from: 0, to: CGFloat(entry.data.progress) / 100)
            .stroke(
              entry.data.accent,
              style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
          Text("\(entry.data.progress)%")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(foreground)
        }
        .frame(width: 48, height: 48)
        VStack(alignment: .leading, spacing: 4) {
          Text(
            "\(entry.data.completedToday)/\(entry.data.totalToday) "
              + entry.data.label("complete", "complete")
          )
          .font(.subheadline.weight(.semibold))
          Text(
            entry.data.showTasks
              ? entry.data.nextTask
              : entry.data.label("today", "Today")
          )
          .font(.caption)
          .lineLimit(1)
          .foregroundColor(secondary)
        }
        .foregroundColor(foreground)
      }
    }
  }

  private var morning: some View {
    VStack(alignment: .leading, spacing: 8) {
      heading(entry.data.label("morning", "Morning routine"))
      if entry.data.showTasks {
        Text(entry.data.nextTask.isEmpty ? entry.data.label("noTask", "No tasks today") : entry.data.nextTask)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(foreground)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      progressLine
    }
  }

  private var evening: some View {
    VStack(alignment: .leading, spacing: 8) {
      heading(entry.data.label("evening", "Evening routine"))
      Spacer(minLength: 0)
      Image(systemName: "moon.stars.fill")
        .font(.title2)
        .foregroundColor(entry.data.accent)
      Text(entry.data.label("eveningHint", "A few calm steps for tonight"))
        .font(.subheadline.weight(.semibold))
        .foregroundColor(foreground)
        .lineLimit(2)
    }
  }

  private var weekly: some View {
    VStack(alignment: .leading, spacing: 8) {
      heading(entry.data.label("weekly", "Your week"))
      Spacer(minLength: 0)
      HStack(alignment: .bottom, spacing: 5) {
        ForEach(0..<7, id: \.self) { index in
          let progress = index < entry.data.weeklyDailyProgress.count
            ? entry.data.weeklyDailyProgress[index].clamped(to: 0...100)
            : 0
          VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
              Capsule().fill(entry.data.accent.opacity(0.18))
              GeometryReader { proxy in
                Capsule()
                  .fill(entry.data.accent)
                  .frame(height: proxy.size.height * CGFloat(progress) / 100)
              }
            }
            Text(["M", "T", "W", "T", "F", "S", "S"][index])
              .font(.system(size: 8, weight: .medium))
              .foregroundColor(secondary)
          }
        }
      }
      .frame(height: family == .systemSmall ? 52 : 72)
      Text(
        "\(entry.data.weeklyCompleted)/\(entry.data.weeklyTotal) "
          + entry.data.label("complete", "complete")
      )
      .font(.caption.weight(.semibold))
      .foregroundColor(foreground)
    }
  }

  private var minimal: some View {
    VStack(spacing: 8) {
      Text("\(entry.data.progress)%")
        .font(.system(size: 42, weight: .bold, design: .rounded))
        .foregroundColor(entry.data.accent)
      Text(entry.data.label("today", "Today"))
        .font(.caption.weight(.medium))
        .foregroundColor(secondary)
      if entry.data.showProgress {
        progressLine
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var statistics: some View {
    VStack(alignment: .leading, spacing: 9) {
      heading(entry.data.label("statistics", "Streak statistics"))
      Spacer(minLength: 0)
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text("\(entry.data.streak)")
          .font(.system(size: 36, weight: .bold, design: .rounded))
          .foregroundColor(entry.data.accent)
        Text(entry.data.label("dayStreak", "day streak"))
          .font(.caption)
          .foregroundColor(secondary)
      }
      if entry.data.showProgress {
        progressLine
      }
      Text(
        "\(entry.data.consistency)% "
          + entry.data.label("consistency", "consistency")
      )
      .font(.caption)
      .foregroundColor(foreground)
    }
  }

  private var actions: some View {
    VStack(alignment: .leading, spacing: 10) {
      heading(entry.data.label("quickActions", "Quick actions"))
      Spacer(minLength: 0)
      HStack(spacing: 10) {
        action("checklist", "skinai://routine/daily")
        action("calendar", "skinai://routine/weekly")
        action("viewfinder", "skinai://scanner")
      }
    }
  }

  private var progressLine: some View {
    VStack(alignment: .leading, spacing: 5) {
      ProgressView(value: Double(entry.data.progress), total: 100)
        .tint(entry.data.accent)
      if entry.data.showProgress {
        Text("\(entry.data.progress)%")
          .font(.caption2.weight(.semibold))
          .foregroundColor(secondary)
      }
    }
  }

  private func heading(_ title: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "sparkles")
        .foregroundColor(entry.data.accent)
      Text(title)
        .font(.subheadline.weight(.bold))
        .foregroundColor(foreground)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }

  private func action(_ symbol: String, _ link: String) -> some View {
    Link(destination: URL(string: link)!) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(entry.data.accent)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(entry.data.accent.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
  }
}

private struct SkinAIWidget: Widget {
  static let kind = "SkinAIWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: SkinAIProvider()) { entry in
      SkinAIWidgetView(entry: entry)
    }
    .configurationDisplayName("SkinAI")
    .description("Your skincare routine and progress at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct SkinAIWidgetBundle: WidgetBundle {
  var body: some Widget {
    SkinAIWidget()
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
