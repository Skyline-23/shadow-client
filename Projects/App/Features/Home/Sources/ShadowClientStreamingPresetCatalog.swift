struct ShadowClientPresetCatalog<Preset, Metadata>
where Preset: CaseIterable & Hashable & Sendable, Preset.AllCases: Collection, Metadata: Sendable {
    private let metadataByPreset: [Preset: Metadata]

    init(_ entries: [(Preset, Metadata)]) {
        var metadataByPreset: [Preset: Metadata] = [:]
        metadataByPreset.reserveCapacity(entries.count)

        for (preset, metadata) in entries {
            precondition(
                metadataByPreset.updateValue(metadata, forKey: preset) == nil,
                "Duplicate preset metadata entry for \(preset)"
            )
        }

        precondition(
            metadataByPreset.count == Array(Preset.allCases).count,
            "Preset metadata table is incomplete for \(Preset.self)"
        )

        self.metadataByPreset = metadataByPreset
    }

    func metadata(for preset: Preset) -> Metadata {
        guard let metadata = metadataByPreset[preset] else {
            preconditionFailure("Missing preset metadata entry for \(preset)")
        }

        return metadata
    }
}

struct ShadowClientStreamingResolutionPresetMetadata: Sendable {
    let width: Int
    let height: Int
    let label: String
}

struct ShadowClientStreamingFrameRatePresetMetadata: Sendable {
    let fps: Int
}

enum ShadowClientStreamingPresetCatalogs {
    static let resolution = ShadowClientPresetCatalog<ShadowClientStreamingResolutionPreset, ShadowClientStreamingResolutionPresetMetadata>([
        (.retinaAuto, .init(width: 1920, height: 1080, label: "Retina Display (Auto)")),
        (.p720, .init(width: 1280, height: 720, label: "720p")),
        (.p1080, .init(width: 1920, height: 1080, label: "1080p")),
        (.p1440, .init(width: 2560, height: 1440, label: "1440p")),
        (.p2160, .init(width: 3840, height: 2160, label: "4K")),
    ])

    static let frameRate = ShadowClientPresetCatalog<ShadowClientStreamingFrameRatePreset, ShadowClientStreamingFrameRatePresetMetadata>([
        (.fps30, .init(fps: 30)),
        (.fps60, .init(fps: 60)),
        (.fps90, .init(fps: 90)),
        (.fps120, .init(fps: 120)),
    ])
}
