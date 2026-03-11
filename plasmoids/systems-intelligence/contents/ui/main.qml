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
    Plasmoid.toolTipSubText: qsTr("Cluster-wide monitoring with mining metrics")
    Plasmoid.icon: "view-statistics"
    Plasmoid.switchWidth: units.gridUnit * 30
    Plasmoid.switchHeight: units.gridUnit * 25

    // Configuration
    property string prometheusUrl: Plasmoid.configuration.PrometheusUrl || "http://127.0.0.1:9090"
    property int refreshInterval: Plasmoid.configuration.RefreshInterval || 5000
    property string clusterNodes: Plasmoid.configuration.ClusterNodes || "zephyr,nexus,forge,sentry"

    property var nodeHealth: ({})
    property var nodeResources: ({})
    property var gpuStats: []
    property var alerts: []
    property var miningStats: ({})
    property var workloadTypes: ({})  // NEW: Track workload type per host

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
        fetchWorkloadTypes()  // NEW: Fetch workload types
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
            xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=" + queries[metric])
            xhr.send()
        })
    }

    // Fetch GPU stats
    function fetchGPUStats() {
        const queries = {
            utilization: 'nvidia_smi_utilization_gpu_ratio * 100',
            temperature: 'nvidia_smi_temperature_gpu',
            power: 'nvidia_smi_power_draw',
            memoryUsed: 'nvidia_smi_fb_memory_usage',
            memoryTotal: 'nvidia_smi_fb_memory_total'
        }

        const gpuMap = {}
        Object.keys(queries).forEach(metric => {
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            const data = JSON.parse(xhr.responseText)
                            const result = data.data.result || []
                            result.forEach(item => {
                                const instance = item.metric.instance || item.metric.gpu || item.metric.hostname || "unknown"
                                if (!gpuMap[instance]) gpuMap[instance] = {instance: instance}
                                gpuMap[instance][metric] = parseFloat(item.value[1])
                            })
                            gpuStats = Object.values(gpuMap)
                        } catch (e) {
                            console.error("Failed to parse GPU stats:", e)
                        }
                    }
                }
            }
            xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=" + queries[metric])
            xhr.send()
        })
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

    // Fetch mining stats (GPU + CPU)
    function fetchMiningStats() {
        const queries = {
            gpuHashrate: 'mining_lolminer_hashrate_total',
            cpuHashrate: 'mining_xmrig_hashrate_total',
            gpuShares: 'rate(mining_lolminer_shares_accepted[5m])',
            cpuShares: 'rate(mining_xmrig_shares_accepted[5m])',
            gpuPower: 'mining_lolminer_power_watts',
            gpuTemp: 'mining_lolminer_temperature_celsius'
        }

        let totalHashrate = 0
        miningStats = {}

        Object.keys(queries).forEach(type => {
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            const data = JSON.parse(xhr.responseText)
                            const result = data.data.result || []
                            result.forEach(item => {
                                const instance = item.metric.instance || item.metric.host || "unknown"
                                const value = parseFloat(item.value[1])

                                if (!miningStats[instance]) miningStats[instance] = {}

                                if (type === 'gpuHashrate') {
                                    miningStats[instance].gpuHashrate = value
                                    totalHashrate += value
                                } else if (type === 'cpuHashrate') {
                                    miningStats[instance].cpuHashrate = value
                                    totalHashrate += value
                                } else if (type === 'gpuShares') {
                                    miningStats[instance].gpuShares = value
                                } else if (type === 'cpuShares') {
                                    miningStats[instance].cpuShares = value
                                } else if (type === 'gpuPower') {
                                    miningStats[instance].power = value
                                } else if (type === 'gpuTemp') {
                                    miningStats[instance].temp = value
                                }
                            })
                        } catch (e) {
                            console.error("Failed to parse mining stats:", e)
                        }
                    }
                }
            }
            xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=" + queries[type])
            xhr.send()
        })

        miningStats.total = totalHashrate
    }

    // NEW: Fetch workload type (mining/gaming/inference/idle)
    function fetchWorkloadTypes() {
        const clusterHosts = root.clusterNodes.split(',')
        clusterHosts.forEach(host => {
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            const data = JSON.parse(xhr.responseText)
                            const result = data.data.result || []
                            if (result.length > 0 && result[0].metric) {
                                workloadTypes[host] = result[0].metric.workload || "unknown"
                            }
                        } catch (e) {
                            // Default to mining if no workload label found
                            workloadTypes[host] = "mining"
                        }
                    }
                }
            }
            // Query workload type label (set by compute-workload-monitor)
            xhr.open("GET", root.prometheusUrl + "/api/v1/query?query=workload_type{host=\"" + host + "\"}")
            xhr.send()
        })
    }

    // Enhanced hashrate formatting with trend indicator
    function formatHashrate(h) {
        if (h >= 1e12) return (h / 1e12).toFixed(1) + " TH/s"
        if (h >= 1e9) return (h / 1e9).toFixed(1) + " GH/s"
        if (h >= 1e6) return (h / 1e6).toFixed(1) + " MH/s"
        if (h >= 1e3) return (h / 1e3).toFixed(1) + " kH/s"
        return h.toFixed(1) + " H/s"
    }

    // NEW: Get workload icon
    function getWorkloadIcon(host) {
        const type = workloadTypes[host] || "mining"
        switch(type) {
            case "gaming": return "🎮"
            case "inference": return "🤖"
            case "builds": return "🔨"
            case "idle": return "💤�"
            default: return "⛏️"
        }
    }

    // NEW: Get status color based on hashrate
    function getStatusColor(host) {
        const stats = miningStats[host] || {}
        if (stats.gpuHashrate > 0 || stats.cpuHashrate > 0) {
            return "#2ecc71"  // Green - mining
        }
        return "#95a5a6"  // Gray - not mining
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

                // GPU Section with alerts
                GroupBox {
                    title: "🎮 GPU Status" + (gpuStats.some(g => (g.temperature || 0) > 75) ? " ⚠️ HOT" : "")
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

                                // Temperature with color
                                Text {
                                    text: Math.round(gpuStats[modelData]?.temperature || 0) + "°C"
                                    Layout.preferredWidth: units.gridUnit * 3
                                    font.pixelSize: units.smallSpacing
                                    font.bold: (gpuStats[modelData]?.temperature || 0) > 75
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

                                // Memory usage
                                Text {
                                    const memUsed = Math.round((gpuStats[modelData]?.memoryUsed || 0) / 1024)
                                            const memTotal = Math.round((gpuStats[modelData]?.memoryTotal || 0) / 1024)
                                            text: memUsed + "/" + memTotal + "GB"
                                    Layout.preferredWidth: units.gridUnit * 4
                                    font.pixelSize: units.smallSpacing * 0.8
                                    color: "#95a5a6"
                                }
                            }
                        }
                    }
                }

                // ENHANCED Mining Section with more details
                GroupBox {
                    title: "⛏️ Mining Operations" + (miningStats.total > 0 ? " • Total: " + formatHashrate(miningStats.total || 0) : "")
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: units.smallSpacing

                        // Total hashrate prominently displayed
                        Text {
                            text: "💰 Total: " + formatHashrate(miningStats.total || 0)
                            font.bold: true
                            font.pixelSize: units.mediumSpacing
                            color: "#f1c40f"
                            visible: miningStats.total > 0
                        }

                        // Per-host breakdown with workload type
                        Repeater {
                            model: Object.keys(miningStats).filter(k => k !== "total")

                            ColumnLayout {
                                spacing: 2

                                RowLayout {
                                    spacing: units.smallSpacing

                                    // Workload type icon
                                    Text {
                                        text: getWorkloadIcon(modelData)
                                        font.pixelSize: units.mediumSpacing
                                    }

                                    // Host name
                                    Text {
                                        text: modelData + ":"
                                        Layout.preferredWidth: units.gridUnit * 5
                                        font.bold: true
                                    }

                                    // Total hashrate (GPU + CPU)
                                    Text {
                                        const stats = miningStats[modelData] || {}
                                        const total = (stats.gpuHashrate || 0) + (stats.cpuHashrate || 0)
                                        text: formatHashrate(total)
                                        Layout.fillWidth: true
                                        font.bold: true
                                        color: getStatusColor(modelData)
                                    }
                                }

                                // Detailed breakdown (indented)
                                RowLayout {
                                    Layout.leftMargin: units.gridUnit * 2
                                    spacing: units.smallSpacing

                                    Text {
                                        text: "GPU: " + formatHashrate(miningStats[modelData]?.gpuHashrate || 0)
                                        font.pixelSize: units.tinySpacing
                                        color: "#7f8c8d"
                                    }

                                    Text {
                                        text: "CPU: " + formatHashrate(miningStats[modelData]?.cpuHashrate || 0)
                                        font.pixelSize: units.tinySpacing
                                        color: "#7f8c8d"
                                    }

                                    // Share rate
                                    Text {
                                        const shares = (miningStats[modelData]?.gpuShares || 0) + (miningStats[modelData]?.cpuShares || 0)
                                        text: "✓ " + shares.toFixed(1) + "/s"
                                        font.pixelSize: units.tinySpacing
                                        color: shares > 0 ? "#2ecc71" : "#95a5a6"
                                    }

                                    // Temperature
                                    Text {
                                        const temp = miningStats[modelData]?.temp || 0
                                        text: "🌡 " + temp.toFixed(0) + "°C"
                                        font.pixelSize: units.tinySpacing
                                        visible: temp > 0
                                    }
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
                                    font.pixelSize: units.smallSpacing
                                }
                            }
                        }

                        Text {
                            text: "✓ No active alerts"
                            visible: alerts.length === 0
                            color: "#2ecc71"
                            font.pixelSize: units.smallSpacing
                        }
                    }
                }

                Item { Layout.preferredHeight: units.smallSpacing }
            }
        }

        // Footer with last update
        Text {
            text: "Last update: " + new Date().toLocaleTimeString() + " • Refresh: " + (root.refreshInterval / 1000) + "s"
            font.pixelSize: units.smallSpacing * 0.8
            color: "#7f8c8d"
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // Compact representation for panel
    Plasmoid.compactRepresentation: RowLayout {
        spacing: units.smallSpacing

        Text {
            text: "🖥️"
            font.pixelSize: units.largeSpacing
        }

        Text {
            text: formatHashrate(miningStats.total || 0)
            font.bold: true
            color: "#f1c40f"
        }

        Text {
            text: alerts.length > 0 ? "🚨" : "✓"
            font.pixelSize: units.mediumSpacing
        }
    }
}
