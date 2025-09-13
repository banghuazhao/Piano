//
// Created by Banghua Zhao on 12/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//
  

import SwiftUI

struct SettingsView: View {
    @AppStorage("showKeyDisplayNames") private var showKeyDisplayNames: Bool = true
    @AppStorage("showFirstKeyNameForOctavesOnly") private var showFirstKeyNameForOctavesOnly: Bool = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Display")) {
                    Toggle("Show Key Names", isOn: $showKeyDisplayNames)
                        .toggleStyle(SwitchToggleStyle())
                    if showKeyDisplayNames {
                        Toggle("Show First Key Name For Octaves Only", isOn: $showFirstKeyNameForOctavesOnly)
                            .toggleStyle(SwitchToggleStyle())
                    }
                }
                
                Section(header: Text("Feedback")) {
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }

                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
