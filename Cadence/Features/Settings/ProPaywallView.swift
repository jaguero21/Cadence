import SwiftUI
import StoreKit

struct ProPaywallView: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var errorMessage: String?

    private let features: [(icon: String, title: String, detail: String)] = [
        ("sparkles",              "Pattern Insights",    "Correlation detection across sleep, mood, stress, and symptoms."),
        ("doc.richtext.fill",     "PDF Export",          "Doctor-ready reports and personal summaries."),
        ("chart.line.uptrend.xyaxis", "90-Day Trends",   "Full trend history across all your health metrics."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    featureList
                    productButtons
                    restoreButton
                    legal
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(CadenceColor.background.ignoresSafeArea())
            .navigationTitle("Cadence Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await store.loadProducts() }
            .alert("Purchase Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 56))
                .foregroundStyle(CadenceColor.sleepPurple)
                .padding(.top, 8)

            Text("Unlock the full\nCadence experience")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("One purchase. All features. Forever — or monthly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(features, id: \.title) { feature in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: feature.icon)
                        .font(.title3)
                        .foregroundStyle(CadenceColor.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title).font(.subheadline.bold())
                        Text(feature.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                if feature.title != features.last?.title {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .cadenceCard()
    }

    private var productButtons: some View {
        VStack(spacing: 12) {
            if let lifetime = store.lifetimeProduct {
                purchaseButton(
                    product: lifetime,
                    label: "Buy Lifetime Access",
                    sublabel: lifetime.displayPrice,
                    color: CadenceColor.accent,
                    prominent: true
                )
            }

            if let monthly = store.monthlyProduct {
                purchaseButton(
                    product: monthly,
                    label: "Subscribe Monthly",
                    sublabel: "\(monthly.displayPrice) / month",
                    color: CadenceColor.sleepPurple,
                    prominent: false
                )
            }

            if store.products.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private func purchaseButton(product: Product, label: String, sublabel: String, color: Color, prominent: Bool) -> some View {
        Button {
            Task { await buy(product) }
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.body.bold())
                Text(sublabel).font(.caption).opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(prominent ? color : color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(prominent ? .white : color)
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task {
                isPurchasing = true
                await store.restorePurchases()
                isPurchasing = false
                if store.isPro { dismiss() }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .disabled(isPurchasing)
    }

    private var legal: some View {
        Text("Payment charged to your Apple ID at purchase confirmation. Subscriptions auto-renew unless cancelled at least 24 hours before the renewal date.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func buy(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let purchased = try await store.purchase(product)
            if purchased { dismiss() }
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }
}
