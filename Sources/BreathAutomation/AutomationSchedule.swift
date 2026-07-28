import Foundation

enum AutomationScheduleEvaluator {
    static func nextOccurrences(
        for trigger: AutomationTrigger,
        anchor: Date?,
        after start: Date,
        through end: Date? = nil,
        timeZone: TimeZone,
        count: Int
    ) throws -> [Date] {
        guard count > 0 else { return [] }
        var occurrences: [Date] = []
        var cursor = start
        while occurrences.count < count,
              let next = try nextOccurrence(
                  for: trigger,
                  anchor: anchor,
                  after: cursor,
                  timeZone: timeZone
              )
        {
            if let end, next > end { break }
            occurrences.append(next)
            cursor = next
        }
        return occurrences
    }

    static func validate(_ trigger: AutomationTrigger) throws {
        switch trigger {
        case .cron(let expression):
            _ = try CronExpression(expression)
        default:
            break
        }
    }

    static func missingLocalOccurrences(
        for trigger: AutomationTrigger,
        after start: Date,
        through end: Date,
        timeZone: TimeZone
    ) throws -> [Date] {
        guard end > start else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard var day = calendar.dateInterval(of: .day, for: start)?.start
        else {
            return []
        }
        var missing: [Date] = []
        while day <= end {
            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else {
                break
            }
            let startOffset = timeZone.secondsFromGMT(for: day)
            let endOffset = timeZone.secondsFromGMT(
                for: nextDay.addingTimeInterval(-1)
            )
            if endOffset > startOffset {
                let dayComponents = calendar.dateComponents(
                    [.year, .month, .day, .weekday],
                    from: day
                )
                for hour in 0..<24 {
                    for minute in 0..<60 where try localComponentsMatch(
                        trigger,
                        day: dayComponents,
                        hour: hour,
                        minute: minute
                    ) {
                        var components = dayComponents
                        components.hour = hour
                        components.minute = minute
                        components.second = 0
                        guard let represented = calendar.date(from: components)
                        else {
                            continue
                        }
                        let roundTrip = calendar.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: represented
                        )
                        let isMissing =
                            roundTrip.year != components.year
                                || roundTrip.month != components.month
                                || roundTrip.day != components.day
                                || roundTrip.hour != hour
                                || roundTrip.minute != minute
                        if isMissing,
                           represented > start,
                           represented <= end
                        {
                            missing.append(represented)
                        }
                    }
                }
            }
            day = nextDay
        }
        return missing.sorted()
    }

    private static func localComponentsMatch(
        _ trigger: AutomationTrigger,
        day: DateComponents,
        hour: Int,
        minute: Int
    ) throws -> Bool {
        switch trigger {
        case .daily(let scheduledHour, let scheduledMinute):
            return hour == scheduledHour && minute == scheduledMinute
        case .weekly(let weekdays, let scheduledHour, let scheduledMinute):
            return weekdays.contains(day.weekday ?? 0)
                && hour == scheduledHour
                && minute == scheduledMinute
        case .cron(let expression):
            return try CronExpression(expression).matches(
                month: day.month ?? 0,
                day: day.day ?? 0,
                weekday: (day.weekday ?? 1) - 1,
                hour: hour,
                minute: minute
            )
        default:
            return false
        }
    }

    private static func nextOccurrence(
        for trigger: AutomationTrigger,
        anchor: Date?,
        after date: Date,
        timeZone: TimeZone
    ) throws -> Date? {
        switch trigger {
        case .manual, .external:
            return nil
        case .once(let scheduledAt):
            return scheduledAt > date ? scheduledAt : nil
        case .daily(let hour, let minute):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute, second: 0),
                matchingPolicy: .strict,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        case .weekly(let weekdays, let hour, let minute):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return weekdays.compactMap { weekday in
                calendar.nextDate(
                    after: date,
                    matching: DateComponents(
                        hour: hour,
                        minute: minute,
                        second: 0,
                        weekday: weekday
                    ),
                    matchingPolicy: .strict,
                    repeatedTimePolicy: .first,
                    direction: .forward
                )
            }.min()
        case .interval(let interval):
            guard let anchor else { return nil }
            if date < anchor {
                return anchor.addingTimeInterval(interval.duration)
            }
            let elapsed = date.timeIntervalSince(anchor)
            let completedIntervals = floor(elapsed / interval.duration)
            return anchor.addingTimeInterval(
                (completedIntervals + 1) * interval.duration
            )
        case .cron(let rawExpression):
            return try CronExpression(rawExpression).next(
                after: date,
                timeZone: timeZone
            )
        }
    }
}

private struct CronExpression {
    private let minute: CronField
    private let hour: CronField
    private let dayOfMonth: CronField
    private let month: CronField
    private let weekday: CronField

    init(_ expression: String) throws {
        let fields = expression.split(whereSeparator: \.isWhitespace)
        guard fields.count == 5, !expression.contains("@") else {
            throw AutomationError.invalidTrigger
        }
        minute = try CronField(String(fields[0]), range: 0...59)
        hour = try CronField(String(fields[1]), range: 0...23)
        dayOfMonth = try CronField(String(fields[2]), range: 1...31)
        month = try CronField(String(fields[3]), range: 1...12)
        weekday = try CronField(
            String(fields[4]),
            range: 0...7,
            normalize: { $0 == 7 ? 0 : $0 }
        )
    }

    func next(after date: Date, timeZone: TimeZone) throws -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let previousLocalMinute = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        components.second = 0
        guard let floored = calendar.date(from: components),
              var candidate = calendar.date(
                  byAdding: .minute,
                  value: floored > date ? 0 : 1,
                  to: floored
              )
        else {
            return nil
        }

        let searchLimit = 5 * 366 * 24 * 60
        for _ in 0..<searchLimit {
            let values = calendar.dateComponents(
                [.year, .minute, .hour, .day, .month, .weekday],
                from: candidate
            )
            guard let yearValue = values.year,
                  let minuteValue = values.minute,
                  let hourValue = values.hour,
                  let dayValue = values.day,
                  let monthValue = values.month,
                  let calendarWeekday = values.weekday
            else {
                throw AutomationError.invalidTrigger
            }
            let weekdayValue = calendarWeekday - 1
            let dayMatches = dayOfMonth.contains(dayValue)
            let weekdayMatches = weekday.contains(weekdayValue)
            let dateMatches: Bool
            if dayOfMonth.isWildcard && weekday.isWildcard {
                dateMatches = true
            } else if dayOfMonth.isWildcard {
                dateMatches = weekdayMatches
            } else if weekday.isWildcard {
                dateMatches = dayMatches
            } else {
                dateMatches = dayMatches || weekdayMatches
            }
            let repeatsPreviousLocalMinute =
                previousLocalMinute.year == yearValue
                    && previousLocalMinute.month == monthValue
                    && previousLocalMinute.day == dayValue
                    && previousLocalMinute.hour == hourValue
                    && previousLocalMinute.minute == minuteValue
            if !repeatsPreviousLocalMinute,
               minute.contains(minuteValue),
               hour.contains(hourValue),
               month.contains(monthValue),
               dateMatches
            {
                return candidate
            }
            guard let next = calendar.date(
                byAdding: .minute,
                value: 1,
                to: candidate
            ) else {
                return nil
            }
            candidate = next
        }
        return nil
    }

    func matches(
        month monthValue: Int,
        day dayValue: Int,
        weekday weekdayValue: Int,
        hour hourValue: Int,
        minute minuteValue: Int
    ) -> Bool {
        let dayMatches = dayOfMonth.contains(dayValue)
        let weekdayMatches = weekday.contains(weekdayValue)
        let dateMatches: Bool
        if dayOfMonth.isWildcard && weekday.isWildcard {
            dateMatches = true
        } else if dayOfMonth.isWildcard {
            dateMatches = weekdayMatches
        } else if weekday.isWildcard {
            dateMatches = dayMatches
        } else {
            dateMatches = dayMatches || weekdayMatches
        }
        return minute.contains(minuteValue)
            && hour.contains(hourValue)
            && month.contains(monthValue)
            && dateMatches
    }
}

private struct CronField {
    let values: Set<Int>
    let isWildcard: Bool

    init(
        _ raw: String,
        range: ClosedRange<Int>,
        normalize: (Int) -> Int = { $0 }
    ) throws {
        isWildcard = raw == "*" || raw.hasPrefix("*/")
        var parsed: Set<Int> = []
        for part in raw.split(separator: ",", omittingEmptySubsequences: false) {
            guard !part.isEmpty else { throw AutomationError.invalidTrigger }
            let stepParts = part.split(separator: "/", omittingEmptySubsequences: false)
            guard stepParts.count <= 2 else { throw AutomationError.invalidTrigger }
            let step: Int
            if stepParts.count == 2 {
                guard let parsedStep = Int(stepParts[1]), parsedStep > 0 else {
                    throw AutomationError.invalidTrigger
                }
                step = parsedStep
            } else {
                step = 1
            }
            let base = String(stepParts[0])
            let selectedRange: ClosedRange<Int>
            if base == "*" {
                selectedRange = range
            } else if base.contains("-") {
                let bounds = base.split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2,
                      let lower = Int(bounds[0]),
                      let upper = Int(bounds[1]),
                      range.contains(lower),
                      range.contains(upper),
                      lower <= upper
                else {
                    throw AutomationError.invalidTrigger
                }
                selectedRange = lower...upper
            } else {
                guard let value = Int(base), range.contains(value) else {
                    throw AutomationError.invalidTrigger
                }
                selectedRange = value...value
            }
            for value in selectedRange where (value - selectedRange.lowerBound) % step == 0 {
                parsed.insert(normalize(value))
            }
        }
        guard !parsed.isEmpty else { throw AutomationError.invalidTrigger }
        values = parsed
    }

    func contains(_ value: Int) -> Bool {
        values.contains(value)
    }
}
