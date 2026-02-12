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
        "zephyr": { ip: "100.81.182.5", lolminer: 4068, xmrig: 8081 },
        "nexus": { ip: "100.86.158.18", lolminer: 4068, xmrig: 8081 },
        "forge": { ip: "100.95.222.45", lolminerAmd: 4069, lolminerNvidia: 4068, xmrig: 8081 },
        "sentry": { ip: "100.82.210.39", xmrig: 8081 }
    })
    
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
                text: "GPU: " + root.totalGpuHashrate + " g/s"
                font.bold: true
                font.pixelSize: Math.min(parent.width, parent.height) * 0.25
                color: Kirigami.Theme.textColor
            }
            
            PlasmaComponents.Label {
                text: "|"
                font.pixelSize: Math.min(parent.width, parent.height) * 0.25
                color: Kirigami.Theme.textColor
                opacity: 0.5
            }
            
            PlasmaComponents.Label {
                text: "CPU: " + root.totalCpuHashrate + " kH/s"
                font.bold: true
                font.pixelSize: Math.min(parent.width, parent.height) * 0.25
                color: Kirigami.Theme.textColor
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
        Layout.minimumWidth: 400
        Layout.minimumHeight: 500
        Layout.preferredWidth: 500
        Layout.preferredHeight: 600
        
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.4)
        radius: 20
        
        Timer {
            interval: 5000
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
                height: 35
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                radius: 10
                
                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: "⛏️ Cluster Mining Monitor"
                    font.bold: true
                    font.pixelSize: 14
                }
            }
            
            // Totals Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                
                Rectangle {
                    Layout.fillWidth: true
                    height: 60
                    color: Qt.rgba(0.46, 0.73, 0, 0.15)
                    radius: 12
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        PlasmaComponents.Label { text: "GPU Total"; font.pixelSize: 10; opacity: 0.7 }
                        PlasmaComponents.Label { text: root.totalGpuHashrate + " g/s"; font.bold: true; font.pixelSize: 18 }
                    }
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    height: 60
                    color: Qt.rgba(0.2, 0.6, 0.8, 0.15)
                    radius: 12
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        PlasmaComponents.Label { text: "CPU Total"; font.pixelSize: 10; opacity: 0.7 }
                        PlasmaComponents.Label { text: root.totalCpuHashrate + " kH/s"; font.bold: true; font.pixelSize: 18 }
                    }
                }
            }
            
            // GPU Section
            PlasmaComponents.Label {
                text: "🎮 GPU Miners"
                font.bold: true
                font.pixelSize: 12
            }
            
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                
                ColumnLayout {
                    id: gpuList
                    width: parent.width
                    spacing: 4
                    
                    Repeater {
                        model: root.gpuData
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.b, 0.3)
                            radius: 8
                            border.color: Qt.rgba(1, 1, 1, 0.05)
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                
                                PlasmaComponents.Label {
                                    text: modelData.node
                                    font.bold: true
                                    font.pixelSize: 11
                                    Layout.preferredWidth: 60
                                }
                                
                                PlasmaComponents.Label {
                                    text: modelData.gpu
                                    font.pixelSize: 10
                                    opacity: 0.8
                                    Layout.preferredWidth: 100
                                }
                                
                                PlasmaComponents.Label {
                                    text: modelData.hashrate.toFixed(2) + " g/s"
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                                
                                Item { Layout.fillWidth: true }
                                
                                PlasmaComponents.Label {
                                    text: modelData.temp + "°C"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: modelData.temp > 80 ? "#FF6B6B" : 
                                           modelData.temp > 70 ? "#FFE066" : "#69DB7C"
                                }
                            }
                        }
                    }
                }
            }
            
            // CPU Section
            PlasmaComponents.Label {
                text: "💻 CPU Miners"
                font.bold: true
                font.pixelSize: 12
            }
            
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                
                Repeater {
                    model: root.cpuData
                    
                    Rectangle {
                        Layout.fillWidth: true
                        height: 50
                        color: Qt.rgba(0.2, 0.6, 0.8, 0.1)
                        radius: 8
                        
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            
                            PlasmaComponents.Label {
                                text: modelData.node
                                font.bold: true
                                font.pixelSize: 10
                            }
                            
                            PlasmaComponents.Label {
                                text: (modelData.hashrate / 1000).toFixed(1) + " kH/s"
                                font.pixelSize: 12
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
        }
    }
    
    // Data fetching functions
    function fetchAllData() {
        var gpus = []
        var cpus = []
        var totalGpu = 0
        var totalCpu = 0
        
        // Counter for async completion
        var pending = 0
        var completed = 0
        
        function checkComplete() {
            completed++
            if (completed >= pending) {
                root.gpuData = gpus
                root.cpuData = cpus
                root.totalGpuHashrate = totalGpu.toFixed(2)
                root.totalCpuHashrate = (totalCpu / 1000).toFixed(1)
            }
        }
        
        // Fetch Zephyr lolminer
        pending++
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var d = JSON.parse(xhr.responseText)
                        if (d.Workers && d.Algorithms) {
                            for (var i = 0; i < d.Workers.length; i++) {
                                gpus.push({
                                    node: "zephyr",
                                    gpu: d.Workers[i].Name || "GPU " + i,
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
        xhr.open("GET", "http://" + nodes.zephyr.ip + ":" + nodes.zephyr.lolminer + "/")
        xhr.send()
        
        // Fetch Nexus lolminer
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
                                    node: "nexus",
                                    gpu: d.Workers[i].Name || "GPU " + i,
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
        xhr2.open("GET", "http://" + nodes.nexus.ip + ":" + nodes.nexus.lolminer + "/")
        xhr2.send()
        
        // Fetch Forge AMD lolminer
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
                                    node: "forge",
                                    gpu: d.Workers[i].Name || "AMD GPU " + i,
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
        xhr3.open("GET", "http://" + nodes.forge.ip + ":" + nodes.forge.lolminerAmd + "/")
        xhr3.send()
        
        // Fetch Forge NVIDIA lolminer
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
                                    node: "forge",
                                    gpu: d.Workers[i].Name || "NVIDIA GPU " + i,
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
        xhr4.open("GET", "http://" + nodes.forge.ip + ":" + nodes.forge.lolminerNvidia + "/")
        xhr4.send()
        
        // Fetch xmrig from each node
        var xmrigNodes = ["zephyr", "nexus", "sentry"]
        for (var n = 0; n < xmrigNodes.length; n++) {
            pending++
            (function(nodeName) {
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
