import Foundation
import CoreGraphics
import RoomPlan
import simd

enum FloorPlanSurfaceRepresentation: String, Codable, Equatable {
    case source
    case solidWall
    case wideOpening
    case beam
    case column
}

struct FloorPlanSurfaceGeometry {
    let source: CapturedRoom.Surface
    let center: CGPoint
    let angle: CGFloat
    let halfLength: CGFloat
    let representation: FloorPlanSurfaceRepresentation
    let isFloorToCeilingGlass: Bool
    let openDirection: OpenDirection
    let strokeWidth: CGFloat?
    let scaleFactor: CGFloat
    let pointsPerMeter: CGFloat
    var thicknessMeters: CGFloat? = nil

    var widthInMeters: CGFloat {
        let measuredWidth = halfLength * 2 / pointsPerMeter
        if representation == .column {
            return min(max(measuredWidth, 0.12), 0.2)
        }
        return measuredWidth
    }

    var heightInMeters: CGFloat {
        let measured = CGFloat(source.dimensions.y)
        let fallback: CGFloat
        if source.category == .wall || effectiveRepresentation == .solidWall {
            fallback = 2.6
        } else if source.category == .door || source.category == .opening {
            fallback = 2.05
        } else {
            fallback = 1.2
        }
        return max((measured.isFinite && measured > 0.1 ? measured : fallback) * scaleFactor, 0.1)
    }

    var depthInMeters: CGFloat {
        if let thicknessMeters, thicknessMeters.isFinite, thicknessMeters > 0 {
            return thicknessMeters
        }
        let measured = CGFloat(source.dimensions.z) * scaleFactor
        return measured.isFinite && measured > 0 ? max(measured, 0.06) : 0.1
    }

    var worldCenter: CGPoint {
        FloorPlanCoordinateMapper.worldXZ(fromPlan: center, pointsPerMeter: pointsPerMeter)
    }

    var centerHeightInMeters: CGFloat {
        let value = CGFloat(source.transform.columns.3.y) * scaleFactor
        return value.isFinite ? value : 0
    }

    var effectiveRepresentation: FloorPlanSurfaceRepresentation {
        if representation == .source,
           source.category == .door,
           halfLength * 2 / pointsPerMeter > FloorPlanGeometry.oversizedDoorWidthMeters {
            return .wideOpening
        }
        return representation
    }

    var isWallGeometry: Bool {
        switch effectiveRepresentation {
        case .solidWall:
            return true
        case .source:
            return source.category == .wall
        case .wideOpening, .beam, .column:
            return false
        }
    }

    var isNoiseFragment: Bool {
        isWallGeometry && widthInMeters < FloorPlanGeometry.minimumWallSegmentLengthMeters
    }
}

struct FloorPlanObjectGeometry {
    let source: CapturedRoom.Object
    let center: CGPoint
    let angle: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let baseWidthInPoints: CGFloat
    let baseDepthInPoints: CGFloat
    let scaleFactor: CGFloat
    let pointsPerMeter: CGFloat

    var worldCenter: CGPoint {
        FloorPlanCoordinateMapper.worldXZ(fromPlan: center, pointsPerMeter: pointsPerMeter)
    }

    var widthInMeters: CGFloat {
        baseWidthInPoints * abs(xScale) / pointsPerMeter
    }

    var depthInMeters: CGFloat {
        baseDepthInPoints * abs(yScale) / pointsPerMeter
    }

    var heightInMeters: CGFloat {
        let value = CGFloat(source.dimensions.y) * scaleFactor
        return value.isFinite && value > 0 ? max(value, 0.25) : 0.75
    }

    var centerHeightInMeters: CGFloat {
        let value = CGFloat(source.transform.columns.3.y) * scaleFactor
        return value.isFinite ? value : 0
    }
}

struct FloorPlanManualObjectGeometry {
    let category: CapturedRoom.Object.Category
    let center: CGPoint
    let angle: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let scaleFactor: CGFloat
    let pointsPerMeter: CGFloat

    var worldCenter: CGPoint {
        FloorPlanCoordinateMapper.worldXZ(fromPlan: center, pointsPerMeter: pointsPerMeter)
    }

    var widthInMeters: CGFloat {
        80 * abs(xScale) / pointsPerMeter
    }

    var depthInMeters: CGFloat {
        60 * abs(yScale) / pointsPerMeter
    }

    var heightInMeters: CGFloat {
        0.75 * scaleFactor
    }
}

struct FloorPlanWallSegment {
    var start: CGPoint
    var end: CGPoint
    var heightInMeters: CGFloat = 2.6
    var depthInMeters: CGFloat = 0.1
    var sourceSurfaceIDs: Set<String> = []

    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    var angle: CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }

    var midpoint: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }
}


// MARK: - Contract v1: coordinate mapping

// Plan coordinates retain the existing saved-file convention:
// u = -worldX * pointsPerMeter, v = worldZ * pointsPerMeter.
// The second component of worldXZ is SceneKit Z, not world Y.
enum FloorPlanCoordinateMapper {
    static func point2D(
        fromWorld position: SIMD3<Float>,
        pointsPerMeter: CGFloat
    ) -> CGPoint {
        guard pointsPerMeter.isFinite, pointsPerMeter > 0,
              position.x.isFinite, position.z.isFinite else {
            return CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        }
        return CGPoint(
            x: -CGFloat(position.x) * pointsPerMeter,
            y: CGFloat(position.z) * pointsPerMeter
        )
    }

    static func worldXZ(
        fromPlan point: CGPoint,
        pointsPerMeter: CGFloat
    ) -> CGPoint {
        guard pointsPerMeter.isFinite, pointsPerMeter > 0,
              point.x.isFinite, point.y.isFinite else {
            return CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        }
        return CGPoint(x: -point.x / pointsPerMeter,
                       y: point.y / pointsPerMeter)
    }

    static func angle2D(from transform: simd_float4x4) -> CGFloat? {
        let x = -CGFloat(transform.columns.0.x)
        let y = CGFloat(transform.columns.0.z)
        guard x.isFinite, y.isFinite, hypot(x, y) > 1e-8 else {
            return nil
        }
        return atan2(y, x)
    }

    static func sceneKitYaw(fromPlanAngle angle: CGFloat) -> CGFloat {
        guard angle.isFinite else { return CGFloat.nan }
        // SceneKit rotation about +Y maps local +X to (cos(yaw), -sin(yaw)).
        // Mapping the plan tangent (cos(a), sin(a)) back to XZ gives
        // (-cos(a), sin(a)), hence yaw = a + pi, modulo 2*pi.
        // Renderer convention: plan-local +Y corresponds to node-local -Z.
        // Asymmetric 3D assets must follow that convention, not node-local +Z.
        return atan2(-sin(angle), -cos(angle))
    }
}

struct FloorPlanOpeningSpan {
    let start: CGPoint
    let end: CGPoint
    // Existing start/end call sites remain source-compatible. Windows protect
    // merge gaps but must not prevent an L/T corner extension.
    var blocksCornerExtension: Bool = true
}


// MARK: - Geometry assembled from captured data and saved edits

struct FloorPlanGeometry {
    static let minimumWallSegmentLengthMeters: CGFloat = 0.12
    static let oversizedDoorWidthMeters: CGFloat = 2.2

    private static let mergeAngle: CGFloat = 1.5 * .pi / 180
    private static let mergeOffsetMeters: CGFloat = 0.05
    private static let mergeGapMeters: CGFloat = 0.05
    private static let cornerReachMeters: CGFloat = 0.22
    private static let boundaryToleranceMeters: CGFloat = 0.01
    private static let minimumDerivedLengthMeters: CGFloat = 0.001

    let scaleFactor: CGFloat
    let pointsPerMeter: CGFloat
    let surfaces: [FloorPlanSurfaceGeometry]
    let objects: [FloorPlanObjectGeometry]
    let manualObjects: [FloorPlanManualObjectGeometry]

    var joinedWallSegments: [FloorPlanWallSegment] {
        let walls = surfaces.filter(\.isWallGeometry).map { surface in
            Self.makeWallSegment(
                center: surface.center,
                angle: surface.angle,
                halfLength: surface.halfLength,
                height: surface.heightInMeters,
                depth: surface.depthInMeters,
                sourceIDs: [surface.source.identifier.uuidString]
            )
        }
        let openings = surfaces.compactMap { surface -> FloorPlanOpeningSpan? in
            guard !surface.isWallGeometry else { return nil }
            switch surface.effectiveRepresentation {
            case .beam, .column, .solidWall:
                return nil
            case .source, .wideOpening:
                break
            }
            let category = surface.source.category
            guard surface.effectiveRepresentation == .wideOpening ||
                    category == .door || category == .opening || category == .window else {
                return nil
            }
            let segment = Self.makeWallSegment(
                center: surface.center,
                angle: surface.angle,
                halfLength: surface.halfLength,
                height: surface.heightInMeters,
                depth: surface.depthInMeters
            )
            return FloorPlanOpeningSpan(
                start: segment.start,
                end: segment.end,
                blocksCornerExtension: category != .window ||
                    surface.effectiveRepresentation == .wideOpening
            )
        }
        return Self.joinedWallSegments(
            from: walls, pointsPerMeter: pointsPerMeter, openings: openings
        )
    }

    init(
        capturedRoom: CapturedRoom,
        editState: FloorPlanEditState?,
        scaleFactor: CGFloat? = nil,
        pointsPerMeter: CGFloat = DrawParameters.scalingFactor
    ) {
        let requestedScale = scaleFactor ?? CGFloat(editState?.calibration?.scaleFactor ?? 1)
        let scale: CGFloat = requestedScale.isFinite && requestedScale > 0 ? requestedScale : 1
        let defaultPPM = DrawParameters.scalingFactor
        let fallbackPPM: CGFloat = defaultPPM.isFinite && defaultPPM > 0 ? defaultPPM : 200
        let ppm = pointsPerMeter.isFinite && pointsPerMeter > 0
            ? pointsPerMeter : fallbackPPM
        self.scaleFactor = scale
        self.pointsPerMeter = ppm

        let deletedSurfaces = Set((editState?.deletedSurfaceIDs ?? []).compactMap(UUID.init(uuidString:)))
        let deletedObjects = Set((editState?.deletedObjectIDs ?? []).compactMap(UUID.init(uuidString:)))
        let savedSurfaces = editState?.surfaces ?? [:]
        let savedObjects = editState?.objects ?? [:]

        func surfaceState(_ id: UUID) -> SavedSurfaceState? {
            savedSurfaces[id.uuidString] ?? savedSurfaces.first {
                UUID(uuidString: $0.key) == id
            }?.value
        }
        func objectState(_ id: UUID) -> SavedObjectState? {
            savedObjects[id.uuidString] ?? savedObjects.first {
                UUID(uuidString: $0.key) == id
            }?.value
        }

        surfaces = (capturedRoom.doors + capturedRoom.openings + capturedRoom.walls + capturedRoom.windows)
            .compactMap { surface -> FloorPlanSurfaceGeometry? in
                guard !deletedSurfaces.contains(surface.identifier) else { return nil }
                let saved = surfaceState(surface.identifier)
                let rawCenter = FloorPlanCoordinateMapper.point2D(
                    fromWorld: SIMD3<Float>(surface.transform.columns.3.x,
                                           surface.transform.columns.3.y,
                                           surface.transform.columns.3.z),
                    pointsPerMeter: ppm
                )
                let center = saved.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
                    ?? CGPoint(x: rawCenter.x * scale, y: rawCenter.y * scale)
                guard let angle = saved.map({ CGFloat($0.zRotation) })
                        ?? FloorPlanCoordinateMapper.angle2D(from: surface.transform) else { return nil }
                let halfLength = saved.map { CGFloat($0.halfLength) }
                    ?? CGFloat(surface.dimensions.x) * ppm * scale / 2
                guard Self.finite(center), angle.isFinite,
                      halfLength.isFinite, halfLength >= 0 else { return nil }
                return FloorPlanSurfaceGeometry(
                    source: surface,
                    center: center,
                    angle: angle,
                    halfLength: halfLength,
                    representation: saved?.representation ?? .source,
                    isFloorToCeilingGlass: saved?.isFloorToCeilingGlass ?? false,
                    openDirection: saved?.openDirection ?? .clockwise,
                    strokeWidth: saved?.strokeWidth.map { CGFloat($0) },
                    scaleFactor: scale,
                    pointsPerMeter: ppm,
                    thicknessMeters: saved?.thicknessMeters.map { CGFloat($0) }
                )
            }

        objects = capturedRoom.objects.compactMap { object -> FloorPlanObjectGeometry? in
            guard !deletedObjects.contains(object.identifier) else { return nil }
            let saved = objectState(object.identifier)
            let rawCenter = FloorPlanCoordinateMapper.point2D(
                fromWorld: SIMD3<Float>(object.transform.columns.3.x,
                                       object.transform.columns.3.y,
                                       object.transform.columns.3.z),
                pointsPerMeter: ppm
            )
            let center = saved.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
                ?? CGPoint(x: rawCenter.x * scale, y: rawCenter.y * scale)
            guard let angle = saved.map({ CGFloat($0.zRotation) })
                    ?? FloorPlanCoordinateMapper.angle2D(from: object.transform) else { return nil }
            let sx = CGFloat(saved?.xScale ?? Double(scale))
            let sy = CGFloat(saved?.yScale ?? Double(scale))
            let baseWidth = max(CGFloat(object.dimensions.x) * ppm, 40)
            let baseDepth = max(CGFloat(object.dimensions.z) * ppm, 40)
            guard Self.finite(center), angle.isFinite, sx.isFinite, sy.isFinite,
                  abs(sx) > 0, abs(sy) > 0,
                  baseWidth.isFinite, baseDepth.isFinite else { return nil }
            return FloorPlanObjectGeometry(
                source: object, center: center, angle: angle,
                xScale: sx, yScale: sy,
                baseWidthInPoints: baseWidth, baseDepthInPoints: baseDepth,
                scaleFactor: scale, pointsPerMeter: ppm
            )
        }

        manualObjects = (editState?.manualObjects ?? []).compactMap { saved in
            guard let category = try? JSONDecoder().decode(
                CapturedRoom.Object.Category.self, from: saved.categoryData
            ) else { return nil }
            let center = CGPoint(x: CGFloat(saved.x), y: CGFloat(saved.y))
            guard Self.finite(center), saved.zRotation.isFinite,
                  saved.xScale.isFinite, saved.yScale.isFinite,
                  abs(saved.xScale) > 0, abs(saved.yScale) > 0 else { return nil }
            return FloorPlanManualObjectGeometry(
                category: category, center: center, angle: CGFloat(saved.zRotation),
                xScale: CGFloat(saved.xScale), yScale: CGFloat(saved.yScale),
                scaleFactor: scale, pointsPerMeter: ppm
            )
        }
    }

    // MARK: - Stable anchor merging; no angular averaging

    static func joinedWallSegments(
        from source: [FloorPlanWallSegment],
        pointsPerMeter: CGFloat = DrawParameters.scalingFactor,
        openings: [FloorPlanOpeningSpan] = []
    ) -> [FloorPlanWallSegment] {
        guard pointsPerMeter.isFinite, pointsPerMeter > 0 else { return [] }
        let epsilon = pointsPerMeter * 1e-7
        let minimumLength = pointsPerMeter * minimumDerivedLengthMeters
        let offset = pointsPerMeter * mergeOffsetMeters
        let gap = pointsPerMeter * mergeGapMeters
        let validOpenings = openings.filter {
            finite($0.start) && finite($0.end) && distance($0.start, $0.end) > epsilon
        }
        // Retain short valid walls. The 12 cm constant is only a presentation/noise hint.
        let sorted = source.enumerated().filter {
            valid($0.element) && $0.element.length >= minimumLength
        }.sorted {
            if $0.element.length != $1.element.length {
                return $0.element.length > $1.element.length
            }
            return $0.offset < $1.offset
        }
        var used = Set<Int>()
        var merged: [FloorPlanWallSegment] = []

        for seed in sorted where !used.contains(seed.offset) {
            let anchor = seed.element
            guard let axis = unit(sub(anchor.end, anchor.start), epsilon: epsilon) else { continue }
            var low: CGFloat = 0
            var high = anchor.length
            var result = anchor
            var members = [anchor]
            used.insert(seed.offset)
            var changed = true

            while changed {
                changed = false
                for candidate in sorted where !used.contains(candidate.offset) {
                    let wall = candidate.element
                    // Pairwise checks prevent an accepted cluster from spanning
                    // 3 degrees or 10 cm through opposite-side anchor tolerances.
                    guard members.allSatisfy({ member in
                        let reference = member.length >= wall.length ? member : wall
                        let shorter = member.length >= wall.length ? wall : member
                        guard let referenceAxis = unit(sub(reference.end, reference.start), epsilon: epsilon),
                              let shorterAxis = unit(sub(shorter.end, shorter.start), epsilon: epsilon) else {
                            return false
                        }
                        return abs(dot(referenceAxis, shorterAxis)) >= cos(mergeAngle) - 1e-12 &&
                            abs(cross(referenceAxis, sub(shorter.start, reference.start))) <= offset + epsilon &&
                            abs(cross(referenceAxis, sub(shorter.end, reference.start))) <= offset + epsilon
                    }) else { continue }
                    guard let direction = unit(sub(wall.end, wall.start), epsilon: epsilon),
                          abs(dot(axis, direction)) >= cos(mergeAngle) - 1e-12 else { continue }
                    let a = sub(wall.start, anchor.start)
                    let b = sub(wall.end, anchor.start)
                    // Both endpoints must remain within 5 cm of the ORIGINAL anchor line.
                    guard abs(cross(axis, a)) <= offset + epsilon,
                          abs(cross(axis, b)) <= offset + epsilon else { continue }
                    let wallLow = min(dot(a, axis), dot(b, axis))
                    let wallHigh = max(dot(a, axis), dot(b, axis))
                    guard wallLow <= high + gap + epsilon,
                          wallHigh >= low - gap - epsilon else { continue }
                    let proposedLow = min(low, wallLow)
                    let proposedHigh = max(high, wallHigh)
                    // Only newly bridged empty space can cross an opening.
                    // An opening over an already occupied wall interval is not a gap.
                    let gapLow: CGFloat
                    let gapHigh: CGFloat
                    if wallLow > high {
                        gapLow = high
                        gapHigh = wallLow
                    } else if low > wallHigh {
                        gapLow = wallHigh
                        gapHigh = low
                    } else {
                        gapLow = 0
                        gapHigh = 0
                    }
                    if gapHigh - gapLow > epsilon && blocked(
                        origin: anchor.start, axis: axis,
                        low: gapLow, high: gapHigh,
                        openings: validOpenings, offset: offset, epsilon: epsilon
                    ) {
                        continue
                    }
                    low = proposedLow
                    high = proposedHigh
                    result.heightInMeters = max(result.heightInMeters, wall.heightInMeters)
                    result.depthInMeters = max(result.depthInMeters, wall.depthInMeters)
                    result.sourceSurfaceIDs.formUnion(wall.sourceSurfaceIDs)
                    used.insert(candidate.offset)
                    members.append(wall)
                    changed = true
                }
            }
            result.start = add(anchor.start, mul(axis, low))
            result.end = add(anchor.start, mul(axis, high))
            merged.append(result)
        }
        return connectCorners(
            merged, pointsPerMeter: pointsPerMeter, openings: validOpenings
        )
    }

    static func segments(from surfaces: [FloorPlanSurface]) -> [FloorPlanWallSegment] {
        surfaces.compactMap { surface in
            let segment = makeWallSegment(
                center: surface.position, angle: surface.zRotation,
                halfLength: surface.halfLength,
                height: CGFloat(surface.capturedSurface.dimensions.y),
                depth: CGFloat(surface.capturedSurface.dimensions.z),
                sourceIDs: [surface.capturedSurface.identifier.uuidString]
            )
            return valid(segment) ? segment : nil
        }
    }

    private static func makeWallSegment(
        center: CGPoint, angle: CGFloat, halfLength: CGFloat,
        height: CGFloat, depth: CGFloat, sourceIDs: Set<String> = []
    ) -> FloorPlanWallSegment {
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        return FloorPlanWallSegment(
            start: sub(center, mul(direction, halfLength)),
            end: add(center, mul(direction, halfLength)),
            heightInMeters: height.isFinite && height > 0 ? height : 2.6,
            depthInMeters: depth.isFinite && depth > 0 ? depth : 0.1,
            sourceSurfaceIDs: sourceIDs
        )
    }

    private static func blocked(
        origin: CGPoint, axis: CGPoint, low: CGFloat, high: CGFloat,
        openings: [FloorPlanOpeningSpan], offset: CGFloat, epsilon: CGFloat
    ) -> Bool {
        guard high - low > epsilon else { return false }
        return openings.contains { opening in
            guard let direction = unit(sub(opening.end, opening.start), epsilon: epsilon),
                  abs(dot(axis, direction)) >= cos(mergeAngle) - 1e-12 else { return false }
            let a = sub(opening.start, origin)
            let b = sub(opening.end, origin)
            guard max(abs(cross(axis, a)), abs(cross(axis, b))) <= offset + epsilon else {
                return false
            }
            let openingLow = min(dot(a, axis), dot(b, axis))
            let openingHigh = max(dot(a, axis), dot(b, axis))
            return min(high, openingHigh) - max(low, openingLow) > epsilon
        }
    }

    // MARK: - L and T junctions on derived segments only

    private struct CornerCandidate {
        let first: Int
        let firstStart: Bool
        let second: Int
        let secondStart: Bool?
        let point: CGPoint
        let score: CGFloat
    }

    private static func connectCorners(
        _ source: [FloorPlanWallSegment],
        pointsPerMeter: CGFloat,
        openings: [FloorPlanOpeningSpan]
    ) -> [FloorPlanWallSegment] {
        guard source.count > 1 else { return source }
        let epsilon = pointsPerMeter * 1e-7
        let minimumLength = pointsPerMeter * minimumDerivedLengthMeters
        let reach = pointsPerMeter * cornerReachMeters
        var candidates: [CornerCandidate] = []
        let cornerBlockingOpenings = openings.filter(\.blocksCornerExtension)

        func endpoint(_ wall: FloorPlanWallSegment, _ start: Bool) -> CGPoint {
            start ? wall.start : wall.end
        }
        func canMove(_ from: CGPoint, to: CGPoint) -> Bool {
            let vector = sub(to, from)
            let length = hypot(vector.x, vector.y)
            guard length <= reach + epsilon else { return false }
            guard let axis = unit(vector, epsilon: epsilon) else { return true }
            return !blocked(
                origin: from, axis: axis, low: 0, high: length,
                openings: cornerBlockingOpenings,
                offset: pointsPerMeter * mergeOffsetMeters,
                epsilon: epsilon
            )
        }

        for i in source.indices {
            for j in source.indices where j > i {
                let first = source[i]
                let second = source[j]
                guard let u = unit(sub(first.end, first.start), epsilon: epsilon),
                      let v = unit(sub(second.end, second.start), epsilon: epsilon) else { continue }
                let determinant = cross(u, v)
                guard determinant.isFinite, abs(determinant) > 1e-8 else { continue }
                let between = sub(second.start, first.start)
                let alongFirst = cross(between, v) / determinant
                let alongSecond = cross(between, u) / determinant
                guard alongFirst.isFinite, alongSecond.isFinite else { continue }
                let point = add(first.start, mul(u, alongFirst))
                guard finite(point) else { continue }

                for firstStart in [true, false] {
                    let a = endpoint(first, firstStart)
                    guard canMove(a, to: point) else { continue }
                    for secondStart in [true, false] {
                        let b = endpoint(second, secondStart)
                        guard distance(a, b) <= 2 * reach + epsilon,
                              canMove(b, to: point) else { continue }
                        candidates.append(CornerCandidate(
                            first: i, firstStart: firstStart,
                            second: j, secondStart: secondStart, point: point,
                            score: distance(a, point) + distance(b, point)
                        ))
                    }
                    if alongSecond >= -epsilon && alongSecond <= second.length + epsilon {
                        candidates.append(CornerCandidate(
                            first: i, firstStart: firstStart, second: j,
                            secondStart: nil, point: point,
                            score: distance(a, point) + epsilon
                        ))
                    }
                }
                for secondStart in [true, false] {
                    let b = endpoint(second, secondStart)
                    if alongFirst >= -epsilon && alongFirst <= first.length + epsilon &&
                        canMove(b, to: point) {
                        candidates.append(CornerCandidate(
                            first: j, firstStart: secondStart, second: i,
                            secondStart: nil, point: point,
                            score: distance(b, point) + epsilon
                        ))
                    }
                }
            }
        }
        candidates.sort {
            if $0.score != $1.score { return $0.score < $1.score }
            if $0.first != $1.first { return $0.first < $1.first }
            if $0.firstStart != $1.firstStart { return $0.firstStart }
            if $0.second != $1.second { return $0.second < $1.second }
            let lhs = $0.secondStart.map { $0 ? 0 : 1 } ?? 2
            let rhs = $1.secondStart.map { $0 ? 0 : 1 } ?? 2
            return lhs < rhs
        }

        var result = source
        var claimed = Set<Int>()
        var tJunctions: [(host: Int, point: CGPoint)] = []

        func endpointKey(_ index: Int, _ start: Bool) -> Int {
            index * 2 + (start ? 0 : 1)
        }
        func replacing(_ wall: FloorPlanWallSegment, start: Bool, point: CGPoint) -> FloorPlanWallSegment {
            var copy = wall
            if start { copy.start = point } else { copy.end = point }
            return copy
        }
        func keepsDirection(_ proposed: FloorPlanWallSegment, original: FloorPlanWallSegment) -> Bool {
            guard valid(proposed), proposed.length >= minimumLength else { return false }
            return dot(sub(proposed.end, proposed.start), sub(original.end, original.start)) > 0
        }

        for candidate in candidates {
            let key = endpointKey(candidate.first, candidate.firstStart)
            guard !claimed.contains(key) else { continue }
            let first = replacing(result[candidate.first], start: candidate.firstStart, point: candidate.point)
            guard keepsDirection(first, original: source[candidate.first]) else { continue }
            if let secondStart = candidate.secondStart {
                let secondKey = endpointKey(candidate.second, secondStart)
                guard !claimed.contains(secondKey) else { continue }
                let second = replacing(result[candidate.second], start: secondStart, point: candidate.point)
                guard keepsDirection(second, original: source[candidate.second]) else { continue }
                // Do not invalidate a T attachment already accepted on either host.
                guard tJunctions.allSatisfy({ junction in
                    if junction.host == candidate.first {
                        return pointOnSegment(junction.point, first, tolerance: epsilon)
                    }
                    if junction.host == candidate.second {
                        return pointOnSegment(junction.point, second, tolerance: epsilon)
                    }
                    return true
                }) else { continue }
                result[candidate.first] = first
                result[candidate.second] = second
                claimed.insert(key)
                claimed.insert(secondKey)
            } else {
                let host = result[candidate.second]
                guard pointOnSegment(candidate.point, host, tolerance: epsilon),
                      tJunctions.allSatisfy({ junction in
                          junction.host != candidate.first ||
                          pointOnSegment(junction.point, first, tolerance: epsilon)
                      }) else { continue }
                result[candidate.first] = first
                claimed.insert(key)
                tJunctions.append((candidate.second, candidate.point))
            }
        }

        // Splitting changes only derived geometry and preserves all source IDs.
        return splitAtEndpoints(result, tolerance: epsilon, minimumLength: minimumLength)
    }

    private static func splitAtEndpoints(
        _ source: [FloorPlanWallSegment], tolerance: CGFloat, minimumLength: CGFloat
    ) -> [FloorPlanWallSegment] {
        var result: [FloorPlanWallSegment] = []
        for i in source.indices {
            let wall = source[i]
            guard let axis = unit(sub(wall.end, wall.start), epsilon: tolerance) else { continue }
            var cuts: [CGFloat] = [0, wall.length]
            for j in source.indices where j != i {
                for point in [source[j].start, source[j].end] {
                    let delta = sub(point, wall.start)
                    let t = dot(delta, axis)
                    if abs(cross(axis, delta)) <= tolerance &&
                        t > tolerance && t < wall.length - tolerance {
                        cuts.append(t)
                    }
                }
            }
            cuts.sort()
            var unique: [CGFloat] = []
            for cut in cuts {
                if let previous = unique.last, cut - previous <= tolerance { continue }
                unique.append(cut)
            }
            guard unique.count > 1 else { continue }
            // Validate all cuts BEFORE appending any pieces, so a late sliver
            // cannot leave both partial pieces and a duplicate original wall.
            guard (1..<unique.count).allSatisfy({
                unique[$0] - unique[$0 - 1] >= minimumLength
            }) else {
                result.append(wall)
                continue
            }
            for k in 1..<unique.count {
                var piece = wall
                piece.start = add(wall.start, mul(axis, unique[k - 1]))
                piece.end = add(wall.start, mul(axis, unique[k]))
                result.append(piece)
            }
        }
        return result
    }

    // MARK: - Boundary validity and planar face traversal

    static func evaluateBoundary(
        segments: [FloorPlanWallSegment],
        pointsPerMeter: CGFloat = DrawParameters.scalingFactor
    ) -> FloorPlanBoundaryResult {
        guard pointsPerMeter.isFinite, pointsPerMeter > 0 else {
            return FloorPlanBoundaryResult(status: .ambiguous)
        }
        guard !segments.isEmpty else { return FloorPlanBoundaryResult(status: .empty) }
        // Bound quadratic work; exceeding this is an explicit unknown, not a fake area.
        guard segments.count <= 2048 else { return FloorPlanBoundaryResult(status: .ambiguous) }
        let epsilon = pointsPerMeter * 1e-7
        let tolerance = pointsPerMeter * boundaryToleranceMeters
        guard segments.allSatisfy({ valid($0) && $0.length > epsilon }) else {
            return FloorPlanBoundaryResult(status: .ambiguous)
        }
        let split = splitAtEndpoints(segments, tolerance: tolerance, minimumLength: epsilon)
        var vertices: [CGPoint] = []
        var clusters: [[CGPoint]] = []
        var edges: [(Int, Int)] = []
        var edgeKeys = Set<String>()

        func vertex(_ point: CGPoint) -> Int {
            if let index = vertices.indices.first(where: { index in
                clusters[index].allSatisfy { distance($0, point) <= tolerance }
            }) {
                clusters[index].append(point)
                return index
            }
            vertices.append(point)
            clusters.append([point])
            return vertices.count - 1
        }
        for wall in split {
            let a = vertex(wall.start)
            let b = vertex(wall.end)
            guard a != b else { return FloorPlanBoundaryResult(status: .ambiguous) }
            let key = "\(min(a, b)):\(max(a, b))"
            if edgeKeys.insert(key).inserted { edges.append((a, b)) }
        }
        guard edges.count >= 3 else { return FloorPlanBoundaryResult(status: .open) }

        // Proper X crossings and collinear overlaps are not guessed into a room.
        for i in edges.indices {
            for j in edges.indices where j > i {
                let first = edges[i]
                let second = edges[j]
                if first.0 == second.0 || first.0 == second.1 ||
                    first.1 == second.0 || first.1 == second.1 { continue }
                let a = vertices[first.0]
                let b = vertices[first.1]
                let c = vertices[second.0]
                let d = vertices[second.1]
                let u = sub(b, a)
                let v = sub(d, c)
                let determinant = cross(u, v)
                let lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
                if abs(determinant) > max(lengths * 1e-10, epsilon * epsilon) {
                    let t = cross(sub(c, a), v) / determinant
                    let q = cross(sub(c, a), u) / determinant
                    if t > 0 && t < 1 && q > 0 && q < 1 {
                        return FloorPlanBoundaryResult(status: .selfIntersecting)
                    }
                } else if let axis = unit(u, epsilon: epsilon),
                          abs(cross(axis, sub(c, a))) <= tolerance,
                          abs(cross(axis, sub(d, a))) <= tolerance {
                    let low = min(dot(sub(c, a), axis), dot(sub(d, a), axis))
                    let high = max(dot(sub(c, a), axis), dot(sub(d, a), axis))
                    if min(hypot(u.x, u.y), high) - max(0, low) > tolerance {
                        return FloorPlanBoundaryResult(status: .ambiguous)
                    }
                }
            }
        }

        var adjacency = Array(repeating: [Int](), count: vertices.count)
        for (a, b) in edges {
            adjacency[a].append(b)
            adjacency[b].append(a)
        }
        // Iteratively peel dangling trees, retaining the graph's 2-core.
        // The original segments are never changed by area evaluation.
        var degrees = adjacency.map(\.count)
        var active = Array(repeating: true, count: vertices.count)
        var queue = vertices.indices.filter { degrees[$0] <= 1 }
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            guard active[current], degrees[current] <= 1 else { continue }
            active[current] = false
            for neighbor in adjacency[current] where active[neighbor] {
                degrees[neighbor] -= 1
                if degrees[neighbor] <= 1 { queue.append(neighbor) }
            }
            degrees[current] = 0
        }
        let removedEdges = edges.filter { !active[$0.0] || !active[$0.1] }
        edges = edges.filter { active[$0.0] && active[$0.1] }
        guard edges.count >= 3 else {
            return FloorPlanBoundaryResult(status: .open)
        }
        adjacency = Array(repeating: [Int](), count: vertices.count)
        for (a, b) in edges {
            adjacency[a].append(b)
            adjacency[b].append(a)
        }
        let activeVertices = vertices.indices.filter { !adjacency[$0].isEmpty }
        guard let firstActive = activeVertices.first else {
            return FloorPlanBoundaryResult(status: .open)
        }
        var reached = Set<Int>()
        var stack = [firstActive]
        while let current = stack.popLast() {
            if !reached.insert(current).inserted { continue }
            stack.append(contentsOf: adjacency[current].filter { !reached.contains($0) })
        }
        guard reached.count == activeVertices.count else {
            // Separate loops may be rooms or holes. Do not silently add their areas.
            return FloorPlanBoundaryResult(status: .ambiguous)
        }
        for i in adjacency.indices {
            let origin = vertices[i]
            adjacency[i].sort { a, b in
                let aa = atan2(vertices[a].y - origin.y, vertices[a].x - origin.x)
                let bb = atan2(vertices[b].y - origin.y, vertices[b].x - origin.x)
                return aa == bb ? a < b : aa < bb
            }
        }
        func halfKey(_ a: Int, _ b: Int) -> String { "\(a):\(b)" }
        var faceForHalf: [String: Int] = [:]
        var faceAreas: [Double] = []
        var faceVertices: [[Int]] = []
        let origin = vertices[firstActive]

        for edge in edges {
            for initial in [(edge.0, edge.1), (edge.1, edge.0)] {
                if faceForHalf[halfKey(initial.0, initial.1)] != nil { continue }
                var a = initial.0
                var b = initial.1
                var face: [Int] = []
                var localHalf = Set<String>()
                var closed = false
                for _ in 0...(edges.count * 2) {
                    let key = halfKey(a, b)
                    guard faceForHalf[key] == nil,
                          localHalf.insert(key).inserted else { break }
                    face.append(a)
                    faceForHalf[key] = faceAreas.count
                    guard let reverse = adjacency[b].firstIndex(of: a),
                          !adjacency[b].isEmpty else { break }
                    let next = adjacency[b][(reverse + adjacency[b].count - 1) % adjacency[b].count]
                    a = b
                    b = next
                    if a == initial.0 && b == initial.1 {
                        closed = true
                        break
                    }
                }
                guard closed, face.count >= 3 else {
                    return FloorPlanBoundaryResult(status: .open)
                }
                guard Set(face).count == face.count else {
                    return FloorPlanBoundaryResult(status: .ambiguous)
                }
                // Translate before shoelace to reduce cancellation far from the origin.
                var twiceArea: Double = 0
                for k in face.indices {
                    let p = sub(vertices[face[k]], origin)
                    let q = sub(vertices[face[(k + 1) % face.count]], origin)
                    twiceArea += Double(p.x) * Double(q.y) - Double(p.y) * Double(q.x)
                }
                let area = twiceArea / 2
                guard area.isFinite, abs(area) > Double(epsilon * epsilon) else {
                    return FloorPlanBoundaryResult(status: .ambiguous)
                }
                faceAreas.append(area)
                faceVertices.append(face)
            }
        }
        for (a, b) in edges {
            guard let left = faceForHalf[halfKey(a, b)],
                  let right = faceForHalf[halfKey(b, a)], left != right else {
                return FloorPlanBoundaryResult(status: .open)
            }
        }
        let outside = faceAreas.filter { $0 < 0 }
        let inside = faceAreas.filter { $0 > 0 }
        guard outside.count == 1, !inside.isEmpty else {
            return FloorPlanBoundaryResult(status: .ambiguous)
        }
        // Pruning must not turn a broken exterior plus an interior loop into
        // a falsely valid room. Only dangling geometry inside the retained
        // exterior is accepted as a partition/screen wall.
        guard let exteriorIndex = faceAreas.firstIndex(where: { $0 < 0 }) else {
            return FloorPlanBoundaryResult(status: .ambiguous)
        }
        let exterior = faceVertices[exteriorIndex].map { vertices[$0] }
        func insideOrOnExterior(_ point: CGPoint) -> Bool {
            var inside = false
            for index in exterior.indices {
                let a = exterior[index]
                let b = exterior[(index + 1) % exterior.count]
                let segment = FloorPlanWallSegment(start: a, end: b)
                if pointOnSegment(point, segment, tolerance: tolerance) {
                    return true
                }
                if (a.y > point.y) != (b.y > point.y) {
                    // This branch guarantees a nonzero vertical denominator.
                    let intersectionX = a.x +
                        (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
                    if point.x < intersectionX { inside.toggle() }
                }
            }
            return inside
        }
        for (a, b) in removedEdges {
            let start = vertices[a]
            let end = vertices[b]
            let middle = mul(add(start, end), 0.5)
            guard insideOrOnExterior(start),
                  insideOrOnExterior(end),
                  insideOrOnExterior(middle) else {
                return FloorPlanBoundaryResult(status: .open)
            }
        }
        let areaPoints = inside.reduce(0, +)
        guard abs(areaPoints + outside[0]) <= max(1e-7, areaPoints * 1e-8) else {
            return FloorPlanBoundaryResult(status: .ambiguous)
        }
        let area = areaPoints / Double(pointsPerMeter) / Double(pointsPerMeter)
        return FloorPlanBoundaryResult(status: .closed, areaSquareMeters: area)
    }

    // MARK: - Finite vector operations

    private static func finite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
    private static func valid(_ segment: FloorPlanWallSegment) -> Bool {
        finite(segment.start) && finite(segment.end) && segment.length.isFinite &&
        segment.heightInMeters.isFinite && segment.heightInMeters > 0 &&
        segment.depthInMeters.isFinite && segment.depthInMeters > 0
    }
    private static func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x - b.x, y: a.y - b.y)
    }
    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x + b.x, y: a.y + b.y)
    }
    private static func mul(_ a: CGPoint, _ value: CGFloat) -> CGPoint {
        CGPoint(x: a.x * value, y: a.y * value)
    }
    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.x + a.y * b.y
    }
    private static func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.y - a.y * b.x
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
    private static func unit(_ vector: CGPoint, epsilon: CGFloat) -> CGPoint? {
        let length = hypot(vector.x, vector.y)
        guard length.isFinite, length > epsilon else { return nil }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }
    private static func pointOnSegment(
        _ point: CGPoint, _ segment: FloorPlanWallSegment, tolerance: CGFloat
    ) -> Bool {
        guard let axis = unit(sub(segment.end, segment.start), epsilon: tolerance * 0.1) else {
            return false
        }
        let delta = sub(point, segment.start)
        let t = dot(delta, axis)
        return abs(cross(axis, delta)) <= tolerance &&
            t >= -tolerance && t <= segment.length + tolerance
    }
}
