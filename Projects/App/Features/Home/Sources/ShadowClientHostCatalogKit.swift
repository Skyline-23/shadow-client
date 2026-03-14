import Foundation

enum ShadowClientHostCatalogKit {
    static func refreshCandidates(
        autoFindHosts: Bool,
        discoveredHosts: [String],
        cachedHosts: [String],
        manualHost: String?
    ) -> [String] {
        let candidates = (autoFindHosts ? discoveredHosts : []) + cachedHosts
        return ShadowClientRemoteHostCandidateFilter.filteredCandidates(
            discoveredHosts: candidates,
            manualHost: manualHost,
            selfHostNames: currentMachineHostNames()
        )
    }

    private static func currentMachineHostNames() -> Set<String> {
        var values = Set<String>()
        let localizedName = ProcessInfo.processInfo.hostName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !localizedName.isEmpty {
            let normalizedName = localizedName.lowercased()
            values.insert(normalizedName)
            values.insert("\(normalizedName).local")
        }
        return values
    }
}
