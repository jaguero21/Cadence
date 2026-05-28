import SwiftUI
import SwiftData

struct WeeklyReviewView: View {
    @Query(sort: \WeeklyReview.weekStartDate, order: .reverse) private var reviews: [WeeklyReview]
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @State private var showingFlow = false
    @State private var selectedReview: WeeklyReview?

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
                        showingFlow = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingFlow) {
                ReviewFlowView(existingReview: thisWeekReview, logs: logs)
            }
            .sheet(item: $selectedReview) { review in
                ReviewDetailView(review: review)
            }
        }
    }

    @ViewBuilder
    private var thisWeekSection: some View {
        Section("This Week") {
            if let review = thisWeekReview {
                Button {
                    if review.isComplete {
                        selectedReview = review
                    } else {
                        showingFlow = true
                    }
                } label: {
                    ReviewRowView(review: review)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showingFlow = true
                } label: {
                    Label("Start this week's review", systemImage: "calendar.badge.plus")
                        .foregroundStyle(CadenceColor.sleepPurple)
                }
            }
        }
    }

    private var pastReviewsSection: some View {
        Section("Past Reviews") {
            ForEach(reviews.filter { !$0.weekStartDate.isThisWeek }) { review in
                Button {
                    selectedReview = review
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
