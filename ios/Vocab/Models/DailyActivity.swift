import Foundation

struct DailyActivity: Codable, Equatable, Sendable {
    var activityDate: CalendarDay
    var reviewsCount: Int

    init(activityDate: CalendarDay, reviewsCount: Int) {
        self.activityDate = activityDate
        self.reviewsCount = reviewsCount
    }
}
