import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.extras 2.0 as PlasmaExtras

Item {
    id: root
    
    property string prometheusUrl: "http://127.0.0.1:9090"
    property int refreshInterval: 5000
    property bool showGpuTemps: true
    property bool showPowerUsage: true
    property bool showHashrate: true
    property bool compactMode: false
    
    property var gpuData: null
    
    Layout.minimumWidth: compactMode ? 300 : 400
    Layout.minimumHeight: showGpuTemps ? 400 : 200
    Layout.preferredWidth: compactMode ? 350 : 450
    Layout.preferredHeight: showGpuTemps ? 450 : 250
    
    Plasmoid.switchWidth: compactMode ? 300 : 400
    Plasmoid.switchHeight: showGpuTemps ? 400 : 200
    
    Timer {
        id: refreshTimer
        interval: refreshInterval
        repeat: true
        onTriggered: refreshData()
    }
    
    Component.onCompleted: {
        refreshData();
        refreshTimer.start();
    }
    
    function refreshData() {
        prometheusQuery('query?query=nvidia_smi_temperature_gpu+amdgpu_temperature_celsius{sensor="edge"}', function(data) {
            gpuData = data;
        });
        updatePowerAndHashrate();
    }
    
    function prometheusQuery(queryPath, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', prometheusUrl + '/api/v1/' + queryPath);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText);
                        callback(response.data.result);
                    } catch(e) {
                        console.error('Parse error:', e);
                    }
                }
            }
        };
        xhr.send();
    }
    
    function updatePowerAndHashrate() {
        prometheusQuery('query?query=sum(nvidia_smi_power_draw_watts)+sum(amdgpu_power_watts)', function(data) {
            if (data && data.length > 0) {
                powerLabel.text = Math.round(data[0].value[1]) + "W";
            }
        });
        
        prometheusQuery('query?query=sum(mining_xmrig_hashrate_total)', function(data) {
            if (data && data.length > 0) {
                var h = parseFloat(data[0].value[1]);
                hashrateLabel.text = formatHashrate(h);
            }
        });
    }
    
    function formatHashrate(h) {
        if (h < 1000) return Math.round(h) + " H/s";
        if (h < 1000000) return (h / 1000).toFixed(1) + " kH/s";
        return (h / 1000000).toFixed(2) + " MH/s";
    }
    
    ColumnLayout {
        anchors.fill: parent
        
        PlasmaExtras.PlasmoidHeading {
            Layout.fillWidth: true
            text: "⚡ Cluster Monitor"
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            
            PlasmaComponents3.Label {
                text: "🖥️ Nodes:"
                font.bold: true
            }
            
            PlasmaComponents3.Label {
                id: onlineNodes
                text: "Loading..."
                font.pixelSize: 14
            }
            
            Component.onCompleted: {
                prometheusQuery('query?query=count(up{job="node"} == 1)', function(data) {
                    if (data && data.length > 0) {
                        onlineNodes.text = data[0].value[1] + "/3 Online";
                    }
                });
            }
        }
        
        ColumnLayout {
            Layout.fillWidth: true
            visible: showGpuTemps
            
            PlasmaExtras.PlasmoidHeading {
                Layout.fillWidth: true
                level: 3
                text: "🌡️ GPU Temperatures"
            }
            
            Row {
                spacing: 10
                Repeater {
                    model: gpuData ? gpuData.length : 0
                    
                    Rectangle {
                        width: 100
                        height: 70
                        color: {
                            var temp = parseFloat(modelData.value[1]);
                            if (temp > 80) return "#ff6b6b";
                            if (temp > 70) return "#feca57";
                            return "#4ecdc4";
                        }()
                        radius: 5
                        
                        Column {
                            anchors.centerIn: parent
                            spacing: 5
                            
                            PlasmaComponents3.Label {
                                text: {
                                    var instance = modelData.metric.instance || "";
                                    if (instance.includes("10.1.1.110")) return "Zephyr";
                                    if (instance.includes("10.1.1.120")) return "Nexus";
                                    if (instance.includes("10.1.1.130")) return "Forge " + (modelData.metric.gpu ? "AMD" : "NV");
                                    return instance;
                                }()
                                font.bold: true
                                font.pixelSize: 11
                            }
                            
                            PlasmaComponents3.Label {
                                text: modelData.value[1] + "°C"
                                font.pixelSize: 18
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            visible: showPowerUsage || showHashrate
            spacing: 20
            
            ColumnLayout {
                Layout.fillWidth: true
                visible: showPowerUsage
                
                PlasmaComponents3.Label {
                    text: "⚡ Power"
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }
                
                PlasmaComponents3.Label {
                    id: powerLabel
                    text: "---W"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }
            }
            
            ColumnLayout {
                Layout.fillWidth: true
                visible: showHashrate
                
                PlasmaComponents3.Label {
                    text: "⛏️ Hashrate"
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }
                
                PlasmaComponents3.Label {
                    id: hashrateLabel
                    text: "---"
                    font.pixelSize: 20
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
