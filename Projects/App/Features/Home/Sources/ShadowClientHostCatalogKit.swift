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
        if let localizedName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localizedName.isEmpty
        {
            let normalizedName = localizedName.lowercased()
            values.insert(normalizedName)
            values.insert("\(normalizedName).local")
        }
        return values
    }
}
