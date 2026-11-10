import SwiftUI

struct CalendarView: View {
    let isVisible: Bool
    @Environment(IslandFeatureStore.self) private var store

    var body: some View {
        let service = store.calendar
        CalendarContent(access: service.access, event: service.nextEvent,
                        onRequestAccess: { service.requestAccess() },
                        onOpenSettings: { SystemSettingsLink.calendars.open() })
            .task(id: isVisible) { service.setVisible(isVisible) }
    }

}

/// Pure presentation of the four Calendar states, so each can be rendered without EventKit.
struct CalendarContent: View {
    @Environment(\.islandPalette) private var palette
    let access: CalendarAccess
    let event: UpcomingEvent?
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        switch access {
        case .notDetermined:
            IslandNotice(symbol: "calendar", title: "See your next event",
                         detail: "Mac Island needs access to your calendars.",
                         buttonTitle: "Allow Calendar Access", action: onRequestAccess)
        case .denied:
            IslandNotice.accessOff(symbol: "calendar.badge.exclamationmark", subject: "Calendar", openSettings: onOpenSettings)
        case .authorized:
            if let event { eventRow(event) } else {
                IslandNotice(symbol: "calendar", title: "No upcoming events",
                             detail: "Events in the next 24 hours show up here.")
            }
        }
    }

    private func eventRow(_ event: UpcomingEvent) -> some View {
        HStack(spacing: IslandSpacing.xl) {
            Circle()
                .fill(Color(.sRGB, red: event.color.red, green: event.color.green, blue: event.color.blue))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                Text(event.title)
                    .font(IslandType.title)
                    .foregroundStyle(IslandTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                TimelineView(.everyMinute) { context in
                    Text(CalendarFormatting.startText(start: event.start, now: context.date))
                        .font(IslandType.bodyDigits)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
