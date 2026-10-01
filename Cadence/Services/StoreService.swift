import StoreKit
import SwiftUI
import OSLog

@MainActor
@Observable
final class StoreService {
    static let shared = StoreService()
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var productsLoadFailed = false
    private var updates: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.carpecadence", category: "StoreService")
    init() { updates = listenForTransactionUpdates() }
    @MainActor deinit { updates?.cancel() }

    var lifetimeProduct: Product? { products.first { $0.id == StoreKitID.proOneTime } }
    var monthlyProduct: Product? { products.first { $0.id == StoreKitID.proMonthly } }

    func loadProducts() async {
        productsLoadFailed = false
        do {
            products = try await Product.products(for: [StoreKitID.proOneTime, StoreKitID.proMonthly])
            // An EMPTY answer is a failure too, not "still loading": StoreKit
            // returns [] without throwing when the IDs aren't available (not
            // yet approved, wrong storefront, sandbox hiccup). Treating that
            // as success left the paywall on an endless "Loading…" spinner —
            // exactly what an App Reviewer would see as a broken purchase flow.
            if products.isEmpty {
                productsLoadFailed = true
                Self.log.error("StoreKit returned no products for the Pro IDs")
            }
        } catch {
            products = []
            productsLoadFailed = true
            Self.log.error("Failed to load StoreKit products: \(error, privacy: .public)")
        }
    }

    // Distinguishes the three outcomes StoreKit reports. A `Bool` collapsed
    // `.pending` into `.userCancelled`, so a family-sharing child hitting Ask
    // to Buy — or a European card triggering SCA — saw the tap do nothing at
    // all, then got Pro silently later when approval landed via
    // Transaction.updates.
    enum PurchaseOutcome {
        case purchased
        case cancelled
        case pending
    }

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            purchasedProductIDs.insert(product.id)
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            // Unknown future cases are reported as cancelled, never as
            // purchased: entitlement is granted by refreshEntitlements and
            // Transaction.updates, both of which verify.
            return .cancelled
        }
    }

    // Rebuilds the entitlement set from StoreKit's authoritative
    // `currentEntitlements`. This must run at launch: StoreKit caches nothing
    // for us across launches and `Transaction.updates` only delivers NEW
    // transactions, so without it a returning Pro user (reinstall, new device,
    // or just a cold start) reads as free.
    //
    // REBUILDS rather than unions: `currentEntitlements` omits expired
    // subscriptions and revoked purchases, so assigning the whole set is what
    // makes Pro actually lapse. Unioning would make every grant permanent for
    // the life of the process.
    func refreshEntitlements() async {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  transaction.revocationDate == nil else { continue }
            owned.insert(transaction.productID)
            await transaction.finish()
        }
        purchasedProductIDs = owned
    }

    enum RestoreOutcome {
        case restored
        case nothingToRestore
        case cancelled
        case failed
    }

    // `AppStore.sync()` first: it asks the App Store for the account's
    // transactions (prompting sign-in if needed), which is what Apple documents
    // for a Restore button. `currentEntitlements` alone only re-reads what this
    // device already has, so a restore on a new device could find nothing.
    // Returns an outcome so the button can say what happened — a restore that
    // silently does nothing reads as broken.
    func restorePurchases() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            await refreshEntitlements()
            return isPro ? .restored : .cancelled
        } catch {
            Self.log.error("AppStore.sync failed: \(error, privacy: .public)")
            await refreshEntitlements()
            return isPro ? .restored : .failed
        }
        await refreshEntitlements()
        return isPro ? .restored : .nothingToRestore
    }

    // User-facing text for a restore outcome (nil = say nothing).
    static func message(for outcome: RestoreOutcome) -> String? {
        switch outcome {
        case .restored:         return String(localized: "Your purchase has been restored. Cadence Pro is active.")
        case .nothingToRestore: return String(localized: "No previous purchases were found for this Apple Account.")
        case .failed:           return String(localized: "Couldn't reach the App Store. Check your connection and try again.")
        case .cancelled:        return nil
        }
    }

    var isPro: Bool {
        purchasedProductIDs.contains(StoreKitID.proOneTime) ||
        purchasedProductIDs.contains(StoreKitID.proMonthly)
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let safe): return safe
        }
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        // Inside an @MainActor class, Task { } inherits MainActor isolation —
        // so the insert below runs on the main thread directly, no hop needed.
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.checkVerified(result) else { continue }
                // `Transaction.updates` also delivers a transaction when it is
                // REVOKED (refund, family-sharing removal). Inserting on that
                // would re-grant Pro to a refunded user, so branch on
                // revocationDate rather than treating every update as a grant.
                if transaction.revocationDate == nil {
                    self.purchasedProductIDs.insert(transaction.productID)
                } else {
                    self.purchasedProductIDs.remove(transaction.productID)
                }
                await transaction.finish()
            }
        }
    }
}

enum StoreError: Error { case failedVerification }
