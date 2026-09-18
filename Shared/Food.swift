import Foundation

struct FoodEntry: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var kcal: Int
    var protein: Double      // grams
    var meal: Int = 0        // Meal raw value
    var amount = ""          // "150 g", "1 serving"

    init(name: String, kcal: Int, protein: Double, meal: Int = 0, amount: String = "") {
        self.name = name; self.kcal = kcal; self.protein = protein; self.meal = meal; self.amount = amount
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Food"
        kcal = (try? c.decodeIfPresent(Int.self, forKey: .kcal)) ?? 0
        protein = (try? c.decodeIfPresent(Double.self, forKey: .protein)) ?? 0
        meal = (try? c.decodeIfPresent(Int.self, forKey: .meal)) ?? 0
        amount = (try? c.decodeIfPresent(String.self, forKey: .amount)) ?? ""
    }

    /// Same food, fresh id, for adding it again.
    func copy(meal: Int) -> FoodEntry { FoodEntry(name: name, kcal: kcal, protein: protein, meal: meal, amount: amount) }
}

enum Meal: Int, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snacks
    var id: Int { rawValue }
    var name: String { ["Breakfast", "Lunch", "Dinner", "Snacks"][rawValue] }
    var icon: String { ["cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill", "fork.knife", "carrot.fill"][rawValue] }

    /// The meal you are most likely logging right now.
    static var now: Meal {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<21: .dinner
        default: .snacks
        }
    }
}

/// What the Day record carries to the cloud: the food log, water, and whether a friend may see it.
struct FoodSync: Codable {
    var e: [FoodEntry]
    var w: Int
    var s: Bool
    var g: [Int]?   // calorie, protein, water goals
}

// MARK: - Food databases

/// Nutrition per 100 g (or ml), plus the package serving when there is one.
struct FoodResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let brand: String
    let kcal100: Double
    let protein100: Double
    let servingGrams: Double?
    let servingText: String?
}

enum FoodSearch {
    /// Injected at build time from the USDA_KEY secret, so it never sits in the public repo.
    static var usdaKey: String {
        let k = Bundle.main.object(forInfoDictionaryKey: "USDAKey") as? String ?? ""
        return k.isEmpty || k.hasPrefix("$(") ? "DEMO_KEY" : k
    }

    /// Plain foods first (chicken breast, rice), then packaged brands.
    static func search(_ query: String) async throws -> [FoodResult] {
        async let plain = usda(query, types: "Foundation,SR Legacy,Survey (FNDDS)", size: 15)
        async let branded = usda(query, types: "Branded", size: 25)
        let (a, b) = try await (plain, branded)
        return a + b
    }

    private static func usda(_ query: String, types: String, size: Int) async throws -> [FoodResult] {
        var c = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        c.queryItems = [
            .init(name: "api_key", value: usdaKey),
            .init(name: "query", value: query),
            .init(name: "pageSize", value: String(size)),
            .init(name: "dataType", value: types),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]] else { return [] }
        return foods.compactMap { f in
            var kcal: Double?
            var protein = 0.0
            for n in f["foodNutrients"] as? [[String: Any]] ?? [] {
                let id = n["nutrientId"] as? Int
                let v = (n["value"] as? NSNumber)?.doubleValue ?? 0
                if id == 1008 || (kcal == nil && (id == 2047 || id == 2048)) { kcal = v }
                if id == 1003 { protein = v }
            }
            guard let kcal, let name = f["description"] as? String else { return nil }
            let unit = (f["servingSizeUnit"] as? String ?? "").lowercased()
            let serving = (f["servingSize"] as? NSNumber)?.doubleValue
            return FoodResult(
                name: name.capitalized,
                brand: (f["brandName"] as? String) ?? (f["brandOwner"] as? String) ?? "",
                kcal100: kcal,
                protein100: protein,
                servingGrams: ["g", "grm", "ml", "mlt"].contains(unit) ? serving : nil,
                servingText: (f["householdServingFullText"] as? String).map { $0.lowercased() }
            )
        }
    }

    /// Packaged food by barcode: Open Food Facts first, then USDA branded foods.
    static func barcode(_ code: String) async -> FoodResult? {
        if let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments,serving_size,serving_quantity"),
           let data = try? await URLSession.shared.data(from: url).0,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let p = json["product"] as? [String: Any],
           let n = p["nutriments"] as? [String: Any],
           let kcal = (n["energy-kcal_100g"] as? NSNumber)?.doubleValue {
            let serving = (p["serving_quantity"] as? NSNumber)?.doubleValue ?? Double(p["serving_quantity"] as? String ?? "")
            return FoodResult(
                name: (p["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Scanned food",
                brand: (p["brands"] as? String ?? "").components(separatedBy: ",").first ?? "",
                kcal100: kcal,
                protein100: (n["proteins_100g"] as? NSNumber)?.doubleValue ?? 0,
                servingGrams: serving,
                servingText: p["serving_size"] as? String
            )
        }
        return try? await usda(code, types: "Branded", size: 1).first
    }
}
