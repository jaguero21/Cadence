import SwiftUI
import StoreKit

struct ProPaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var pendingMessage: String?

    // String(localized:) at the literal, not bare strings: these are read back
    // out as tuple members and rendered with Text(feature.title), which takes
    // the non-localizing StringProtocol overload — as bare literals the whole
    // paywall stayed English in every language.
    private let features: [(icon: String, title: String, detail: String)] = [
        ("sparkles",
         String(localized: "Pattern Insights"),
         String(localized: "Correlation detection across sleep, mood, stress, and symptoms.")),
        ("doc.richtext.fill",
         String(localized: "PDF Export"),
         String(localized: "Doctor-ready reports and personal summaries.")),
        ("chart.line.uptrend.xyaxis",
         String(localized: "90-Day Trends"),
         String(localized: "Full trend history across all your health metrics.")),
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
            .alert("Waiting for Approval", isPresented: .init(
                get: { pendingMessage != nil },
                set: { if !$0 { pendingMessage = nil } }
            )) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(pendingMessage ?? "")
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
            // Keyed by icon, not title: the titles are localized now, so they
            // are the wrong thing to hang view identity on.
            ForEach(features, id: \.icon) { feature in
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
                if feature.icon != features.last?.icon {
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

            if store.productsLoadFailed {
                VStack(spacing: 10) {
                    Text("Couldn't load products. Check your connection.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await store.loadProducts() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if store.products.isEmpty {
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

    // App Review Guideline 3.1.2 requires functional Terms of Use and Privacy
    // Policy links reachable from the purchase screen itself — having them only
    // in Settings → About does not satisfy it and is a routine rejection. Keep
    // both links on this screen for as long as it sells a subscription.
    private var legal: some View {
        VStack(spacing: 10) {
            Text("Payment charged to your Apple ID at purchase confirmation. Subscriptions auto-renew unless cancelled at least 24 hours before the renewal date. Manage or cancel in your Apple ID settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                if let terms = CadenceURL.terms {
                    Link("Terms of Use", destination: terms)
                }
                if let privacy = CadenceURL.privacyPolicy {
                    Link("Privacy Policy", destination: privacy)
                }
            }
            .font(.caption.weight(.medium))
            .tint(CadenceColor.accent)
        }
    }

    // MARK: - Actions

    private func buy(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await store.purchase(product) {
            case .purchased:
                dismiss()
            case .pending:
                // Ask to Buy or a bank approval step. Say so — otherwise the
                // tap looks like it did nothing, and Pro appears later with no
                // explanation once approval lands.
                pendingMessage = String(localized: "Your purchase needs approval before it can finish. Cadence Pro will unlock automatically once it's approved.")
            case .cancelled:
                break
            }
        } catch {
            errorMessage = String(localized: "Something went wrong. Please try again.")
        }
    }
}
