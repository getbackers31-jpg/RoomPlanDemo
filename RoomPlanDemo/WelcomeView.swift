//
//  WelcomeView.swift
//  RoomPlanPDP
//
//  Created by Baidetskyi Yurii on 08.01.2025.
//

import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack {
            Image(systemName: "house")
                .imageScale(.large)
                .foregroundColor(.indigo)
                .padding(.bottom, 8)
            
            Text("空間掃描 2D")
                .font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
                .fontWeight(.bold)
            Text("掃描您的空間並建立 2D 平面圖。")
            
            Spacer()
                .frame(height: 50)
            
            NavigationLink("開始掃描") {
                RoomCaptureScanView()
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .fontWeight(.bold)
            
            
            NavigationLink("範例展示") {
                RoomCaptureScanView(isDemo: true)
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .fontWeight(.bold)
        }
    }
}


#Preview {
    WelcomeView()
}
