import Foundation

/// Plaatst overlappende afspraken naast elkaar.
public enum EventLayout {
    public struct Slot: Equatable {
        public var lane: Int
        public var laneCount: Int
    }

    /// - Returns: per interval (zelfde volgorde als invoer) de baan en het aantal banen in zijn cluster.
    public static func assign(_ intervals: [(start: Date, end: Date)]) -> [Slot] {
        let order = intervals.indices.sorted {
            (intervals[$0].start, intervals[$0].end) < (intervals[$1].start, intervals[$1].end)
        }

        var slots = [Slot](repeating: Slot(lane: 0, laneCount: 1), count: intervals.count)
        var cluster: [Int] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for index in cluster { slots[index].laneCount = laneEnds.count }
            cluster.removeAll()
            laneEnds.removeAll()
        }

        for index in order {
            let item = intervals[index]
            if !cluster.isEmpty && item.start >= clusterEnd { closeCluster() }

            if let lane = laneEnds.firstIndex(where: { $0 <= item.start }) {
                laneEnds[lane] = item.end
                slots[index].lane = lane
            } else {
                laneEnds.append(item.end)
                slots[index].lane = laneEnds.count - 1
            }
            cluster.append(index)
            clusterEnd = cluster.count == 1 ? item.end : max(clusterEnd, item.end)
        }
        closeCluster()
        return slots
    }
}
