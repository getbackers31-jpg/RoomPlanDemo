import Foundation
import CoreGraphics
import RoomPlan

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
        max(CGFloat(source.dimensions.z) * scaleFactor, 0.06)
    }

    var worldCenter: CGPoint {
        CGPoint(x: -center.x / pointsPerMeter, y: -center.y / pointsPerMeter)
    }

    var centerHeightInMeters: CGFloat {
        CGFloat(source.transform.position.y) * scaleFactor
    }

    var effectiveRepresentation: FloorPlanSurfaceRepresentation {
        if representation == .source,
           source.category == .door,
           halfLength * 2 / pointsPerMeter > oversizedDoorWidthMeters {
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
        CGPoint(x: -center.x / pointsPerMeter, y: -center.y / pointsPerMeter)
    }

    var widthInMeters: CGFloat {
        baseWidthInPoints * abs(xScale) / pointsPerMeter
    }

    var depthInMeters: CGFloat {
        baseDepthInPoints * abs(yScale) / pointsPerMeter
    }

    var heightInMeters: CGFloat {
        max(CGFloat(source.dimensions.y) * scaleFactor, 0.25)
    }

    var centerHeightInMeters: CGFloat {
        CGFloat(source.transform.position.y) * scaleFactor
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
        CGPoint(x: -center.x / pointsPerMeter, y: -center.y / pointsPerMeter)
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

struct FloorPlanGeometry {
    static let minimumWallSegmentLengthMeters: CGFloat = 0.12
    static let oversizedDoorWidthMeters: CGFloat = 2.2

    let scaleFactor: CGFloat
    let pointsPerMeter: CGFloat
    let surfaces: [FloorPlanSurfaceGeometry]
    let objects: [FloorPlanObjectGeometry]
    let manualObjects: [FloorPlanManualObjectGeometry]

    var joinedWallSegments: [FloorPlanWallSegment] {
        Self.joinedWallSegments(
            from: surfaces.filter(\.isWallGeometry).map { surface in
                Self.makeWallSegment(
                    center: surface.center,
                    angle: surface.angle,
                    halfLength: surface.halfLength,
                    height: surface.heightInMeters,
                    depth: surface.depthInMeters
                )
            },
            pointsPerMeter: pointsPerMeter
        )
    }

    init(
        capturedRoom: CapturedRoom,
        editState: FloorPlanEditState?,
        scaleFactor: CGFloat? = nil,
        pointsPerMeter: CGFloat = DrawParameters.scalingFactor
    ) {
        let calibrationFactor = scaleFactor
            ?? CGFloat(editState?.calibration?.scaleFactor ?? 1)
        let resolvedScaleFactor = calibrationFactor.isFinite && calibrationFactor > 0
            ? calibrationFactor
            : 1
        self.scaleFactor = resolvedScaleFactor
        self.pointsPerMeter = pointsPerMeter

        surfaces = (capturedRoom.doors + capturedRoom.openings + capturedRoom.walls + capturedRoom.windows)
            .map { surface in
                let saved = editState?.surfaces[surface.identifier.uuidString]
                return FloorPlanSurfaceGeometry(
                    source: surface,
                    center: CGPoint(
                        x: CGFloat(saved?.x ?? Double(-CGFloat(surface.transform.position.x) * pointsPerMeter * resolvedScaleFactor)),
                        y: CGFloat(saved?.y ?? Double(CGFloat(surface.transform.position.z) * pointsPerMeter * resolvedScaleFactor))
                    ),
                    angle: CGFloat(
                        saved?.zRotation
                            ?? Double(-CGFloat(surface.transform.eulerAngles.z - surface.transform.eulerAngles.y))
                    ),
                    halfLength: CGFloat(
                        saved?.halfLength
                            ?? Double(CGFloat(surface.dimensions.x) * pointsPerMeter * resolvedScaleFactor / 2)
                    ),
                    representation: saved?.representation ?? .source,
                    isFloorToCeilingGlass: saved?.isFloorToCeilingGlass ?? false,
                    openDirection: saved?.openDirection ?? .clockwise,
                    strokeWidth: saved?.strokeWidth.map { CGFloat($0) },
                    scaleFactor: resolvedScaleFactor,
                    pointsPerMeter: pointsPerMeter
                )
            }

        objects = capturedRoom.objects.map { object in
            let saved = editState?.objects[object.identifier.uuidString]
            let baseWidthScale = saved == nil ? resolvedScaleFactor : 1
            return FloorPlanObjectGeometry(
                source: object,
                center: CGPoint(
                    x: CGFloat(saved?.x ?? Double(-CGFloat(object.transform.position.x) * pointsPerMeter * resolvedScaleFactor)),
                    y: CGFloat(saved?.y ?? Double(CGFloat(object.transform.position.z) * pointsPerMeter * resolvedScaleFactor))
                ),
                angle: CGFloat(
                    saved?.zRotation
                        ?? Double(-CGFloat(object.transform.eulerAngles.z - object.transform.eulerAngles.y))
                ),
                xScale: CGFloat(saved?.xScale ?? 1),
                yScale: CGFloat(saved?.yScale ?? 1),
                baseWidthInPoints: max(CGFloat(object.dimensions.x) * pointsPerMeter * baseWidthScale, 40),
                baseDepthInPoints: max(CGFloat(object.dimensions.z) * pointsPerMeter * baseWidthScale, 40),
                scaleFactor: resolvedScaleFactor,
                pointsPerMeter: pointsPerMeter
            )
        }

        manualObjects = (editState?.manualObjects ?? []).compactMap { saved in
            guard let category = try? JSONDecoder().decode(
                CapturedRoom.Object.Category.self,
                from: saved.categoryData
            ) else {
                return nil
            }
            return FloorPlanManualObjectGeometry(
                category: category,
                center: CGPoint(x: saved.x, y: saved.y),
                angle: CGFloat(saved.zRotation),
                xScale: CGFloat(saved.xScale),
                yScale: CGFloat(saved.yScale),
                scaleFactor: resolvedScaleFactor,
                pointsPerMeter: pointsPerMeter
            )
        }
    }

    static func joinedWallSegments(
        from source: [FloorPlanWallSegment],
        pointsPerMeter: CGFloat = DrawParameters.scalingFactor
    ) -> [FloorPlanWallSegment] {
        let minimumLength = pointsPerMeter * minimumWallSegmentLengthMeters
        var segments = source.filter { $0.length >= minimumLength }
        let parallelTolerance = sin(CGFloat.pi / 45)
        let offsetTolerance = DrawParameters.wallWidth * 0.5
        let gapTolerance = DrawParameters.wallWidth * 1.5

        var didMerge = true
        while didMerge {
            didMerge = false
            guard segments.count > 1 else { break }

            mergeSearch: for firstIndex in 0..<(segments.count - 1) {
                for secondIndex in (firstIndex + 1)..<segments.count {
                    let first = segments[firstIndex]
                    let second = segments[secondIndex]
                    let firstVector = CGPoint(x: first.end.x - first.start.x, y: first.end.y - first.start.y)
                    let secondVector = CGPoint(x: second.end.x - second.start.x, y: second.end.y - second.start.y)
                    let firstLength = first.length
                    let secondLength = second.length
                    guard firstLength > 1, secondLength > 1 else { continue }

                    let firstDirection = CGPoint(x: firstVector.x / firstLength, y: firstVector.y / firstLength)
                    let secondDirection = CGPoint(x: secondVector.x / secondLength, y: secondVector.y / secondLength)
                    guard abs(crossProduct(firstDirection, secondDirection)) <= parallelTolerance else { continue }

                    let directionSign: CGFloat = dotProduct(firstDirection, secondDirection) < 0 ? -1 : 1
                    let combinedVector = CGPoint(
                        x: firstVector.x + secondVector.x * directionSign,
                        y: firstVector.y + secondVector.y * directionSign
                    )
                    let combinedLength = hypot(combinedVector.x, combinedVector.y)
                    guard combinedLength > 1 else { continue }
                    let direction = CGPoint(x: combinedVector.x / combinedLength, y: combinedVector.y / combinedLength)
                    let normal = CGPoint(x: -direction.y, y: direction.x)
                    let firstStart = dotProduct(first.start, direction)
                    let firstEnd = dotProduct(first.end, direction)
                    let secondStart = dotProduct(second.start, direction)
                    let secondEnd = dotProduct(second.end, direction)
                    let firstMin = min(firstStart, firstEnd)
                    let firstMax = max(firstStart, firstEnd)
                    let secondMin = min(secondStart, secondEnd)
                    let secondMax = max(secondStart, secondEnd)
                    let gap = max(0, max(firstMin, secondMin) - min(firstMax, secondMax))
                    guard gap <= gapTolerance else { continue }

                    let overlapStart = max(firstMin, secondMin)
                    let overlapEnd = min(firstMax, secondMax)
                    let comparisonProjection = overlapStart <= overlapEnd
                        ? (overlapStart + overlapEnd) / 2
                        : (max(firstMin, secondMin) + min(firstMax, secondMax)) / 2
                    let firstStartOffset = dotProduct(first.start, normal)
                    let firstEndOffset = dotProduct(first.end, normal)
                    let secondStartOffset = dotProduct(second.start, normal)
                    let secondEndOffset = dotProduct(second.end, normal)
                    let firstOffsetAtComparison = firstStartOffset
                        + (comparisonProjection - firstStart) * (firstEndOffset - firstStartOffset) / (firstEnd - firstStart)
                    let secondOffsetAtComparison = secondStartOffset
                        + (comparisonProjection - secondStart) * (secondEndOffset - secondStartOffset) / (secondEnd - secondStart)
                    guard abs(firstOffsetAtComparison - secondOffsetAtComparison) <= offsetTolerance else { continue }

                    let firstMidOffset = (firstStartOffset + firstEndOffset) / 2
                    let secondMidOffset = (secondStartOffset + secondEndOffset) / 2
                    let averageOffset = (firstMidOffset * firstLength + secondMidOffset * secondLength)
                        / (firstLength + secondLength)
                    segments[firstIndex] = FloorPlanWallSegment(
                        start: CGPoint(
                            x: direction.x * min(firstMin, secondMin) + normal.x * averageOffset,
                            y: direction.y * min(firstMin, secondMin) + normal.y * averageOffset
                        ),
                        end: CGPoint(
                            x: direction.x * max(firstMax, secondMax) + normal.x * averageOffset,
                            y: direction.y * max(firstMax, secondMax) + normal.y * averageOffset
                        ),
                        heightInMeters: max(first.heightInMeters, second.heightInMeters),
                        depthInMeters: max(first.depthInMeters, second.depthInMeters)
                    )
                    segments.remove(at: secondIndex)
                    didMerge = true
                    break mergeSearch
                }
            }
        }

        return connectCorners(segments)
    }

    static func segments(from surfaces: [FloorPlanSurface]) -> [FloorPlanWallSegment] {
        surfaces.map {
            makeWallSegment(
                center: $0.position,
                angle: $0.zRotation,
                halfLength: $0.halfLength,
                height: CGFloat($0.capturedSurface.dimensions.y),
                depth: CGFloat($0.capturedSurface.dimensions.z)
            )
        }
    }

    private static func makeWallSegment(
        center: CGPoint,
        angle: CGFloat,
        halfLength: CGFloat,
        height: CGFloat,
        depth: CGFloat
    ) -> FloorPlanWallSegment {
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        return FloorPlanWallSegment(
            start: CGPoint(x: center.x - halfLength * direction.x, y: center.y - halfLength * direction.y),
            end: CGPoint(x: center.x + halfLength * direction.x, y: center.y + halfLength * direction.y),
            heightInMeters: height,
            depthInMeters: depth
        )
    }

    private static func connectCorners(_ source: [FloorPlanWallSegment]) -> [FloorPlanWallSegment] {
        guard source.count > 1 else { return source }

        var connected = source
        let minimumCrossProduct = sin(CGFloat.pi / 45)
        let endpointTolerance = DrawParameters.wallWidth * 2
        let maximumMiterExtension = DrawParameters.wallWidth * 3

        func endpoint(_ isStart: Bool, of segment: FloorPlanWallSegment) -> CGPoint {
            isStart ? segment.start : segment.end
        }

        for firstIndex in 0..<(source.count - 1) {
            for secondIndex in (firstIndex + 1)..<source.count {
                let first = source[firstIndex]
                let second = source[secondIndex]
                let firstVector = CGPoint(x: first.end.x - first.start.x, y: first.end.y - first.start.y)
                let secondVector = CGPoint(x: second.end.x - second.start.x, y: second.end.y - second.start.y)
                let firstLength = first.length
                let secondLength = second.length
                guard firstLength > 1, secondLength > 1 else { continue }

                let firstDirection = CGPoint(x: firstVector.x / firstLength, y: firstVector.y / firstLength)
                let secondDirection = CGPoint(x: secondVector.x / secondLength, y: secondVector.y / secondLength)
                let determinant = crossProduct(firstDirection, secondDirection)
                guard abs(determinant) > minimumCrossProduct else { continue }

                var bestMatch: (point: CGPoint, firstIsStart: Bool, secondIsStart: Bool, score: CGFloat)?
                for firstIsStart in [true, false] {
                    let firstPoint = endpoint(firstIsStart, of: first)
                    for secondIsStart in [true, false] {
                        let secondPoint = endpoint(secondIsStart, of: second)
                        let endpointDistance = hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
                        guard endpointDistance <= endpointTolerance else { continue }

                        let between = CGPoint(x: secondPoint.x - firstPoint.x, y: secondPoint.y - firstPoint.y)
                        let distanceAlongFirst = crossProduct(between, secondDirection) / determinant
                        let intersection = CGPoint(
                            x: firstPoint.x + firstDirection.x * distanceAlongFirst,
                            y: firstPoint.y + firstDirection.y * distanceAlongFirst
                        )
                        let firstExtension = hypot(intersection.x - firstPoint.x, intersection.y - firstPoint.y)
                        let secondExtension = hypot(intersection.x - secondPoint.x, intersection.y - secondPoint.y)
                        guard firstExtension <= maximumMiterExtension,
                              secondExtension <= maximumMiterExtension else { continue }

                        let score = endpointDistance + firstExtension + secondExtension
                        if let current = bestMatch, current.score <= score { continue }
                        bestMatch = (intersection, firstIsStart, secondIsStart, score)
                    }
                }

                guard let match = bestMatch else { continue }
                if match.firstIsStart {
                    connected[firstIndex].start = match.point
                } else {
                    connected[firstIndex].end = match.point
                }
                if match.secondIsStart {
                    connected[secondIndex].start = match.point
                } else {
                    connected[secondIndex].end = match.point
                }
            }
        }

        return connected
    }

    private static func crossProduct(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    private static func dotProduct(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        lhs.x * rhs.x + lhs.y * rhs.y
    }
}
