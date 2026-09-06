import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("plateshelf")
                .font(.largeTitle).bold()
            Text("SwiftUI macOS 앱 스캐폴드")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
