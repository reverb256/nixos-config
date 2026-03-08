import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Item {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground
    Plasmoid.toolTipMainText: "Systems Intelligence"
    Plasmoid.toolTipSubText: qsTr("Cluster-wide monitoring")
    Plasmoid.icon: "view-statistics"
    Plasmoid.switchWidth: units.gridUnit * 25
    Plasmoid.switchHeight: units.gridUnit * 20

    // Configuration
    property string prometheusUrl: Plasmoid.configuration.PrometheusUrl || "http://127.0.0.1:9090"
    property int refreshInterval: Plasmoid.configuration.RefreshInterval || 5000
    property string clusterNodes: Plasmoid.configuration.ClusterNodes || "zephyr,nexus,forge,sentry"

    property var nodeHealth: ({})
    property var nodeResources: ({})
    property var gpuStats: []
    property var alerts: []
    property var miningStats: ({})

    Timer {
        id: refreshTimer
        interval: root.refreshInterval
        running: true
        repeat: true
        onTriggered: {
            fetchAllMetrics()
        }
    }

    Component.onCompleted: {
        fetchAllMetrics()
    }

    function fetchAllMetrics() {
        fetchNodeHealth()
        fetchNodeResources()
        fetchGPUStats()
        fetchAlerts()
        fetchMiningStats()
    }

    // Fetch node up/down status
    function fetchNodeHealth() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        const data = JSON.parse(xhr.responseText)
                        const result = data.data.result || []
                        nodeHealth = {}
                        result.forEach(item => {
                            const instance = item.metric.instance || item.metric.job || "unknown"
                            nodeHealth[instance] = item.value[1] === "1"
                        })
                    } catch (e) {
                        console.error("Failed to parse node health:", e)
                    }
                }
            }
        }
        xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=up{job=\"node\"}")
        xhr.send()
    }

    // Fetch CPU, Memory, Disk usage
    function fetchNodeResources() {
        const queries = {
            cpu: '100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100',
            memory: '(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100',
            disk: '(1 - node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"}) * 100'
        }

        Object.keys(queries).forEach(metric => {
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            const data = JSON.parse(xhr.responseText)
                            const result = data.data.result || []
                            result.forEach(item => {
                                const instance = item.metric.instance || "unknown"
                                if (!nodeResources[instance]) nodeResources[instance] = {}
                                nodeResources[instance][metric] = parseFloat(item.value[1])
                            })
                        } catch (e) {
                            console.error("Failed to parse", metric, ":", e)
                        }
                    }
                }
            }
            xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=" + encodeURIComponent(queries[metric]))
            xhr.send()
        })
    }

    // Fetch GPU statistics
    function fetchGPUStats() {
        const queries = {
            utilization: 'nvidia_smi_utilization_gpu_ratio * 100',
            temperature: 'nvidia_smi_temperature_gpu',
            power: 'nvidia_smi_power_draw_watts',
            memory: 'nvidia_smi_memory_used_bytes / nvidia_smi_memory_total_bytes * 100'
        }

        let pending = Object.keys(queries).length
        const results = {}

        Object.keys(queries).forEach(metric => {
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            const data = JSON.parse(xhr.responseText)
                            const result = data.data.result || []
                            results[metric] = result
                            pending--
                            if (pending === 0) {
                                processGPUStats(results)
                            }
                        } catch (e) {}
                    }
                }
            }
            xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=" + encodeURIComponent(queries[metric]))
            xhr.send()
        })
    }

    function processGPUStats(results) {
        gpuStats = []
        // Group by GPU
        const gpuMap = {}
        Object.keys(results).forEach(metric => {
            results[metric].forEach(item => {
                const instance = item.metric.instance || "unknown"
                if (!gpuMap[instance]) gpuMap[instance] = {instance: instance}
                gpuMap[instance][metric] = parseFloat(item.value[1])
            })
        })
        gpuStats = Object.values(gpuMap)
    }

    // Fetch active alerts
    function fetchAlerts() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        const data = JSON.parse(xhr.responseText)
                        alerts = data.data.result || []
                    } catch (e) {}
                }
            }
        }
        xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=ALERTS{alertstate=\"firing\"}")
        xhr.send()
    }

    // Fetch mining stats
    function fetchMiningStats() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        const data = JSON.parse(xhr.responseText)
                        const result = data.data.result || []
                        miningStats = {}
                        let totalHashrate = 0
                        result.forEach(item => {
                            const host = item.metric.host || item.metric.instance || "unknown"
                            const hashrate = parseFloat(item.value[1])
                            miningStats[host] = hashrate
                            totalHashrate += hashrate
                        })
                        miningStats.total = totalHashrate
                    } catch (e) {}
                }
            }
        }
        xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=mining_worker_hashrate")
        xhr.send()
    }

    // Full representation
    Plasmoid.fullRepresentation: ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: units.smallSpacing

        // Header
        Kirigami.Heading {
            level: 2
            text: "🖥️ Systems Intelligence"
            Layout.alignment: Qt.AlignHCenter
        }

        // Cluster Health Row
        RowLayout {
            Layout.fillWidth: true
            spacing: units.smallSpacing

            Repeater {
                model: Object.keys(nodeHealth)

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: units.gridUnit * 3

                    Rectangle {
                        anchors.fill: parent
                        color: nodeHealth[modelData] ? "#2ecc71" : "#e74c3c"
                        radius: units.smallSpacing / 2
                        opacity: 0.2

                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: units.smallSpacing / 2

                        Text {
                            text: modelData
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }

        // Scrollable content
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: units.smallSpacing

                // Node Resources Section
                GroupBox {
                    title: "📊 Node Resources"
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: units.smallSpacing

                        Repeater {
                            model: Object.keys(nodeResources)

                            RowLayout {
                                spacing: units.smallSpacing

                                Text {
                                    text: modelData
                                    Layout.preferredWidth: units.gridUnit * 5
                                    font.bold: true
                                }

                                // CPU
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: units.gridUnit * 1.5

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#34495e"
                                        radius: 2

                                        Rectangle {
                                            width: parent.width * (nodeResources[modelData]?.cpu || 0) / 100
                                            height: parent.height
                                            color: {
                                                const v = nodeResources[modelData]?.cpu || 0
                                                if (v < 50) return "#2ecc71"
                                                if (v < 80) return "#f39c12"
                                                return "#e74c3c"
                                            }
                                            radius: 2
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Math.round(nodeResources[modelData]?.cpu || 0) + "%"
                                            font.pixelSize: units.smallSpacing
                                            color: "white"
                                        }
                                    }
                                }

                                // Memory
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: units.gridUnit * 1.5

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#34495e"
                                        radius: 2

                                        Rectangle {
                                            width: parent.width * (nodeResources[modelData]?.memory || 0) / 100
                                            height: parent.height
                                            color: {
                                                const v = nodeResources[modelData]?.memory || 0
                                                if (v < 50) return "#2ecc71"
                                                if (v < 80) return "#f39c12"
                                                return "#e74c3c"
                                            }
                                            radius: 2
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "RAM:" + Math.round(nodeResources[modelData]?.memory || 0) + "%"
                                            font.pixelSize: units.smallSpacing
                                            color: "white"
                                        }
                                    }
                                }

                                // Disk
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: units.gridUnit * 1.5

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#34495e"
                                        radius: 2

                                        Rectangle {
                                            width: parent.width * (nodeResources[modelData]?.disk || 0) / 100
                                            height: parent.height
                                            color: {
                                                const v = nodeResources[modelData]?.disk || 0
                                                if (v < 50) return "#2ecc71"
                                                if (v < 80) return "#f39c12"
                                                return "#e74c3c"
                                            }
                                            radius: 2
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "DSK:" + Math.round(nodeResources[modelData]?.disk || 0) + "%"
                                            font.pixelSize: units.smallSpacing
                                            color: "white"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // GPU Section
                GroupBox {
                    title: "🎮 GPU Status"
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: units.smallSpacing

                        Repeater {
                            model: gpuStats.length

                            RowLayout {
                                spacing: units.smallSpacing

                                Text {
                                    text: gpuStats[modelData]?.instance || ""
                                    Layout.preferredWidth: units.gridUnit * 5
                                    font.bold: true
                                }

                                // Utilization
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: units.gridUnit * 1.5

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#34495e"
                                        radius: 2

                                        Rectangle {
                                            width: parent.width * (gpuStats[modelData]?.utilization || 0) / 100
                                            height: parent.height
                                            color: "#3498db"
                                            radius: 2
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Math.round(gpuStats[modelData]?.utilization || 0) + "%"
                                            font.pixelSize: units.smallSpacing
                                            color: "white"
                                        }
                                    }
                                }

                                // Temperature
                                Text {
                                    text: Math.round(gpuStats[modelData]?.temperature || 0) + "°C"
                                    Layout.preferredWidth: units.gridUnit * 3
                                    font.pixelSize: units.smallSpacing
                                    color: {
                                        const t = gpuStats[modelData]?.temperature || 0
                                        if (t < 60) return "#2ecc71"
                                        if (t < 75) return "#f39c12"
                                        return "#e74c3c"
                                    }
                                }

                                // Power
                                Text {
                                    text: Math.round(gpuStats[modelData]?.power || 0) + "W"
                                    font.pixelSize: units.smallSpacing
                                    color: "#95a5a6"
                                }
                            }
                        }
                    }
                }

                // Mining Section
                GroupBox {
                    title: "⛏️ Mining"
                    Layout.fillWidth: true
                    visible: miningStats.total > 0

                    ColumnLayout {
                        spacing: units.smallSpacing

                        Text {
                            text: "Total: " + formatHashrate(miningStats.total || 0)
                            font.bold: true
                        }

                        Repeater {
                            model: Object.keys(miningStats).filter(k => k !== "total")

                            RowLayout {
                                Text {
                                    text: modelData + ":"
                                    Layout.preferredWidth: units.gridUnit * 5
                                }
                                Text {
                                    text: formatHashrate(miningStats[modelData] || 0)
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                // Alerts Section
                GroupBox {
                    title: "🚨 Alerts (" + alerts.length + ")"
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: units.smallSpacing

                        Repeater {
                            model: alerts.length

                            RowLayout {
                                spacing: units.smallSpacing

                                Rectangle {
                                    width: units.gridUnit / 2
                                    height: width
                                    radius: width / 2
                                    color: {
                                        const severity = alerts[modelData]?.metric?.severity || "warning"
                                        if (severity === "critical") return "#e74c3c"
                                        if (severity === "warning") return "#f39c12"
                                        return "#3498db"
                                    }
                                }

                                Text {
                                    text: alerts[modelData]?.metric?.alertname || "Unknown"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Text {
                            text: "No active alerts"
                            visible: alerts.length === 0
                            color: "#2ecc71"
                        }
                    }
                }

                Item { Layout.preferredHeight: units.smallSpacing }
            }
        }

        // Footer with last update
        Text {
            text: "Last update: " + new Date().toLocaleTimeString()
            font.pixelSize: units.smallSpacing * 0.8
            color: "#7f8c8d"
            Layout.alignment: Qt.AlignHCenter
        }
    }

    function formatHashrate(h) {
        if (h >= 1e12) return (h / 1e12).toFixed(1) + " TH/s"
        if (h >= 1e9) return (h / 1e9).toFixed(1) + " GH/s"
        if (h >= 1e6) return (h / 1e6).toFixed(1) + " MH/s"
        if (h >= 1e3) return (h / 1e3).toFixed(1) + " kH/s"
        return h.toFixed(0) + " H/s"
    }
}
