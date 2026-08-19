//
//  SettingsView.swift
//  OSCcourier
//
//  The app's Settings window content. Split out of OSCcourierApp.swift
//  verbatim — no logic changes.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.auto.rawValue
    // How many OSC messages per second continuous (curve) tracks emit while
    // playing. Stored as an Int; the playback timer interval is 1/this.
    @AppStorage("oscMessagesPerSecond") private var oscMessagesPerSecond: Int = 20

    // Sensible range for continuous automation over local UDP OSC: below ~5/s
    // fast moves audibly step; above ~100/s mostly just floods the receiver.
    private let minRate = 5.0
    private let maxRate = 100.0

    // Fixed column widths. Everything is laid out against these two constants
    // rather than letting SwiftUI size things intrinsically — that's what
    // keeps rows from shifting when a field gains focus, when the numeric
    // value changes width (9 -> 100), or when a control swaps for another.
    private let labelWidth: CGFloat = 195
    private let controlWidth: CGFloat = 220

    // Double-clicking the numeric value swaps it for an editable field.
    @State private var isEditingRate = false
    @State private var rateEditText = ""
    @FocusState private var rateFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Appearance") {
                Picker("", selection: $appearanceModeRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Divider()

            // OSC send address prefix and receive port moved to a per-window
            // popover (next to the OSC address field in the toolbar) — they
            // can't live here anymore now that they're per-window/per-project
            // instead of a shared UserDefaults value, and Settings is a
            // single app-wide window.

            row("OSC output rate (msg/s.)") {
                resolutionControl
            }
            // Space for the tick overlay, reserved on the row as a whole
            // rather than inside resolutionControl — adding it there would
            // make the control taller again, which is precisely what threw
            // the label's vertical centering off.
            .padding(.bottom, 26)
        }
        .padding(20)
        .frame(width: labelWidth + controlWidth + 60, alignment: .leading)
        // Appearance is handled app-wide via NSApp.appearance — no
        // .preferredColorScheme anywhere, so SwiftUI views and AppKit-backed
        // controls (TextField, title bar) can't disagree with each other.
        .onChange(of: appearanceModeRaw) { _, newValue in
            (AppearanceMode(rawValue: newValue) ?? .auto).apply()
        }
    }

    // One settings row: right-aligned label of fixed width, then the control
    // in a fixed-width slot. Both widths are constant, so nothing reflows.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .lineLimit(1)
                .fixedSize()
                .frame(width: labelWidth, alignment: .trailing)
            content()
                .frame(width: controlWidth, alignment: .leading)
        }
    }

    private var resolutionControl: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { Double(oscMessagesPerSecond) },
                    set: { newValue in
                        // Magnetic snap to the recommended default (20):
                        // within 3 of it, stick to exactly 20.
                        oscMessagesPerSecond = abs(newValue - 20) < 3 ? 20 : Int(newValue.rounded())
                    }
                ),
                in: minRate...maxRate
            )
            // Both states (read-only Text and the editable TextField) live
            // in a ZStack with one fixed frame, and only their opacity is
            // toggled — so the slot's size never changes and nothing in
            // the window can shift when entering/leaving edit mode.
            ZStack(alignment: .trailing) {
                Text("\(oscMessagesPerSecond)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .opacity(isEditingRate ? 0 : 1)
                TextField("", text: $rateEditText)
                    // .plain (not .roundedBorder): the native bordered style
                    // has its own intrinsic padding/size, which would resize
                    // this slot on entering edit mode. The focus ring below is
                    // drawn as an overlay instead — overlays sit outside the
                    // layout flow, so it's purely visual and shifts nothing.
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($rateFieldFocused)
                    .opacity(isEditingRate ? 1 : 0)
                    .disabled(!isEditingRate)
                    .onSubmit { commitRateEdit() }
                    .onExitCommand { isEditingRate = false }
                    .onChange(of: rateFieldFocused) { _, focused in
                        if !focused && isEditingRate { commitRateEdit() }
                    }
            }
            .frame(width: 30, alignment: .trailing)
            .overlay {
                if isEditingRate {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                rateEditText = "\(oscMessagesPerSecond)"
                isEditingRate = true
                rateFieldFocused = true
            }
        }
        // Ticks drawn as an overlay rather than stacked below in a VStack:
        // an overlay sits OUTSIDE the layout flow, so this control's height
        // stays exactly the slider's height. That's what lets the row's
        // normal vertical centering put the label right on the slider,
        // instead of centering it against slider + ticks combined (which is
        // what pushed it down).
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    tickMark(label: "", atX: tickX(for: 5, width: width) + 10, width: width)
                    tickMark(label: "default", atX: tickX(for: 20, width: width) + 8, width: width) {
                        oscMessagesPerSecond = 20
                    }
                    tickMark(label: "", atX: tickX(for: 100, width: width) - 10, width: width)
                }
            }
            .frame(height: 26)
            .offset(y: 26)
        }
    }

    private func commitRateEdit() {
        if let v = Int(rateEditText.trimmingCharacters(in: .whitespaces)) {
            oscMessagesPerSecond = min(max(v, Int(minRate)), Int(maxRate))
        }
        isEditingRate = false
        rateFieldFocused = false
    }

    private func tickX(for value: Double, width: CGFloat) -> CGFloat {
        // The slider's usable track is inset from its bounds by roughly half
        // a knob on each side; subtracting the numeric readout's width keeps
        // the ticks under the slider itself rather than the whole HStack.
        let trackWidth = width - 38
        return CGFloat((value - minRate) / (maxRate - minRate)) * trackWidth
    }

    // A single tick: a short vertical line at the slider's value position,
    // with a caption centered under it. An optional onTap makes it clickable
    // — used so clicking "default" snaps back to 20.
    private func tickMark(label: String, atX: CGFloat, width: CGFloat, onTap: (() -> Void)? = nil) -> some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 1, height: 5)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize()
        }
        .frame(width: 80)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .position(x: min(max(atX, 0), width), y: 11)
    }
}
