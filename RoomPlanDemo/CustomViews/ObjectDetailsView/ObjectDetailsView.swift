//
//  ObjectDetailsView.swift
//  RoomPlanPDP
//
//  Created by Baidetskyi Yurii on 24.01.2025.
//

import RoomPlan
import SwiftUI

struct ObjectDetailsView: View {
    @Binding var object: FloorPlanObject?
    @Binding var selectedType: DetailsType?

    @State private var angle: CGFloat = 0

    init(
        object: Binding<FloorPlanObject?>,
        selectedType: Binding<DetailsType?>
    ) {
        _object = object
        _selectedType = selectedType
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 20) {
                    headerView

                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            ForEach(DetailsType.allCases, id: \.self) { type in
                                createSliderButton(for: type)
                            }
                        }
                    }
                }
                .padding(20)
            }

            Spacer()
        }
        .background(Color.teal)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear(perform: syncAngleFromSelection)
        .onChange(of: selectedObjectIdentity) { _, _ in
            syncAngleFromSelection()
        }
    }
}

private extension ObjectDetailsView {
    var selectedObjectIdentity: ObjectIdentifier? {
        object.map(ObjectIdentifier.init)
    }

    func normalizedRadians(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        var result = value.truncatingRemainder(dividingBy: 2 * .pi)
        if result > .pi { result -= 2 * .pi }
        if result < -.pi { result += 2 * .pi }
        return result
    }

    func syncAngleFromSelection() {
        angle = normalizedRadians(object?.zRotation ?? 0)
    }

    var headerView: some View {
        HStack {
            createTitleView(from: object)

            Spacer()

            Button {
                withAnimation {
                    selectedType = nil
                    object?.deselect()
                    object = nil
                }
            } label: {
                Image(systemName: "xmark.square.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    func createTitleView(from object: FloorPlanObject?) -> some View {
        if let object {
            Text("\(object.objectCategory.displayName)")
                .font(.largeTitle)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    func createSliderButton(for type: DetailsType) -> some View {
        if let object {
            switch type {
            case .measurements, .doorDirection:
                EmptyView()
            case .delete:
                Button {
                    withAnimation {
                        (object.scene as? FloorPlanScene)?.deleteObject(object)
                        selectedType = nil
                    }
                } label: {
                    VStack {
                        Image(systemName: type.buttonImageName)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(.white)

                        Text(type.description)
                            .foregroundStyle(.white)
                    }
                }
            case .rotate:
                Button {
                    guard let scene = object.scene as? FloorPlanScene else { return }
                    scene.recordUndoState()
                    let next = normalizedRadians(angle + .pi / 12)
                    object.updateAngle(to: next * 180 / .pi)
                    angle = next
                } label: {
                    VStack {
                        Image(systemName: type.buttonImageName)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(.white)

                        Text(type.description)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

#Preview {
    ObjectDetailsView(
        object: .constant(nil),
        selectedType: .constant(.measurements)
    )
}
