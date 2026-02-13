import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root
    
    // Node configuration - Tailscale IPs
    readonly property var nodes: ({
        "zephyr": { ip: "100.81.182.5", lolminer: 4068, xmrig: 8081, hasNvidia: true, hasCpu: true },
        "nexus": { ip: "100.86.158.18", lolminer: 4068, xmrig: 8081, hasNvidia: true, hasCpu: true },
        "forge": { ip: "100.95.222.45", lolminerAmd: 4069, lolminerNvidia: 4068, hasAmd: true, hasNvidia: true },
        "sentry": { ip: "100.82.210.39", xmrig: 8081, hasCpu: true }
    })
    
    // Colors
    readonly property color amdColor: Qt.rgba(1, 0.42, 0.21, 1.0)
    readonly property color nvidiaColor: Qt.rgba(0.46, 0.73, 0, 1.0)
    readonly property color cpuColor: Qt.rgba(0.2, 0.6, 0.8, 1.0)
    readonly property color stopColor: Qt.rgba(0.9, 0.2, 0.2, 1.0)
    readonly property color startColor: Qt.rgba(0.2, 0.8, 0.2, 1.0)
    
    // Data storage
    property var gpuData: []
    property var cpuData: []
    property string totalGpuHashrate: "0.00"
    property string totalCpuHashrate: "0.00"
    property bool controlsExpanded: false
    
    // Command runner
    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            if (data["exit code"] > 0) {
                console.log("Command failed:", data["Standard Error"] || data["exit code"])
            }
            disconnectedSources.append(sourceName)
        }
        
        function run(cmd) {
            connectSource(cmd)
        }
    }
    
    // Compact representation for panel
    compactRepresentation: Rectangle {
        id: compactRoot
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.highlightColor, Kirigami.Theme.backgroundColor, 0.9)
        border.color: Kirigami.Theme.highlightColor
        border.width: 1
        radius: 4
        
        Timer {
            interval: 5000
            running: true
            repeat: true
            onTriggered: root.fetchAllData()
            Component.onCompleted: root.fetchAllData()
        }
        
        RowLayout {
            anchors.centerIn: parent
            spacing: 4
            
            PlasmaComponents.Label {
                text: "⛏️"
                font.pixelSize: Math.min(compactRoot.width, compactRoot.height) * 0.35
            }
            
            PlasmaComponents.Label {
                text: root.totalGpuHashrate + " g"
                font.bold: true
                font.pixelSize: Math.min(compactRoot.width, compactRoot.height) * 0.22
                color: nvidiaColor
            }
            
            PlasmaComponents.Label {
                text: root.totalCpuHashrate + " k"
                font.bold: true
                font.pixelSize: Math.min(compactRoot.width, compactRoot.height) * 0.22
                color: cpuColor
            }
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }
    
    // Full representation
    fullRepresentation: Rectangle {
        id: fullRoot
        Layout.minimumWidth: 450
        Layout.minimumHeight: 600
        Layout.preferredWidth: 520
        Layout.preferredHeight: 700
        
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.4)
        radius: 20
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        
        Timer {
            interval: 5000
            running: true
            repeat: true
            onTriggered: root.fetchAllData()
            Component.onCompleted: root.fetchAllData()
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6
            
            // Title with controls toggle
            Rectangle {
                Layout.fillWidth: true
                height: 32
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                radius: 10
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    
                    PlasmaComponents.Label {
                        text: "⛏️ Mining Monitor"
                        font.bold: true
                        font.pixelSize: 13
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    PlasmaComponents.Button {
                        text: root.controlsExpanded ? "▼ Controls" : "▶ Controls"
                        implicitHeight: 22
                        font.pixelSize: 9
                        onClicked: root.controlsExpanded = !root.controlsExpanded
                    }
                }
            }
            
            // Totals Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                
                Rectangle {
                    Layout.fillWidth: true
                    height: 50
                    color: Qt.rgba(nvidiaColor.r, nvidiaColor.g, nvidiaColor.b, 0.12)
                    radius: 10
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        PlasmaComponents.Label { text: "🎮 GPU"; font.pixelSize: 9; opacity: 0.7 }
                        PlasmaComponents.Label { text: root.totalGpuHashrate + " g/s"; font.bold: true; font.pixelSize: 16; color: nvidiaColor }
                    }
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    height: 50
                    color: Qt.rgba(cpuColor.r, cpuColor.g, cpuColor.b, 0.12)
                    radius: 10
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        PlasmaComponents.Label { text: "💻 CPU"; font.pixelSize: 9; opacity: 0.7 }
                        PlasmaComponents.Label { text: root.totalCpuHashrate + " kH/s"; font.bold: true; font.pixelSize: 16; color: cpuColor }
                    }
                }
            }
            
            // Controls Panel (collapsible)
            Rectangle {
                Layout.fillWidth: true
                height: root.controlsExpanded ? 80 : 0
                visible: root.controlsExpanded
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.3)
                radius: 8
                clip: true
                
                Behavior on height { NumberAnimation { duration: 200 } }
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    
                    PlasmaComponents.Label {
                        text: "Cluster Controls"
                        font.pixelSize: 10
                        font.bold: true
                    }
                    
                    RowLayout {
                        spacing: 6
                        
                        PlasmaComponents.Button {
                            text: "⏹ Stop All Miners"
                            implicitHeight: 24
                            font.pixelSize: 9
                            onClicked: root.controlAllMiners("stop")
                        }
                        
                        PlasmaComponents.Button {
                            text: "▶ Start All Miners"
                            implicitHeight: 24
                            font.pixelSize: 9
                            onClicked: root.controlAllMiners("start")
                        }
                        
                        PlasmaComponents.Button {
                            text: "🔄 Refresh"
                            implicitHeight: 24
                            font.pixelSize: 9
                            onClicked: root.fetchAllData()
                        }
                    }
                }
            }
            
            // GPU Section
            PlasmaComponents.Label {
                text: "🔥 GPU Miners (" + root.gpuData.length + ")"
                font.bold: true
                font.pixelSize: 11
                color: amdColor
            }
            
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                model: root.gpuData
                spacing: 2
                clip: true
                
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 36
                    color: modelData.type === "amd" ? 
                        Qt.rgba(amdColor.r, amdColor.g, amdColor.b, 0.1) :
                        Qt.rgba(nvidiaColor.r, nvidiaColor.g, nvidiaColor.b, 0.1)
                    radius: 6
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 5
                        
                        PlasmaComponents.Label {
                            text: modelData.type === "amd" ? "🔥" : "💚"
                            font.pixelSize: 11
                        }
                        
                        PlasmaComponents.Label {
                            text: modelData.node
                            font.bold: true
                            font.pixelSize: 9
                            Layout.preferredWidth: 45
                        }
                        
                        PlasmaComponents.Label {
                            text: modelData.hashrate.toFixed(2) + " g/s"
                            font.pixelSize: 10
                            font.bold: true
                            Layout.preferredWidth: 60
                        }
                        
                        PlasmaComponents.Label {
                            text: modelData.temp + "°"
                            font.pixelSize: 9
                            color: modelData.temp > 80 ? "#FF6B6B" : modelData.temp > 70 ? "#FFE066" : "#69DB7C"
                            Layout.preferredWidth: 32
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: modelData.active ? startColor : stopColor
                        }
                        
                        // Control buttons (show when controls expanded)
                        PlasmaComponents.Button {
                            visible: root.controlsExpanded
                            text: modelData.active ? "⏹" : "▶"
                            implicitWidth: 24
                            implicitHeight: 20
                            font.pixelSize: 9
                            onClicked: root.controlMiner(modelData.node, modelData.type, modelData.active ? "stop" : "start")
                        }
                    }
                }
            }
            
            // CPU Section
            PlasmaComponents.Label {
                text: "💻 CPU Miners (" + root.cpuData.length + ")"
                font.bold: true
                font.pixelSize: 11
                color: cpuColor
            }
            
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                
                Repeater {
                    model: root.cpuData
                    
                    Rectangle {
                        Layout.fillWidth: true
                        height: root.controlsExpanded ? 70 : 55
                        color: Qt.rgba(cpuColor.r, cpuColor.g, cpuColor.b, 0.08)
                        radius: 6
                        
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 1
                            
                            RowLayout {
                                PlasmaComponents.Label {
                                    text: modelData.node
                                    font.bold: true
                                    font.pixelSize: 9
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 5
                                    height: 5
                                    radius: 2
                                    color: modelData.active ? startColor : stopColor
                                }
                            }
                            
                            PlasmaComponents.Label {
                                text: (modelData.hashrate / 1000).toFixed(1) + " kH/s"
                                font.pixelSize: 11
                                font.bold: true
                                color: cpuColor
                            }
                            
                            PlasmaComponents.Label {
                                text: modelData.shares + " shares"
                                font.pixelSize: 8
                                opacity: 0.6
                            }
                            
                            // Control buttons
                            RowLayout {
                                visible: root.controlsExpanded
                                spacing: 2
                                
                                PlasmaComponents.Button {
                                    text: "⏹"
                                    implicitWidth: 22
                                    implicitHeight: 16
                                    font.pixelSize: 8
                                    onClicked: root.controlMiner(modelData.node, "xmrig", "stop")
                                }
                                
                                PlasmaComponents.Button {
                                    text: "▶"
                                    implicitWidth: 22
                                    implicitHeight: 16
                                    font.pixelSize: 8
                                    onClicked: root.controlMiner(modelData.node, "xmrig", "start")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Control functions using SSH
    function controlMiner(node, minerType, action) {
        var service = ""
        if (minerType === "amd") {
            service = "lolminer-amd"
        } else if (minerType === "nvidia") {
            service = "lolminer-nvidia"
        } else if (minerType === "xmrig" || minerType === "cpu") {
            service = "xmrig"
        }
        
        var cmd = "ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no j_kro@" + nodes[node].ip + " 'sudo systemctl " + action + " " + service + "'"
        console.log("Running:", cmd)
        executable.run(cmd)
        
        // Refresh after delay
        QTimer.singleShot(3000, fetchAllData)
    }
    
    function controlAllMiners(action) {
        for (var node in nodes) {
            if (nodes[node].hasNvidia) {
                controlMiner(node, "nvidia", action)
            }
            if (nodes[node].hasAmd) {
                controlMiner(node, "amd", action)
            }
            if (nodes[node].hasCpu) {
                controlMiner(node, "xmrig", action)
            }
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
                gpus.sort(function(a, b) {
                    if (a.type !== b.type) return a.type === "amd" ? -1 : 1
                    if (a.node !== b.node) return a.node.localeCompare(b.node)
                    return a.index - b.index
                })
                cpus.sort(function(a, b) { return a.node.localeCompare(b.node) })
                root.gpuData = gpus
                root.cpuData = cpus
                root.totalGpuHashrate = totalGpu.toFixed(2)
                root.totalCpuHashrate = (totalCpu / 1000).toFixed(1)
            }
        }
        
        // Zephyr NVIDIA
        pending++
        var xhr1 = new XMLHttpRequest()
        xhr1.onreadystatechange = function() {
            if (xhr1.readyState === XMLHttpRequest.DONE) {
                if (xhr1.status === 200) {
                    try {
                        var d = JSON.parse(xhr1.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "zephyr", type: "nvidia", index: i,
                                    gpu: d.Workers[i].Name || "GPU", hashrate: d.Algorithms[0].Worker_Performance[i] || 0,
                                    temp: d.Workers[i].Core_Temp || 0, active: true
                                })
                            }
                            totalGpu += d.Algorithms[0].Total_Performance || 0
                        }
                    } catch(e) {}
                }
                checkComplete()
            }
        }
        xhr1.open("GET", "http://" + nodes.zephyr.ip + ":" + nodes.zephyr.lolminer + "/")
        xhr1.send()
        
        // Nexus NVIDIA
        pending++
        var xhr2 = new XMLHttpRequest()
        xhr2.onreadystatechange = function() {
            if (xhr2.readyState === XMLHttpRequest.DONE) {
                if (xhr2.status === 200) {
                    try {
                        var d = JSON.parse(xhr2.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "nexus", type: "nvidia", index: i,
                                    gpu: d.Workers[i].Name || "GPU", hashrate: d.Algorithms[0].Worker_Performance[i] || 0,
                                    temp: d.Workers[i].Core_Temp || 0, active: true
                                })
                            }
                            totalGpu += d.Algorithms[0].Total_Performance || 0
                        }
                    } catch(e) {}
                }
                checkComplete()
            }
        }
        xhr2.open("GET", "http://" + nodes.nexus.ip + ":" + nodes.nexus.lolminer + "/")
        xhr2.send()
        
        // Forge AMD
        pending++
        var xhr3 = new XMLHttpRequest()
        xhr3.onreadystatechange = function() {
            if (xhr3.readyState === XMLHttpRequest.DONE) {
                if (xhr3.status === 200) {
                    try {
                        var d = JSON.parse(xhr3.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "forge", type: "amd", index: i,
                                    gpu: d.Workers[i].Name || "AMD", hashrate: d.Algorithms[0].Worker_Performance[i] || 0,
                                    temp: d.Workers[i].Core_Temp || 0, active: true
                                })
                            }
                            totalGpu += d.Algorithms[0].Total_Performance || 0
                        }
                    } catch(e) {}
                }
                checkComplete()
            }
        }
        xhr3.open("GET", "http://" + nodes.forge.ip + ":" + nodes.forge.lolminerAmd + "/")
        xhr3.send()
        
        // Forge NVIDIA
        pending++
        var xhr4 = new XMLHttpRequest()
        xhr4.onreadystatechange = function() {
            if (xhr4.readyState === XMLHttpRequest.DONE) {
                if (xhr4.status === 200) {
                    try {
                        var d = JSON.parse(xhr4.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "forge", type: "nvidia", index: i,
                                    gpu: d.Workers[i].Name || "NVIDIA", hashrate: d.Algorithms[0].Worker_Performance[i] || 0,
                                    temp: d.Workers[i].Core_Temp || 0, active: true
                                })
                            }
                            totalGpu += d.Algorithms[0].Total_Performance || 0
                        }
                    } catch(e) {}
                }
                checkComplete()
            }
        }
        xhr4.open("GET", "http://" + nodes.forge.ip + ":" + nodes.forge.lolminerNvidia + "/")
        xhr4.send()
        
        // CPU Miners
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
                                    shares: d.results.shares_good || 0,
                                    active: true
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
