

import SwiftUI

struct ContentView: View {
    @State private var selection = 0
 
    var body: some View {
        TabView(selection: $selection){
            TimetableView()
                .tabItem {
                        Image(systemName: "radio.fill")
                        Text("ねとらじ")
                }
                .tag(0)
            Text("したらば")
                .tabItem {
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        Text("したらば")
                }
                .tag(1)
            Text("配信")
                .tabItem {
                        Image(systemName: "music.mic")
                        Text("配信")
                }
                .tag(2)
            
        }
    }
}
