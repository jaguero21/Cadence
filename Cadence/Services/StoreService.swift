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
    private init() { updates = listenForTransactionUpdates() }
    @MainActor deinit { updates?.cancel() }

    var lifetimeProduct: Product? { products.first { $0.id == StoreKitID.proOneTime } }
    var monthlyProduct: Product? { products.first { $0.id == StoreKitID.proMonthly } }

    func loadProducts() async {
        productsLoadFailed = false
        do {
            products = try await Product.products(for: [StoreKitID.proOneTime, StoreKitID.proMonthly])
        } catch {
            products = []
            productsLoadFailed = true
            Self.log.error("Failed to load StoreKit products: \(error, privacy: .public)")
        }
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            purchasedProductIDs.insert(product.id)
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
            }
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

    private func recordPurchase(_ productID: String) {
        purchasedProductIDs.insert(productID)
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached(priority: .background) {
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                await self.recordPurchase(transaction.productID)
                await transaction.finish()
            }
        }
    }
}

enum StoreError: Error { case failedVerification }
