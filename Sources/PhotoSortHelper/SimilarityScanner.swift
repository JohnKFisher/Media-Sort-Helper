import CoreImage
import Foundation
import Photos
import Vision

final class SimilarityScanner: @unchecked Sendable {
    private struct ImageStats {
        let meanLuma: Double
        let stdLuma: Double
        let colorfulness: Double
    }

    private let libraryService: PhotoLibraryService
    private let ciContext = CIContext()
    private lazy var faceDetector: CIDetector? = {
        CIDetector(
            ofType: CIDetectorTypeFace,
            context: ciContext,
            options: [
                CIDetectorAccuracy: CIDetectorAccuracyLow,
                CIDetectorSmile: true,
                CIDetectorEyeBlink: true
            ]
        )
    }()

    init(libraryService: PhotoLibraryService) {
        self.libraryService = libraryService
    }

    func scan(
        settings: ScanSettings,
        progress: @escaping @MainActor (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let assets = try libraryService.fetchAssets(settings: settings)

        if assets.isEmpty {
            await progress(.init(fractionCompleted: 1.0, message: "Not enough photos in scope to compare."))
            return ScanResult(
                groups: [],
                bestAssetByGroupID: [:],
                bestShotScoresByAssetID: [:],
                assetLookup: Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) }),
                scannedAssetCount: assets.count,
                temporalClusterCount: 0
            )
        }

        await progress(.init(fractionCompleted: 0.05, message: "Building time-near candidate groups..."))

        let temporalClusters = buildTemporalClusters(
            from: assets,
            maxGapSeconds: settings.maxTimeGapSeconds
        )

        var featurePrintCache: [String: VNFeaturePrintObservation] = [:]
        var outputGroups: [ReviewGroup] = []
        var assetLookup: [String: PHAsset] = [:]
        assets.forEach { assetLookup[$0.localIdentifier] = $0 }

        let clusterCount = max(1, temporalClusters.count)

        for (clusterIndex, cluster) in temporalClusters.enumerated() {
            try Task.checkCancellation()

            let fraction = 0.10 + (Double(clusterIndex) / Double(clusterCount)) * 0.80
            await progress(
                .init(
                    fractionCompleted: min(0.92, fraction),
                    message: "Analyzing group \(clusterIndex + 1) of \(clusterCount)..."
                )
            )

            if cluster.count == 1, let onlyAsset = cluster.first {
                let onlyDate = onlyAsset.creationDate ?? .distantPast
                outputGroups.append(
                    ReviewGroup(
                        assetIDs: [onlyAsset.localIdentifier],
                        startDate: onlyDate,
                        endDate: onlyDate
                    )
                )
                continue
            }

            let imageCluster = cluster.filter { $0.mediaType == .image }
            let observations: [String: VNFeaturePrintObservation]
            if imageCluster.isEmpty {
                observations = [:]
            } else {
                observations = try await featurePrints(
                    for: imageCluster,
                    cache: &featurePrintCache
                )
            }

            let reviewGroups = similarityComponents(
                in: cluster,
                observations: observations,
                threshold: settings.similarityDistanceThreshold
            )

            outputGroups.append(contentsOf: reviewGroups)
        }

        outputGroups.sort { lhs, rhs in
            lhs.startDate < rhs.startDate
        }

        var bestAssetByGroupID: [UUID: String] = [:]
        var bestShotScoresByAssetID: [String: BestShotScoreBreakdown] = [:]
        if settings.autoPickBestShot, !outputGroups.isEmpty {
            await progress(
                .init(
                    fractionCompleted: 0.94,
                    message: "Evaluating quality signals for best-shot suggestions..."
                )
            )
            let selections = try await bestShotSelections(
                groups: outputGroups,
                assetLookup: assetLookup,
                progress: progress
            )
            bestAssetByGroupID = selections.suggestions
            bestShotScoresByAssetID = selections.scores
        }

        await progress(
            .init(
                fractionCompleted: 1.0,
                message: settings.autoPickBestShot
                    ? "Scan complete. Found \(outputGroups.count) review groups and suggested best shots."
                    : "Scan complete. Found \(outputGroups.count) review groups."
            )
        )

        return ScanResult(
            groups: outputGroups,
            bestAssetByGroupID: bestAssetByGroupID,
            bestShotScoresByAssetID: bestShotScoresByAssetID,
            assetLookup: assetLookup,
            scannedAssetCount: assets.count,
            temporalClusterCount: temporalClusters.count
        )
    }

    private func buildTemporalClusters(
        from assets: [PHAsset],
        maxGapSeconds: TimeInterval
    ) -> [[PHAsset]] {
        let sorted = assets.sorted { lhs, rhs in
            (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
        }

        guard !sorted.isEmpty else {
            return []
        }

        var clusters: [[PHAsset]] = []
        var currentCluster: [PHAsset] = [sorted[0]]

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]
            let previousDate = previous.creationDate ?? .distantPast
            let currentDate = current.creationDate ?? .distantFuture

            if currentDate.timeIntervalSince(previousDate) <= maxGapSeconds {
                currentCluster.append(current)
            } else {
                clusters.append(currentCluster)
                currentCluster = [current]
            }
        }

        clusters.append(currentCluster)

        return clusters
    }

    private func featurePrints(
        for assets: [PHAsset],
        cache: inout [String: VNFeaturePrintObservation]
    ) async throws -> [String: VNFeaturePrintObservation] {
        var output: [String: VNFeaturePrintObservation] = [:]
        output.reserveCapacity(assets.count)

        for asset in assets {
            try Task.checkCancellation()
            let id = asset.localIdentifier

            if let cached = cache[id] {
                output[id] = cached
                continue
            }

            guard
                let cgImage = await libraryService.requestCGImage(
                    for: asset,
                    targetSize: CGSize(width: 320, height: 320)
                )
            else {
                continue
            }

            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                continue
            }

            cache[id] = observation
            output[id] = observation
        }

        return output
    }

    private func similarityComponents(
        in cluster: [PHAsset],
        observations: [String: VNFeaturePrintObservation],
        threshold: Float
    ) -> [ReviewGroup] {
        var groups: [ReviewGroup] = []

        // Videos are always kept as single-item review groups.
        let videoAssets = cluster
            .filter { $0.mediaType == .video }
            .sorted { lhs, rhs in
                (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
            }
        for video in videoAssets {
            let date = video.creationDate ?? .distantPast
            groups.append(
                ReviewGroup(
                    assetIDs: [video.localIdentifier],
                    startDate: date,
                    endDate: date
                )
            )
        }

        let imageAssets = cluster.filter { $0.mediaType == .image }
        guard !imageAssets.isEmpty else {
            return groups
        }

        let assetsByID = Dictionary(uniqueKeysWithValues: imageAssets.map { ($0.localIdentifier, $0) })
        let allIDs = imageAssets.map(\.localIdentifier)

        var edges: [String: Set<String>] = [:]
        allIDs.forEach { edges[$0] = [] }

        for firstIndex in 0..<allIDs.count {
            let idA = allIDs[firstIndex]
            guard let assetA = assetsByID[idA] else { continue }

            for secondIndex in (firstIndex + 1)..<allIDs.count {
                let idB = allIDs[secondIndex]
                guard let assetB = assetsByID[idB] else { continue }

                let isSameBurst: Bool = {
                    guard let burstA = assetA.burstIdentifier, !burstA.isEmpty else { return false }
                    guard let burstB = assetB.burstIdentifier, !burstB.isEmpty else { return false }
                    return burstA == burstB
                }()

                if isSameBurst {
                    edges[idA, default: []].insert(idB)
                    edges[idB, default: []].insert(idA)
                    continue
                }

                guard
                    let observationA = observations[idA],
                    let observationB = observations[idB]
                else {
                    continue
                }

                var distance: Float = 0
                do {
                    try observationA.computeDistance(&distance, to: observationB)
                } catch {
                    continue
                }

                if distance <= threshold {
                    edges[idA, default: []].insert(idB)
                    edges[idB, default: []].insert(idA)
                }
            }
        }

        var visited: Set<String> = []

        for startID in allIDs where !visited.contains(startID) {
            var stack: [String] = [startID]
            var componentIDs: [String] = []

            while let current = stack.popLast() {
                if visited.contains(current) {
                    continue
                }

                visited.insert(current)
                componentIDs.append(current)

                for neighbor in edges[current, default: []] where !visited.contains(neighbor) {
                    stack.append(neighbor)
                }
            }

            let sortedComponentIDs = componentIDs.sorted { lhs, rhs in
                (assetsByID[lhs]?.creationDate ?? .distantPast) < (assetsByID[rhs]?.creationDate ?? .distantPast)
            }

            // Split each connected component into stricter subgroups so every member
            // is directly similar to all others in that subgroup (not just connected by chain).
            let refinedComponents = refineConnectedComponent(sortedIDs: sortedComponentIDs, edges: edges)

            for refinedIDs in refinedComponents {
                let componentAssets = refinedIDs.compactMap { assetsByID[$0] }.sorted { lhs, rhs in
                    (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
                }

                guard let firstDate = componentAssets.first?.creationDate,
                      let lastDate = componentAssets.last?.creationDate else {
                    continue
                }

                groups.append(
                    ReviewGroup(
                        assetIDs: componentAssets.map(\.localIdentifier),
                        startDate: firstDate,
                        endDate: lastDate
                    )
                )
            }
        }

        return groups
    }

    private func refineConnectedComponent(
        sortedIDs: [String],
        edges: [String: Set<String>]
    ) -> [[String]] {
        var refined: [[String]] = []

        for candidateID in sortedIDs {
            let candidateNeighbors = edges[candidateID, default: []]
            var inserted = false

            for index in refined.indices {
                let existingGroup = refined[index]
                // Candidate can join only if it is directly similar to every existing member.
                if existingGroup.allSatisfy({ candidateNeighbors.contains($0) }) {
                    refined[index].append(candidateID)
                    inserted = true
                    break
                }
            }

            if !inserted {
                refined.append([candidateID])
            }
        }

        return refined
    }

    private func bestShotSelections(
        groups: [ReviewGroup],
        assetLookup: [String: PHAsset],
        progress: @escaping @MainActor (ScanProgress) -> Void
    ) async throws -> (suggestions: [UUID: String], scores: [String: BestShotScoreBreakdown]) {
        var suggestions: [UUID: String] = [:]
        var scoreCache: [String: BestShotScoreBreakdown] = [:]
        let total = max(1, groups.count)

        for (index, group) in groups.enumerated() {
            try Task.checkCancellation()

            if index % 4 == 0 || index == total - 1 {
                let fraction = 0.94 + (Double(index) / Double(total)) * 0.05
                await progress(
                    .init(
                        fractionCompleted: min(0.99, fraction),
                        message: "Choosing best shot \(index + 1) of \(total)..."
                    )
                )
            }

            if let bestID = await bestShotAssetID(
                in: group,
                assetLookup: assetLookup,
                scoreCache: &scoreCache
            ) {
                suggestions[group.id] = bestID
            }

            if index % 6 == 0 {
                await Task.yield()
            }
        }

        return (suggestions: suggestions, scores: scoreCache)
    }

    private func bestShotAssetID(
        in group: ReviewGroup,
        assetLookup: [String: PHAsset],
        scoreCache: inout [String: BestShotScoreBreakdown]
    ) async -> String? {
        let imageIDs = group.assetIDs.filter { assetLookup[$0]?.mediaType == .image }
        guard !imageIDs.isEmpty else {
            // Video-only groups do not receive auto-pick suggestions.
            return nil
        }

        var bestAssetID = imageIDs[0]
        var bestScore = -Double.infinity

        for assetID in imageIDs {
            let score: BestShotScoreBreakdown
            if let cached = scoreCache[assetID] {
                score = cached
            } else if let asset = assetLookup[assetID] {
                score = await qualityScore(for: asset)
                scoreCache[assetID] = score
            } else {
                continue
            }

            if score.totalScore > bestScore {
                bestScore = score.totalScore
                bestAssetID = assetID
            }
        }

        return bestAssetID
    }

    private func qualityScore(for asset: PHAsset) async -> BestShotScoreBreakdown {
        guard
            let cgImage = await libraryService.requestCGImage(
                for: asset,
                targetSize: CGSize(width: 720, height: 720),
                contentMode: .aspectFit
            )
        else {
            return BestShotScoreBreakdown(
                totalScore: 0.4,
                facePresence: 0.0,
                framing: 0.0,
                eyesOpen: 0.0,
                smile: 0.0,
                sharpness: 0.4,
                lighting: 0.4,
                color: 0.4,
                contrast: 0.4
            )
        }

        let ciImage = CIImage(cgImage: cgImage)
        let stats = imageStats(from: cgImage)
        let meanLuma = stats?.meanLuma ?? 0.5
        let lightingScore = clamp01(1.0 - (abs(meanLuma - 0.55) / 0.55))
        let contrastScore = clamp01((stats?.stdLuma ?? 0.14) / 0.22)
        let colorScore = clamp01((stats?.colorfulness ?? 0.11) / 0.35)
        let sharpnessScore = edgeSharpnessScore(for: ciImage)

        let faces = faceFeatures(in: ciImage)
        guard !faces.isEmpty else {
            let total = 0.42 * sharpnessScore
                + 0.27 * lightingScore
                + 0.17 * contrastScore
                + 0.14 * colorScore

            return BestShotScoreBreakdown(
                totalScore: total,
                facePresence: 0.0,
                framing: 0.0,
                eyesOpen: 0.5,
                smile: 0.0,
                sharpness: sharpnessScore,
                lighting: lightingScore,
                color: colorScore,
                contrast: contrastScore
            )
        }

        let imageArea = max(1.0, ciImage.extent.width * ciImage.extent.height)
        let largestFaceArea = faces.map { $0.bounds.width * $0.bounds.height }.max() ?? 0
        let faceAreaRatio = clamp01(Double(largestFaceArea / imageArea))
        let framingScore = clamp01(1.0 - (abs(faceAreaRatio - 0.18) / 0.18))
        let facePresenceScore = clamp01(Double(faces.count) / 3.0)

        var eyesMeasuredCount = 0
        var eyesOpenCount = 0
        var smilesCount = 0
        for face in faces {
            if face.hasMouthPosition && face.hasSmile {
                smilesCount += 1
            }

            if face.hasLeftEyePosition && face.hasRightEyePosition {
                eyesMeasuredCount += 1
                if !face.leftEyeClosed && !face.rightEyeClosed {
                    eyesOpenCount += 1
                }
            }
        }

        let eyesOpenScore = eyesMeasuredCount > 0
            ? Double(eyesOpenCount) / Double(eyesMeasuredCount)
            : 0.5
        let smileScore = Double(smilesCount) / Double(faces.count)

        let total = 0.20 * facePresenceScore
            + 0.17 * framingScore
            + 0.18 * eyesOpenScore
            + 0.12 * smileScore
            + 0.14 * sharpnessScore
            + 0.10 * lightingScore
            + 0.07 * colorScore
            + 0.02 * contrastScore

        return BestShotScoreBreakdown(
            totalScore: total,
            facePresence: facePresenceScore,
            framing: framingScore,
            eyesOpen: eyesOpenScore,
            smile: smileScore,
            sharpness: sharpnessScore,
            lighting: lightingScore,
            color: colorScore,
            contrast: contrastScore
        )
    }

    private func edgeSharpnessScore(for image: CIImage) -> Double {
        let edges = image.applyingFilter(
            "CIEdges",
            parameters: [kCIInputIntensityKey: 2.2]
        )
        let edgeLuma = averageLuma(for: edges) ?? 0.02
        return clamp01(edgeLuma / 0.12)
    }

    private func faceFeatures(in image: CIImage) -> [CIFaceFeature] {
        guard let faceDetector else {
            return []
        }

        let features = faceDetector.features(in: image)
        return features.compactMap { $0 as? CIFaceFeature }
    }

    private func averageLuma(for image: CIImage) -> Double? {
        guard let averageRGBA = averageRGBA(for: image) else {
            return nil
        }

        let r = averageRGBA.0
        let g = averageRGBA.1
        let b = averageRGBA.2
        return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    }

    private func averageRGBA(for image: CIImage) -> (Double, Double, Double, Double)? {
        let extent = image.extent.integral
        guard !extent.isEmpty else {
            return nil
        }

        let averageImage = image.applyingFilter(
            "CIAreaAverage",
            parameters: [kCIInputExtentKey: CIVector(cgRect: extent)]
        )

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            averageImage,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return (
            Double(pixel[0]) / 255.0,
            Double(pixel[1]) / 255.0,
            Double(pixel[2]) / 255.0,
            Double(pixel[3]) / 255.0
        )
    }

    private func imageStats(from cgImage: CGImage, dimension: Int = 96) -> ImageStats? {
        let sampleSize = max(32, dimension)
        let bytesPerPixel = 4
        let bytesPerRow = sampleSize * bytesPerPixel
        var data = [UInt8](repeating: 0, count: sampleSize * bytesPerRow)

        guard let context = CGContext(
            data: &data,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        let pixelCount = sampleSize * sampleSize
        guard pixelCount > 0 else {
            return nil
        }

        var lumaValues = [Double]()
        lumaValues.reserveCapacity(pixelCount)

        var rgValues = [Double]()
        rgValues.reserveCapacity(pixelCount)
        var ybValues = [Double]()
        ybValues.reserveCapacity(pixelCount)

        for pixelIndex in 0..<pixelCount {
            let byteIndex = pixelIndex * 4
            let r = Double(data[byteIndex]) / 255.0
            let g = Double(data[byteIndex + 1]) / 255.0
            let b = Double(data[byteIndex + 2]) / 255.0

            let luma = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
            lumaValues.append(luma)

            rgValues.append(r - g)
            ybValues.append(0.5 * (r + g) - b)
        }

        let meanLuma = mean(lumaValues)
        let stdLuma = stdDeviation(lumaValues, meanValue: meanLuma)

        let meanRG = mean(rgValues)
        let meanYB = mean(ybValues)
        let stdRG = stdDeviation(rgValues, meanValue: meanRG)
        let stdYB = stdDeviation(ybValues, meanValue: meanYB)
        let colorfulness = sqrt((stdRG * stdRG) + (stdYB * stdYB))
            + (0.3 * sqrt((meanRG * meanRG) + (meanYB * meanYB)))

        return ImageStats(
            meanLuma: meanLuma,
            stdLuma: stdLuma,
            colorfulness: colorfulness
        )
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        let total = values.reduce(0, +)
        return total / Double(values.count)
    }

    private func stdDeviation(_ values: [Double], meanValue: Double) -> Double {
        guard values.count > 1 else {
            return 0
        }

        let variance = values.reduce(0) { partial, value in
            let diff = value - meanValue
            return partial + (diff * diff)
        } / Double(values.count)

        return sqrt(variance)
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
