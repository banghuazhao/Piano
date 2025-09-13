//
// Created by Banghua Zhao on 12/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//
  

import SwiftUI

struct SettingsView: View {
    @AppStorage("showKeyDisplayNames") private var showKeyDisplayNames: Bool = true
    @AppStorage("showFirstKeyNameForOctavesOnly") private var showFirstKeyNameForOctavesOnly: Bool = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = false
    @AppStorage("keyWidth") private var keyWidth: Double = 50.0
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
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Key Width")
                            Spacer()
                            Text("\(Int(keyWidth)) pt")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $keyWidth, in: 30...80, step: 5)
                            .accentColor(.blue)
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
