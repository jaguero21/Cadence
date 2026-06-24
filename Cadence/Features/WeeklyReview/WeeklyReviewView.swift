import SwiftUI
import SwiftData

struct WeeklyReviewView: View {
    @Query(sort: \WeeklyReview.weekStartDate, order: .reverse) private var reviews: [WeeklyReview]
    @Query private var logs: [DailyLog]
    @State private var activeSheet: ActiveSheet?

    // referenceDate anchors the 14-day window so it refreshes in place at a
    // midnight rollover rather than via a full view rebuild.
    init(referenceDate: Date = .now) {
        let day = Calendar.current.startOfDay(for: referenceDate)
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: day) ?? .distantPast
        _logs = Query(filter: #Predicate<DailyLog> { $0.date >= cutoff }, sort: \DailyLog.date, order: .reverse)
    }

    private enum ActiveSheet: Identifiable {
        case reviewFlow
        case viewingReview(WeeklyReview)

        var id: String {
            switch self {
            case .reviewFlow: "reviewFlow"
            case .viewingReview: "viewingReview"
            }
        }
    }

    private var thisWeekReview: WeeklyReview? {
        reviews.first { $0.weekStartDate.isThisWeek }
    }

    var body: some View {
        NavigationStack {
            List {
                thisWeekSection
                pastReviewsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Weekly Review")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .reviewFlow
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .reviewFlow:
                    ReviewFlowView(existingReview: thisWeekReview, logs: logs)
                case .viewingReview(let review):
                    ReviewDetailView(review: review)
                }
            }
        }
    }

    @ViewBuilder
    private var thisWeekSection: some View {
        Section("This Week") {
            if let review = thisWeekReview {
                Button {
                    if review.isComplete {
                        activeSheet = .viewingReview(review)
                    } else {
                        activeSheet = .reviewFlow
                    }
                } label: {
                    ReviewRowView(review: review)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    activeSheet = .reviewFlow
                } label: {
                    Label("Start this week's review", systemImage: "calendar.badge.plus")
                        .foregroundStyle(CadenceColor.sleepPurple)
                }
            }
        }
    }

    private var pastReviews: [WeeklyReview] {
        Array(reviews.drop(while: { $0.weekStartDate.isThisWeek }))
    }

    private var pastReviewsSection: some View {
        Section("Past Reviews") {
            ForEach(pastReviews) { review in
                Button {
                    activeSheet = .viewingReview(review)
                } label: {
                    ReviewRowView(review: review)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ReviewRowView: View {
    let review: WeeklyReview

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(review.weekLabel).font(.headline)
                Text(review.isComplete ? "Complete" : "In progress")
                    .font(.caption)
                    .foregroundStyle(review.isComplete ? CadenceColor.successGreen : CadenceColor.energyOrange)
            }
            Spacer()
            if review.overallRating > 0 {
                StarRatingDisplayView(rating: review.overallRating, font: .caption, spacing: 2)
            }
        }
    }
}

struct ReviewDetailView: View {
    let review: WeeklyReview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    WeekSummaryView(review: review)
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                }
                ForEach(review.promptResponses, id: \.section) { response in
                    Section(response.section) {
                        Text(response.response.isEmpty ? "—" : response.response)
                            .font(.body)
                            .foregroundStyle(response.response.isEmpty ? .tertiary : .primary)
                    }
                }
                if review.overallRating > 0 {
                    Section("Rating") {
                        StarRatingDisplayView(rating: review.overallRating)
                    }
                }
            }
            .navigationTitle(review.weekLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
