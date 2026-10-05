//
//  HomeView.swift
//  InTune_442
//
//  Created by Collin Le on 10/4/26.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            NavigationStack {
                Text("")
                .navigationTitle("InTune")
            }
            .tabItem {
                Image(systemName: "house")
            }
            NavigationStack {
                MusicCardView()
            }
            .tabItem {
                Image(systemName: "music.note")
            }
            NavigationStack {
                Profile()
            }
            .tabItem {
                Image(systemName: "person.crop.circle")
            }
            
        }
    }
}

#Preview {
    HomeView()
}
