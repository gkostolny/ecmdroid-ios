// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

// MARK: - Setup data model

private struct SetupBitItem: Identifiable {
    let id = UUID()
    let key: String
    let title: String?
    let bitNumbers: [Int]
    let varName: String
}

private struct SetupVariableItem: Identifiable {
    let id = UUID()
    let key: String
    let title: String?
}

private enum SetupItem: Identifiable {
    case bit(SetupBitItem)
    case variable(SetupVariableItem)

    var id: UUID {
        switch self {
        case .bit(let b): return b.id
        case .variable(let v): return v.id
        }
    }
}

private struct SetupCategory: Identifiable {
    let id = UUID()
    let name: String
    let items: [SetupItem]
}

private struct SetupScreen: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let categories: [SetupCategory]
}

// MARK: - Setup definition (mirrors ecm_setup.xml)

private let setupScreens: [SetupScreen] = [
    SetupScreen(name: "General Config", icon: "gearshape", categories: [
        SetupCategory(name: "System", items: [
            .bit(SetupBitItem(key: "KConfig[4]", title: "Bank Angle Sensor", bitNumbers: [4], varName: "KConfig")),
            .bit(SetupBitItem(key: "KConfig[2]", title: "Deceleration Fuel Cut", bitNumbers: [2], varName: "KConfig")),
            .bit(SetupBitItem(key: "KConfig[5]", title: nil, bitNumbers: [5], varName: "KConfig")),
            .bit(SetupBitItem(key: "KConfig[1]", title: nil, bitNumbers: [1], varName: "KConfig")),
            .bit(SetupBitItem(key: "KConfig[0]", title: "Idle Fuel Amp Ign Adjust", bitNumbers: [0], varName: "KConfig")),
            .bit(SetupBitItem(key: "KConfig[3]", title: nil, bitNumbers: [3], varName: "KConfig")),
            .bit(SetupBitItem(key: "KSI_Config[6]", title: nil, bitNumbers: [6], varName: "KSI_Config")),
            .bit(SetupBitItem(key: "KSI_Config[5]", title: nil, bitNumbers: [5], varName: "KSI_Config")),
        ]),
        SetupCategory(name: "Noise Reduction", items: [
            .bit(SetupBitItem(key: "KRet_Config[0]", title: "On Accel Condition Only", bitNumbers: [0], varName: "KRet_Config")),
            .bit(SetupBitItem(key: "KRet_Config[2]", title: "On Accel and WOT Condition", bitNumbers: [2], varName: "KRet_Config")),
            .bit(SetupBitItem(key: "KRet_Config[1]", title: "On WOT Condition Only", bitNumbers: [1], varName: "KRet_Config")),
            .bit(SetupBitItem(key: "KRet_Config[6]", title: nil, bitNumbers: [6], varName: "KRet_Config")),
            .bit(SetupBitItem(key: "KRet_Config[7]", title: "Suppress Accel Enrichment", bitNumbers: [7], varName: "KRet_Config")),
            .bit(SetupBitItem(key: "KAIC_Config[7]", title: "Active Intake", bitNumbers: [7], varName: "KAIC_Config")),
        ]),
        SetupCategory(name: "Airbox Pressure Sensor", items: [
            .bit(SetupBitItem(key: "KBaro_Config[7]", title: "Baro Correction Feature", bitNumbers: [7], varName: "KBaro_Config")),
            .bit(SetupBitItem(key: "KBaro_Config[6]", title: "Airbox Pressure Feature", bitNumbers: [6], varName: "KBaro_Config")),
            .bit(SetupBitItem(key: "KBaro_Config[2]", title: "Log Avg Baro ABP Corr Data", bitNumbers: [2], varName: "KBaro_Config")),
            .bit(SetupBitItem(key: "KABP_Config[1]", title: "Log MAP Front Rear Data", bitNumbers: [1], varName: "KABP_Config")),
            .bit(SetupBitItem(key: "KBaro_Config[0]", title: "Read Baro at Key On", bitNumbers: [0], varName: "KBaro_Config")),
            .bit(SetupBitItem(key: "KABP_Config[5]", title: "Read Sensor Continuously", bitNumbers: [5], varName: "KABP_Config")),
            .bit(SetupBitItem(key: "KBaro_Config[1]", title: "Skip Key On Read If Engine Runs", bitNumbers: [1], varName: "KBaro_Config")),
            .bit(SetupBitItem(key: "KABP_Config[4]", title: "Speed Correction", bitNumbers: [4], varName: "KABP_Config")),
            .bit(SetupBitItem(key: "KABP_Config[6]", title: "Use Baro Not MAP Sensor", bitNumbers: [6], varName: "KABP_Config")),
        ]),
        SetupCategory(name: "Shifter", items: [
            .bit(SetupBitItem(key: "KShift_Config[7]", title: "Shifter Feature", bitNumbers: [7], varName: "KShift_Config")),
            .bit(SetupBitItem(key: "KShift_Config[0]", title: "Shifter Transition Required", bitNumbers: [0], varName: "KShift_Config")),
            .bit(SetupBitItem(key: "KShift_Config[1]", title: "Shifter Fuel Spark Cut", bitNumbers: [1], varName: "KShift_Config")),
            .bit(SetupBitItem(key: "KSL_Config[7]", title: "Shift Light Feature", bitNumbers: [7], varName: "KSL_Config")),
            .bit(SetupBitItem(key: "KSL_Config[0]", title: "Shift Light Output", bitNumbers: [0], varName: "KSL_Config")),
        ]),
    ]),
    SetupScreen(name: "Error Mask", icon: "exclamationmark.shield", categories: [
        SetupCategory(name: "Sensors", items: [
            .bit(SetupBitItem(key: "EDiag1[6,7]", title: "Air Temperature Sensor", bitNumbers: [6, 7], varName: "EDiag1")),
            .bit(SetupBitItem(key: "EDiag3[6,7]", title: "Bank Angle Sensor", bitNumbers: [6, 7], varName: "EDiag3")),
            .bit(SetupBitItem(key: "EDiag8[6,7]", title: "Baro Sensor", bitNumbers: [6, 7], varName: "EDiag8")),
            .bit(SetupBitItem(key: "EDiag1[4,5]", title: "Battery Voltage", bitNumbers: [4, 5], varName: "EDiag1")),
            .bit(SetupBitItem(key: "EDiag3[0]", title: "Camshaft Position", bitNumbers: [0], varName: "EDiag3")),
            .bit(SetupBitItem(key: "EDiag5[4,5]", title: "Clutch Switch", bitNumbers: [4, 5], varName: "EDiag5")),
            .bit(SetupBitItem(key: "EDiag8[2,3]", title: "Crankshaft Position", bitNumbers: [2, 3], varName: "EDiag8")),
            .bit(SetupBitItem(key: "EDiag0[0,1]", title: "Engine Temp Sensor", bitNumbers: [0, 1], varName: "EDiag0")),
            .bit(SetupBitItem(key: "EDiag7[1,2,3]", title: "Fuel Pressure", bitNumbers: [1, 2, 3], varName: "EDiag7")),
            .bit(SetupBitItem(key: "EDiag8[4,5]", title: "Manifold Pressure", bitNumbers: [4, 5], varName: "EDiag8")),
            .bit(SetupBitItem(key: "EDiag5[2,3]", title: "Neutral Indicator Switch", bitNumbers: [2, 3], varName: "EDiag5")),
            .bit(SetupBitItem(key: "EDiag0[2,3,4]", title: "O2 Sensor Rear", bitNumbers: [2, 3, 4], varName: "EDiag0")),
            .bit(SetupBitItem(key: "EDiag7[5,6,7]", title: "O2 Sensor Front", bitNumbers: [5, 6, 7], varName: "EDiag7")),
            .bit(SetupBitItem(key: "EDiag4[5,6,7]", title: "Sidestand Switch", bitNumbers: [5, 6, 7], varName: "EDiag4")),
            .bit(SetupBitItem(key: "EDiag0[5,6]", title: "Throttle Pos Sensor", bitNumbers: [5, 6], varName: "EDiag0")),
        ]),
        SetupCategory(name: "Actuators", items: [
            .bit(SetupBitItem(key: "EDiag4_2[0,1,2,3]", title: "Exhaust Valve Actuator", bitNumbers: [0, 1, 2, 3], varName: "EDiag4_2")),
            .bit(SetupBitItem(key: "EDiag0[7]", title: "Cooling Fan", bitNumbers: [7], varName: "EDiag0")),
        ]),
    ]),
    SetupScreen(name: "Limits", icon: "speedometer", categories: [
        SetupCategory(name: "RPM Limits - Fixed", items: [
            .variable(SetupVariableItem(key: "KRPM_Soft_Hi", title: "RPM Soft High")),
            .variable(SetupVariableItem(key: "KRPM_Soft_Lo", title: "RPM Soft Low")),
            .variable(SetupVariableItem(key: "KRPM_Hard_Hi", title: "RPM Hard High")),
            .variable(SetupVariableItem(key: "KRPM_Hard_Lo", title: "RPM Hard Low")),
            .variable(SetupVariableItem(key: "KRPM_Kill_Hi", title: "RPM Kill High")),
            .variable(SetupVariableItem(key: "KRPM_Kill_Lo", title: "RPM Kill Low")),
        ]),
        SetupCategory(name: "RPM Limits - Cold Engine", items: [
            .variable(SetupVariableItem(key: "KTE_Cold", title: "Cold Engine Temp")),
            .variable(SetupVariableItem(key: "KRPM_Cold_Soft_Hi", title: "Cold Soft High")),
            .variable(SetupVariableItem(key: "KRPM_Cold_Soft_Lo", title: "Cold Soft Low")),
            .variable(SetupVariableItem(key: "KRPM_Cold_Hard_Hi", title: "Cold Hard High")),
            .variable(SetupVariableItem(key: "KRPM_Cold_Hard_Lo", title: "Cold Hard Low")),
        ]),
        SetupCategory(name: "Temperature Limits", items: [
            .variable(SetupVariableItem(key: "KTemp_Soft_Hi", title: "Temp Soft High")),
            .variable(SetupVariableItem(key: "KTemp_Soft_Lo", title: "Temp Soft Low")),
            .variable(SetupVariableItem(key: "KTemp_Hard_Hi", title: "Temp Hard High")),
            .variable(SetupVariableItem(key: "KTemp_Hard_Lo", title: "Temp Hard Low")),
            .variable(SetupVariableItem(key: "KTemp_Kill_Hi", title: "Temp Kill High")),
            .variable(SetupVariableItem(key: "KTemp_Kill_Lo", title: "Temp Kill Low")),
            .variable(SetupVariableItem(key: "KTemp_CEL_Flash_Hi", title: "CEL Flash High")),
            .variable(SetupVariableItem(key: "KTemp_CEL_Flash_Lo", title: "CEL Flash Low")),
        ]),
        SetupCategory(name: "Temperature Conditions", items: [
            .variable(SetupVariableItem(key: "KTemp_Load_Soft", title: "Load Soft")),
            .variable(SetupVariableItem(key: "KTemp_Load_Hard", title: "Load Hard")),
            .variable(SetupVariableItem(key: "KTemp_RPM_Soft", title: "RPM Soft")),
            .variable(SetupVariableItem(key: "KTemp_RPM_Hard", title: "RPM Hard")),
            .variable(SetupVariableItem(key: "KTemp_Abs_Hi", title: "Absolute High")),
            .variable(SetupVariableItem(key: "KTemp_Abs_Lo", title: "Absolute Low")),
        ]),
        SetupCategory(name: "Fan Setup - Key Off", items: [
            .variable(SetupVariableItem(key: "KKey_Off_Fan_Time", title: "Fan Run Time")),
            .variable(SetupVariableItem(key: "KKey_Off_Min_Bat", title: "Min Battery Voltage")),
            .variable(SetupVariableItem(key: "KKey_Off_Fan_On", title: "Fan On Temp")),
            .variable(SetupVariableItem(key: "KKey_Off_Fan_Off", title: "Fan Off Temp")),
            .variable(SetupVariableItem(key: "KKey_Off_Delay", title: "Delay")),
            .variable(SetupVariableItem(key: "KKey_Off_Fan_DC", title: "Fan Duty Cycle")),
        ]),
        SetupCategory(name: "Fan Setup - Key On", items: [
            .variable(SetupVariableItem(key: "KTemp_Fan_On", title: "Fan On Temp")),
            .variable(SetupVariableItem(key: "KTemp_Fan_Off", title: "Fan Off Temp")),
            .bit(SetupBitItem(key: "KCF_Config[5]", title: "Fan Control", bitNumbers: [5], varName: "KCF_Config")),
        ]),
    ]),
    SetupScreen(name: "AFV Settings", icon: "fuelpump", categories: [
        SetupCategory(name: "Adaptive Fuel Values", items: [
            .variable(SetupVariableItem(key: "LFuel", title: "AFV Rear")),
            .variable(SetupVariableItem(key: "LFuel1", title: "AFV Front")),
        ]),
    ]),
    SetupScreen(name: "O2 Setup", icon: "atom", categories: [
        SetupCategory(name: "O2 Sensor", items: [
            .variable(SetupVariableItem(key: "KO2_Rich", title: "Rich Voltage")),
            .variable(SetupVariableItem(key: "KO2_Midpoint", title: "Midpoint Voltage")),
            .variable(SetupVariableItem(key: "KO2_Lean", title: "Lean Voltage")),
            .variable(SetupVariableItem(key: "KO2_Min_RPM", title: "Min RPM")),
            .variable(SetupVariableItem(key: "KO2_Min_TP", title: "Min Throttle Position")),
            .variable(SetupVariableItem(key: "KO2_Act_Time", title: "Activation Time")),
            .variable(SetupVariableItem(key: "KO2_Inact_Time", title: "Inactivation Time")),
        ]),
        SetupCategory(name: "Closed Loop Configuration", items: [
            .bit(SetupBitItem(key: "KCL_Fuel_Config[7]", title: nil, bitNumbers: [7], varName: "KCL_Fuel_Config")),
            .bit(SetupBitItem(key: "KCL_Fuel_Config[0]", title: nil, bitNumbers: [0], varName: "KCL_Fuel_Config")),
            .bit(SetupBitItem(key: "KCL_Fuel_Config[6]", title: nil, bitNumbers: [6], varName: "KCL_Fuel_Config")),
        ]),
        SetupCategory(name: "EGO Correction Settings", items: [
            .variable(SetupVariableItem(key: "KFBFuel_Max", title: "Max EGO Correction")),
            .variable(SetupVariableItem(key: "KFBFuel_Min", title: "Min EGO Correction")),
            .variable(SetupVariableItem(key: "KCL_Max_TE", title: "Max Engine Temp")),
            .variable(SetupVariableItem(key: "KCL_Min_TE", title: "Min Engine Temp")),
        ]),
        SetupCategory(name: "AFV Learning", items: [
            .variable(SetupVariableItem(key: "KLFuel_Max", title: "AFV Max")),
            .variable(SetupVariableItem(key: "KLFuel_Min", title: "AFV Min")),
            .variable(SetupVariableItem(key: "Enrich_Time", title: "Enrichment Time")),
            .variable(SetupVariableItem(key: "KLFuel_Inc", title: "AFV Increment")),
            .variable(SetupVariableItem(key: "KLFuel_Dec", title: "AFV Decrement")),
            .variable(SetupVariableItem(key: "KLCL_Count", title: "CL Count")),
            .variable(SetupVariableItem(key: "KLCL_Max_TE", title: "Max Engine Temp")),
            .variable(SetupVariableItem(key: "KLCL_Min_TE", title: "Min Engine Temp")),
            .variable(SetupVariableItem(key: "KLFCD", title: "Fuel Cut Decel")),
        ]),
    ]),
    SetupScreen(name: "Exhaust Config", icon: "smoke", categories: [
        SetupCategory(name: "Exhaust Valve", items: [
            .bit(SetupBitItem(key: "KAMC_Config[7]", title: "Exhaust Valve Enabled", bitNumbers: [7], varName: "KAMC_Config")),
            .bit(SetupBitItem(key: "KAMC_Config[0]", title: nil, bitNumbers: [0], varName: "KAMC_Config")),
            .bit(SetupBitItem(key: "KAMC_Config[1]", title: "Keep Open When Not in WOT", bitNumbers: [1], varName: "KAMC_Config")),
            .bit(SetupBitItem(key: "KAMC_Config[2]", title: nil, bitNumbers: [2], varName: "KAMC_Config")),
            .bit(SetupBitItem(key: "KAMC_Config[4]", title: nil, bitNumbers: [4], varName: "KAMC_Config")),
            .bit(SetupBitItem(key: "KAMC_Config[5]", title: "Close Valve on AMC Error", bitNumbers: [5], varName: "KAMC_Config")),
            .bit(SetupBitItem(key: "KAMC_Config[3]", title: nil, bitNumbers: [3], varName: "KAMC_Config")),
            .bit(SetupBitItem(key: "KAMC_Config[6]", title: "Cycle Valve at Ignition On", bitNumbers: [6], varName: "KAMC_Config")),
        ]),
    ]),
]

// MARK: - Views

struct SetupView: View {
    var ecm = ECM.shared

    var body: some View {
        NavigationStack {
            if !ecm.isEEPROMRead {
                ContentUnavailableView {
                    Label("EEPROM Not Read", systemImage: "memorychip")
                } description: {
                    Text("Connect to an ECM and read the EEPROM from the ECM tab to view configuration.")
                }
            } else {
                List(setupScreens) { screen in
                    NavigationLink {
                        SetupScreenView(screen: screen)
                    } label: {
                        Label(screen.name, systemImage: screen.icon)
                    }
                }
            }
        }
        .navigationTitle("Setup")
    }
}

private struct SetupScreenView: View {
    let screen: SetupScreen
    var ecm = ECM.shared

    var body: some View {
        List {
            ForEach(screen.categories) { category in
                Section(category.name) {
                    ForEach(category.items) { item in
                        SetupItemRow(item: item)
                    }
                }
            }
        }
        .navigationTitle(screen.name)
    }
}

private struct SetupItemRow: View {
    let item: SetupItem
    var ecm = ECM.shared

    var body: some View {
        switch item {
        case .bit(let bitItem):
            BitItemRow(item: bitItem)
        case .variable(let varItem):
            VariableItemRow(item: varItem)
        }
    }
}

private struct BitItemRow: View {
    let item: SetupBitItem
    var ecm = ECM.shared

    var body: some View {
        let result = readBits()
        HStack(spacing: 12) {
            Image(systemName: result.available ? (result.allSet ? "checkmark.circle.fill" : "circle") : "minus.circle")
                .foregroundColor(result.available ? (result.allSet ? .green : .secondary) : .gray.opacity(0.5))
                .font(.body)

            Text(result.title)
                .foregroundColor(result.available ? .primary : .secondary)

            Spacer()

            if !result.available {
                Text("N/A")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func readBits() -> (title: String, allSet: Bool, available: Bool) {
        var title = item.title ?? item.key
        var allSet = true
        var anyFound = false

        for bitNr in item.bitNumbers {
            if let bit = ecm.getEEPROMBit(name: item.varName, bitNr: bitNr) {
                anyFound = true
                if title == item.key, !bit.name.isEmpty {
                    title = bit.name
                }
                if !bit.isSet {
                    allSet = false
                }
            }
        }

        if !anyFound {
            return (title, false, false)
        }
        return (title, allSet, true)
    }
}

private struct VariableItemRow: View {
    let item: SetupVariableItem
    var ecm = ECM.shared

    var body: some View {
        let result = readVariable()
        HStack(spacing: 12) {
            Text(result.title)
                .foregroundColor(result.available ? .primary : .secondary)

            Spacer()

            if result.available {
                Text(result.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.buellGold)
            } else {
                Text("N/A")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func readVariable() -> (title: String, value: String, available: Bool) {
        let title = item.title ?? item.key
        guard let v = ecm.getEEPROMValue(item.key) else {
            return (title, "", false)
        }
        let formatted = v.formattedValue
        // formattedValue already includes Variable.symbol.
        let display = formatted.isEmpty ? "N/A" : formatted
        return (title, display, true)
    }
}
