import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    
    // Node configuration - Tailscale IPs
    readonly property var nodes: ({
        "zephyr": { ip: "100.81.182.5", lolminer: 4068, xmrig: 8081, hasNvidia: true },
        "nexus": { ip: "100.86.158.18", lolminer: 4068, xmrig: 8081, hasNvidia: true },
        "forge": { ip: "100.95.222.45", lolminerAmd: 4069, lolminerNvidia: 4068, xmrig: 8081, hasAmd: true, hasNvidia: true },
        "sentry": { ip: "100.82.210.39", xmrig: 8081, hasCpu: true }
    })
    
    // Colors
    readonly property color amdColor: Qt.rgba(1, 0.42, 0.21, 1.0)      // Orange #FF6B35
    readonly property color nvidiaColor: Qt.rgba(0.46, 0.73, 0, 1.0)   // Green #76B900
    readonly property color cpuColor: Qt.rgba(0.2, 0.6, 0.8, 1.0)       // Blue #3399CC
    
    // Data storage
    property var gpuData: []
    property var cpuData: []
    property string totalGpuHashrate: "0.00"
    property string totalCpuHashrate: "0.00"
    
    // Compact representation for panel
    compactRepresentation: Rectangle {
        id: compactRoot
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.highlightColor, Kirigami.Theme.backgroundColor, 0.9)
        border.color: Kirigami.Theme.highlightColor
        border.width: 1
        radius: 4
        
        property string totalHashrate: "0.00"
        
        Timer {
            interval: 5000
            running: true
            repeat: true
            onTriggered: root.fetchAllData()
            Component.onCompleted: root.fetchAllData()
        }
        
        RowLayout {
            anchors.centerIn: parent
            spacing: 6
            
            PlasmaComponents.Label {
                text: "GPU: " + root.totalGpuHashrate + " g/s"
                font.bold: true
                font.pixelSize: Math.min(compactRoot.width, compactRoot.height) * 0.3
                color: nvidiaColor
            }
            
            PlasmaComponents.Label {
                text: "|"
                font.pixelSize: Math.min(compactRoot.width, compactRoot.height) * 0.3
                color: Kirigami.Theme.textColor
                opacity: 0.5
            }
            
            PlasmaComponents.Label {
                text: "CPU: " + root.totalCpuHashrate + " kH"
                font.bold: true
                font.pixelSize: Math.min(compactRoot.width, compactRoot.height) * 0.3
                color: cpuColor
            }
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }
    
    // Full representation - Glassmorphic Design
    fullRepresentation: Rectangle {
        id: fullRoot
        Layout.minimumWidth: 350
        Layout.minimumHeight: 500
        Layout.preferredWidth: 400
        Layout.preferredHeight: 600
        
        // Glassmorphism background
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.4)
        radius: 20
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        
        Timer {
            interval: 3000
            running: true
            repeat: true
            onTriggered: root.fetchAllData()
            Component.onCompleted: root.fetchAllData()
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10
            
            // Title
            Rectangle {
                Layout.fillWidth: true
                height: 40
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                radius: 12
                
                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: "⛏️ Cluster Mining Monitor"
                    font.bold: true
                    font.pixelSize: 16
                }
            }
            
            // Totals Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                
                // GPU Total
                Rectangle {
                    Layout.fillWidth: true
                    height: 70
                    color: Qt.rgba(nvidiaColor.r, nvidiaColor.g, nvidiaColor.b, 0.15)
                    radius: 16
                    border.color: Qt.rgba(nvidiaColor.r, nvidiaColor.g, nvidiaColor.b, 0.3)
                    border.width: 1
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        
                        PlasmaComponents.Label {
                            text: "🎮 GPU Total"
                            font.pixelSize: 10
                            opacity: 0.8
                        }
                        
                        PlasmaComponents.Label {
                            text: root.totalGpuHashrate + " g/s"
                            font.bold: true
                            font.pixelSize: 22
                            color: nvidiaColor
                        }
                    }
                }
                
                // CPU Total
                Rectangle {
                    Layout.fillWidth: true
                    height: 70
                    color: Qt.rgba(cpuColor.r, cpuColor.g, cpuColor.b, 0.15)
                    radius: 16
                    border.color: Qt.rgba(cpuColor.r, cpuColor.g, cpuColor.b, 0.3)
                    border.width: 1
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        
                        PlasmaComponents.Label {
                            text: "💻 CPU Total"
                            font.pixelSize: 10
                            opacity: 0.8
                        }
                        
                        PlasmaComponents.Label {
                            text: root.totalCpuHashrate + " kH/s"
                            font.bold: true
                            font.pixelSize: 22
                            color: cpuColor
                        }
                    }
                }
            }
            
            // GPU Section Header
            PlasmaComponents.Label {
                text: "🔥 GPU Miners"
                font.bold: true
                font.pixelSize: 13
                color: amdColor
            }
            
            // GPU List
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                
                ColumnLayout {
                    id: gpuList
                    width: parent.width
                    spacing: 4
                    
                    Repeater {
                        model: root.gpuData
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            // Color based on GPU type
                            color: modelData.type === "amd" ? 
                                Qt.rgba(amdColor.r, amdColor.g, amdColor.b, 0.15) :
                                Qt.rgba(nvidiaColor.r, nvidiaColor.g, nvidiaColor.b, 0.15)
                            radius: 10
                            border.width: 1
                            border.color: modelData.type === "amd" ?
                                Qt.rgba(amdColor.r, amdColor.g, amdColor.b, 0.3) :
                                Qt.rgba(nvidiaColor.r, nvidiaColor.g, nvidiaColor.b, 0.3)
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                
                                // GPU emoji based on type
                                PlasmaComponents.Label {
                                    text: modelData.type === "amd" ? "🔥" : "💚"
                                    font.pixelSize: 14
                                }
                                
                                PlasmaComponents.Label {
                                    text: modelData.node
                                    font.bold: true
                                    font.pixelSize: 11
                                    Layout.preferredWidth: 55
                                }
                                
                                PlasmaComponents.Label {
                                    text: modelData.gpu
                                    font.pixelSize: 10
                                    opacity: 0.8
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                
                                PlasmaComponents.Label {
                                    text: modelData.hashrate.toFixed(2) + " g/s"
                                    font.bold: true
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 70
                                }
                                
                                PlasmaComponents.Label {
                                    text: modelData.temp + "°C"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: modelData.temp > 80 ? "#FF6B6B" : 
                                           modelData.temp > 70 ? "#FFE066" : "#69DB7C"
                                    Layout.preferredWidth: 45
                                }
                            }
                        }
                    }
                }
            }
            
            // CPU Section Header
            PlasmaComponents.Label {
                text: "💻 CPU Miners"
                font.bold: true
                font.pixelSize: 13
                color: cpuColor
            }
            
            // CPU Grid
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                
                Repeater {
                    model: root.cpuData
                    
                    Rectangle {
                        Layout.fillWidth: true
                        height: 55
                        color: Qt.rgba(cpuColor.r, cpuColor.g, cpuColor.b, 0.12)
                        radius: 10
                        border.color: Qt.rgba(cpuColor.r, cpuColor.g, cpuColor.b, 0.2)
                        border.width: 1
                        
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            
                            PlasmaComponents.Label {
                                text: modelData.node
                                font.bold: true
                                font.pixelSize: 11
                            }
                            
                            PlasmaComponents.Label {
                                text: (modelData.hashrate / 1000).toFixed(1) + " kH/s"
                                font.pixelSize: 13
                                font.bold: true
                                color: cpuColor
                            }
                            
                            PlasmaComponents.Label {
                                text: modelData.shares + " shares"
                                font.pixelSize: 9
                                opacity: 0.7
                            }
                        }
                    }
                }
            }
            
            Item { Layout.fillHeight: true }
        }
    }
    
    // Data fetching
    function fetchAllData() {
        var gpus = []
        var cpus = []
        var totalGpu = 0
        var totalCpu = 0
        var pending = 0
        var completed = 0
        
        function checkComplete() {
            completed++
            if (completed >= pending) {
                // Sort GPUs: AMD first, then NVIDIA, by node
                gpus.sort(function(a, b) {
                    if (a.type !== b.type) return a.type === "amd" ? -1 : 1
                    if (a.node !== b.node) return a.node.localeCompare(b.node)
                    return a.index - b.index
                })
                root.gpuData = gpus
                root.cpuData = cpus
                root.totalGpuHashrate = totalGpu.toFixed(2)
                root.totalCpuHashrate = (totalCpu / 1000).toFixed(1)
            }
        }
        
        // === GPU Miners ===
        
        // Zephyr NVIDIA
        pending++
        var xhrZephyrNv = new XMLHttpRequest()
        xhrZephyrNv.onreadystatechange = function() {
            if (xhrZephyrNv.readyState === XMLHttpRequest.DONE) {
                if (xhrZephyrNv.status === 200) {
                    try {
                        var d = JSON.parse(xhrZephyrNv.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "zephyr",
                                    type: "nvidia",
                                    index: i,
                                    gpu: d.Workers[i].Name || "RTX 3090",
                                    hashrate: d.Algorithms[0].Worker_Performance[i] || 0,
                                    temp: d.Workers[i].Core_Temp || 0
                                })
                            }
                            totalGpu += d.Algorithms[0].Total_Performance || 0
                        }
                    } catch(e) {}
                }
                checkComplete()
            }
        }
        xhrZephyrNv.open("GET", "http://" + nodes.zephyr.ip + ":" + nodes.zephyr.lolminer + "/")
        xhrZephyrNv.send()
        
        // Nexus NVIDIA
        pending++
        var xhrNexusNv = new XMLHttpRequest()
        xhrNexusNv.onreadystatechange = function() {
            if (xhrNexusNv.readyState === XMLHttpRequest.DONE) {
                if (xhrNexusNv.status === 200) {
                    try {
                        var d = JSON.parse(xhrNexusNv.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "nexus",
                                    type: "nvidia",
                                    index: i,
                                    gpu: d.Workers[i].Name || "RTX 3060 Ti",
                                    hashrate: d.Algorithms[0].Worker_Performance[i] || 0,
                                    temp: d.Workers[i].Core_Temp || 0
                                })
                            }
                            totalGpu += d.Algorithms[0].Total_Performance || 0
                        }
                    } catch(e) {}
                }
                checkComplete()
            }
        }
        xhrNexusNv.open("GET", "http://" + nodes.nexus.ip + ":" + nodes.nexus.lolminer + "/")
        xhrNexusNv.send()
        
        // Forge AMD
        pending++
        var xhrForgeAmd = new XMLHttpRequest()
        xhrForgeAmd.onreadystatechange = function() {
            if (xhrForgeAmd.readyState === XMLHttpRequest.DONE) {
                if (xhrForgeAmd.status === 200) {
                    try {
                        var d = JSON.parse(xhrForgeAmd.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "forge",
                                    type: "amd",
                                    index: i,
                                    gpu: d.Workers[i].Name || "RX 5700 XT",
                                    hashrate: d.Algorithms[0].Worker_Performance[i] || 0,
                                    temp: d.Workers[i].Core_Temp || 0
                                })
                            }
                            totalGpu += d.Algorithms[0].Total_Performance || 0
                        }
                    } catch(e) {}
                }
                checkComplete()
            }
        }
        xhrForgeAmd.open("GET", "http://" + nodes.forge.ip + ":" + nodes.forge.lolminerAmd + "/")
        xhrForgeAmd.send()
        
        // Forge NVIDIA
        pending++
        var xhrForgeNv = new XMLHttpRequest()
        xhrForgeNv.onreadystatechange = function() {
            if (xhrForgeNv.readyState === XMLHttpRequest.DONE) {
                if (xhrForgeNv.status === 200) {
                    try {
                        var d = JSON.parse(xhrForgeNv.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "forge",
                                    type: "nvidia",
                                    index: i,
                                    gpu: d.Workers[i].Name || "RTX 4060",
                                    hashrate: d.Algorithms[0].Worker_Performance[i] || 0,
                                    temp: d.Workers[i].Core_Temp || 0
                                })
                            }
                            totalGpu += d.Algorithms[0].Total_Performance || 0
                        }
                    } catch(e) {}
                }
                checkComplete()
            }
        }
        xhrForgeNv.open("GET", "http://" + nodes.forge.ip + ":" + nodes.forge.lolminerNvidia + "/")
        xhrForgeNv.send()
        
        // === CPU Miners ===
        
        var xmrigNodes = ["zephyr", "nexus", "sentry"]
        for (var n = 0; n < xmrigNodes.length; n++) {
            pending++
            ;(function(nodeName) {
                var xhr = new XMLHttpRequest()
                xhr.onreadystatechange = function() {
                    if (xhr.readyState === XMLHttpRequest.DONE) {
                        if (xhr.status === 200) {
                            try {
                                var d = JSON.parse(xhr.responseText)
                                cpus.push({
                                    node: nodeName,
                                    hashrate: d.hashrate.total[0] || 0,
                                    shares: d.results.shares_good || 0
                                })
                                totalCpu += d.hashrate.total[0] || 0
                            } catch(e) {}
                        }
                        checkComplete()
                    }
                }
                xhr.open("GET", "http://" + nodes[nodeName].ip + ":" + nodes[nodeName].xmrig + "/1/summary")
                xhr.send()
            })(xmrigNodes[n])
        }
    }
}
