import Foundation

/// Volgorde van kolommen bij het slepen van een kolom.
public enum ColumnOrdering {
    /// De sleutels met `key` op positie `index` van de overige sleutels (de kolom zelf niet meegeteld).
    /// Een onbekende sleutel laat de volgorde ongewijzigd; `index` wordt binnen het bereik gehouden.
    public static func moving(_ keys: [String], key: String, toIndex index: Int) -> [String] {
        guard let from = keys.firstIndex(of: key) else { return keys }
        var result = keys
        result.remove(at: from)
        result.insert(key, at: min(max(index, 0), result.count))
        return result
    }

    /// Positie (onder de overige kolommen) waar een gesleepte kolom terechtkomt, op basis van het midden van de
    /// gesleepte kolom en de middens van de andere kolommen, van links naar rechts.
    public static func insertionIndex(draggedMidX: Double, otherMidXs: [Double]) -> Int {
        otherMidXs.filter { $0 < draggedMidX }.count
    }
}
