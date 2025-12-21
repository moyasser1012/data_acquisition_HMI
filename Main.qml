import QtQuick
import QtQuick.VirtualKeyboard
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtLocation
import QtPositioning
import Qt5Compat.GraphicalEffects
import QtWebSockets

ApplicationWindow {

    visible: true
    width: 1920
    height: 1200
    title: qsTr("GUI")

    property real qnhSetting: 1013.25

    property int airspeedUnit: 0
    property int altitudeUnit: 0
    property int vsiUnit: 0
    property int tempUnit: 0

    property int selectedIndex: 0

    property double ros_ts: 0
    property double esp_ts: 0
    property double latitude: 49.8728
    property double longitude: 8.6512

    property bool isRecording: false
    property string currentBagPath: ""

    property int flagValue: 0

    property real rollRate: 0
    property real pitchRate: 0
    property real yawRate: 0

    property real roll: 0
    property real pitch: 0
    property real yaw: 0

    property real vn: 0
    property real ve: 0
    property real vd: 0

    property real gpsSpeed: 0
    property real altitude: 0

    property real temperature: 0
    property real humidity: 0
    property real diff_pressure: 0
    property real baro_pressure: 0
    property real air_density: 0

    property real ias: 0
    property real tas: 0

    WebSocket {
        id: socket
        url: "ws://192.168.1.1:9099"  // first websocket server path
        active: true

        onTextMessageReceived: function(message){
            console.log("Received message: " + message)

            try {
                var response = JSON.parse(message)

                if (response.status === "success") {
                    statusText.text = response.message
                    statusText.color = "green"

                    if (response.recording !== undefined) {
                        // Status check response
                        isRecording = response.recording
                        recordButton.text = isRecording ? "Stop Recording" : "Record"

                        if (response.bag_path !== undefined) {
                            currentBagPath = response.bag_path
                        }
                    } else if (response.message.indexOf("Started recording") !== -1) {
                        isRecording = true
                        recordButton.text = "Stop Recording"
                        if (response.bag_path !== undefined) {
                            currentBagPath = response.bag_path
                        }
                    } else if (response.message.indexOf("stopped") !== -1 ||
                               response.message.indexOf("Stopped") !== -1) {
                        isRecording = false
                        recordButton.text = "Record"
                        currentBagPath = ""
                    }
                } else if (response.status === "error") {
                    statusText.text = "Error: " + response.message
                    statusText.color = "red"
                }
            } catch (e) {
                statusText.text = "Response: " + message
                statusText.color = "white"
            }
        }

        onStatusChanged: {
            if (socket.status === WebSocket.Error) {
                statusText.text = "Error: " + socket.errorString
                statusText.color = "red"
                reconnectTimer.start()
            } else if (socket.status === WebSocket.Open) {
                statusText.text = "Connected"
                statusText.color = "green"
                reconnectTimer.stop()
                // Request initial status
                statusCheckTimer.start()
            } else if (socket.status === WebSocket.Closed) {
                statusText.text = "Disconnected"
                statusText.color = "orange"
                reconnectTimer.start()
                statusCheckTimer.stop()
            } else if (socket.status === WebSocket.Connecting) {
                statusText.text = "Connecting..."
                statusText.color = "yellow"
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 3000  // Try to reconnect every 3 seconds
        repeat: true
        onTriggered: {
            if (socket.status !== WebSocket.Open && socket.status !== WebSocket.Connecting) {
                console.log("Attempting to reconnect...")
                statusText.text = "Reconnecting..."
                socket.active = false
                socket.active = true
            }
        }
    }

    Timer {
        id: statusCheckTimer
        interval: 3000  // Check status every 3 seconds
        repeat: true
        running: false
        onTriggered: {
            if (socket.status === WebSocket.Open) {
                socket.sendTextMessage("status")
            }
        }
    }


    WebSocket {
        id: socket1
        url: "ws://192.168.1.1:9090" // second websocket server path
        active: true

        property bool isConnected: false
        property string publishTopicName: "/app/flag"
        property string publishMessageType: "flag_msgs/msg/Flag"
        property bool isAdvertised: false
        property int reconnectAttempts: 0
        property int maxReconnectAttempts: 100

        // Subscription tracking
        property var subscribedTopics: ({})

        onTextMessageReceived: function(message) {
            try {
                var rosMsg = JSON.parse(message)

                if (rosMsg.op === "publish" && rosMsg.topic && rosMsg.msg) {
                    var topic = rosMsg.topic
                    var msg = rosMsg.msg

                    // Handle /fmu/out/sensor_combined
                    if (topic === "/fmu/out/sensor_combined") {
                        if (msg.timestamp !== undefined) {
                            ros_ts = msg.timestamp
                        }

                        // Gyroscope data (angular rates in rad/s)
                        if (msg.gyro_rad !== undefined && msg.gyro_rad.length >= 3) {
                            rollRate = msg.gyro_rad[0]
                            pitchRate = msg.gyro_rad[1]
                            yawRate = msg.gyro_rad[2]
                        }

                        // Barometer data
                        if (msg.baro_temp_celcius !== undefined) {
                            temperature = msg.baro_temp_celcius
                        }
                    }

                    // Handle /fmu/out/vehicle_gps_position
                    else if (topic === "/fmu/out/vehicle_gps_position") {
                        if (msg.lat !== undefined && msg.lon !== undefined) {
                            // Keep numeric values (avoid toFixed which converts to string)
                            latitude = msg.lat / 1e7
                            longitude = msg.lon / 1e7
                        }

                        if (msg.alt !== undefined) {
                            altitude = msg.alt
                        }

                        if (msg.vel_m_s !== undefined) {
                            gpsSpeed = msg.vel_m_s
                        }
                    }

                    // Handle /fmu/out/vehicle_odometry
                    else if (topic === "/fmu/out/vehicle_odometry") {
                        // Velocity in NED frame
                        if (msg.velocity !== undefined && msg.velocity.length >= 3) {
                            vn = msg.velocity[0]
                            ve = msg.velocity[1]
                            vd = msg.velocity[2]
                        }

                        // Attitude (quaternion to Euler angles)
                        if (msg.q !== undefined && msg.q.length >= 4) {
                            var q = msg.q
                            var qw = q[0]
                            var qx = q[1]
                            var qy = q[2]
                            var qz = q[3]

                            // Convert quaternion to Euler angles (in degrees)
                            // Roll (x-axis rotation)
                            var sinr_cosp = 2 * (qw * qx + qy * qz)
                            var cosr_cosp = 1 - 2 * (qx * qx + qy * qy)
                            roll = (Math.atan2(sinr_cosp, cosr_cosp) * 180 / Math.PI)

                            // Pitch (y-axis rotation)
                            var sinp = 2 * (qw * qy - qz * qx)
                            if (Math.abs(sinp) >= 1)
                                pitch = (Math.sign(sinp) * 90)
                            else
                                pitch = (Math.asin(sinp) * 180 / Math.PI)

                            // Yaw (z-axis rotation)
                            var siny_cosp = 2 * (qw * qz + qx * qy)
                            var cosy_cosp = 1 - 2 * (qy * qy + qz * qz)
                            yaw = (Math.atan2(siny_cosp, cosy_cosp) * 180 / Math.PI)
                        }
                    }

                    // Handle /esp32/wing_data
                    else if (topic === "/esp32/wing_data") {
                        if (msg.temperature !== undefined) {
                            temperature = msg.temperature
                        }
                        if (msg.humidity !== undefined) {
                            humidity = msg.humidity
                        }
                        if (msg.air_density !== undefined) {
                            air_density = msg.air_density
                        }
                        if (msg.timestamp !== undefined) {
                            esp_ts = msg.timestamp.toFixed(0)
                        }
                        if (msg.baro_pressure !== undefined) {
                            baro_pressure = msg.baro_pressure
                        }
                        if (msg.diff_pressure !== undefined) {
                            diff_pressure = msg.diff_pressure
                        }
                        // Calculate IAS and Tas from differential pressure and rho if available
                        if (diff_pressure > 0 && air_density > 0) {
                            ias = Math.sqrt(2 * diff_pressure * 100 / air_density)
                            tas = (ias * Math.sqrt(1.225 / air_density))
                        } else {
                            ias = 0
                            tas = 0
                        }
                    }
                }
            }
            catch (e) {
                console.log("Error parsing ROS message: " + e)
            }
        }

        onStatusChanged: {
            if (socket1.status === WebSocket.Error) {
                console.log("Rosbridge Error: " + socket1.errorString)
                isConnected = false
                isAdvertised = false
                subscribedTopics = {}
                reconnectTimer1.start()
            } else if (socket1.status === WebSocket.Open) {
                console.log("Rosbridge Connected")
                isConnected = true
                reconnectAttempts = 0  // Reset reconnect attempts on successful connection
                reconnectTimer1.stop()

                // Advertise publish topic after connection
                advertiseTopic()
                // Subscribe to topics
                subscribeToTopic("/fmu/out/sensor_combined", "px4_msgs/msg/SensorCombined")
                subscribeToTopic("/fmu/out/vehicle_gps_position", "px4_msgs/msg/SensorGps")
                subscribeToTopic("/fmu/out/vehicle_odometry", "px4_msgs/msg/VehicleOdometry")
                subscribeToTopic("/esp32/wing_data", "wing_msgs/msg/WingData")
            } else if (socket1.status === WebSocket.Closed) {
                console.log("Rosbridge Disconnected")
                isConnected = false
                isAdvertised = false
                subscribedTopics = {}
                reconnectTimer1.start()
            } else if (socket1.status === WebSocket.Connecting) {
                console.log("Rosbridge Connecting...")
                isConnected = false
            }
        }

        // Function to advertise the published topic
        function advertiseTopic() {
            if (!isConnected) {
                console.log("Cannot advertise: not connected")
                return
            }

            var advertiseMsg = {
                "op": "advertise",
                "topic": publishTopicName,
                "type": publishMessageType
            }

            var jsonMsg = JSON.stringify(advertiseMsg)
            socket1.sendTextMessage(jsonMsg)
            isAdvertised = true
            console.log("Advertised topic: " + publishTopicName)
        }

        // Function to publish a message
        function publishMessage(messageData) {
            if (!isConnected) {
                console.log("Cannot publish: not connected")
                return false
            }

            if (!isAdvertised) {
                console.log("Cannot publish: topic not advertised")
                return false
            }

            var publishMsg = {
                "op": "publish",
                "topic": publishTopicName,
                "msg": messageData
            }

            var jsonMsg = JSON.stringify(publishMsg)
            socket1.sendTextMessage(jsonMsg)
            console.log("Published to " + publishTopicName + ": " + JSON.stringify(messageData))
            return true
        }

        // Function to subscribe to a topic
        function subscribeToTopic(topicName, messageType) {
            if (!isConnected) {
                console.log("Cannot subscribe: not connected")
                return false
            }

            var subscribeMsg = {
                "op": "subscribe",
                "topic": topicName,
                "type": messageType
            }

            var jsonMsg = JSON.stringify(subscribeMsg)
            socket1.sendTextMessage(jsonMsg)
            subscribedTopics[topicName] = true
            console.log("Subscribed to " + topicName + " with type " + messageType)
            return true
        }

        // Function to unsubscribe from a topic
        function unsubscribeFromTopic(topicName) {
            if (!isConnected) {
                console.log("Cannot unsubscribe: not connected")
                return false
            }

            var unsubscribeMsg = {
                "op": "unsubscribe",
                "topic": topicName
            }

            var jsonMsg = JSON.stringify(unsubscribeMsg)
            socket1.sendTextMessage(jsonMsg)
            delete subscribedTopics[topicName]
            console.log("Unsubscribed from " + topicName)
            return true
        }

        // Function to unadvertise the topic
        function unadvertiseTopic() {
            if (!isConnected || !isAdvertised) {
                return
            }

            var unadvertiseMsg = {
                "op": "unadvertise",
                "topic": publishTopicName
            }

            var jsonMsg = JSON.stringify(unadvertiseMsg)
            socket1.sendTextMessage(jsonMsg)
            isAdvertised = false
            console.log("Unadvertised topic: " + publishTopicName)
        }

        // Clean up on component destruction
        Component.onDestruction: {
            reconnectTimer1.stop()
            unsubscribeFromTopic("/fmu/out/sensor_combined")
            unsubscribeFromTopic("/fmu/out/vehicle_gps_position")
            unsubscribeFromTopic("/fmu/out/vehicle_odometry")
            unsubscribeFromTopic("/esp32/wing_data")
        }
    }

    // Reconnection Timer
    Timer {
        id: reconnectTimer1
        interval: 3000  // Try to reconnect every 3 seconds
        repeat: true
        running: false

        onTriggered: {
            if (socket1.reconnectAttempts >= socket1.maxReconnectAttempts) {
                console.log("Max reconnection attempts reached. Stopping reconnection.")
                reconnectTimer1.stop()
                return
            }

            if (socket1.status !== WebSocket.Open && socket1.status !== WebSocket.Connecting) {
                socket1.reconnectAttempts++
                console.log("Attempting to reconnect... (Attempt " + socket1.reconnectAttempts + "/" + socket1.maxReconnectAttempts + ")")
                socket1.active = false
                reopenTimer.start()
            }
        }
    }

    Timer {
        id: reopenTimer
        interval: 100
        repeat: false
        onTriggered: {
            socket1.active = true
        }
    }

    TabBar {
            id: tabBar
            width: parent.width
            height:50
            anchors.top: parent.top
            currentIndex: selectedIndex

            TabButton {
                text: "Map"
                onClicked: selectedIndex = 0
            }

            TabButton {
                text: "Sensors"
                onClicked: selectedIndex = 1
            }

            TabButton {
                text: "Six Pack"
                onClicked: selectedIndex = 2
            }

            TabButton {
                text: "Primary Flight Display"
                onClicked: selectedIndex = 3
            }

            TabButton {
                text: "Settings"
                onClicked: selectedIndex = 4
            }
        }

    Loader {
        id: pageLoader
        anchors.top: tabBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        sourceComponent: selectedIndex === 0 ? mapPage :
                         selectedIndex === 1 ? sensorPage :
                         selectedIndex === 2 ? packPage :
                         selectedIndex === 3 ? pfdPage :
                         settingsPage
    }


    Component {
        id: mapPage
        Rectangle {
            anchors.fill: parent
            color: "#94a3b8"

            Rectangle {
                id: window
                anchors.fill: parent

                property int mapZoomLevel: 11

                Item {
                    id: mapView
                    anchors.fill: parent
                    clip: true

                    property int zoomLevel: window.mapZoomLevel
                    property double centerLatitude: latitude
                    property double centerLongitude: longitude

                    Rectangle {
                        anchors.fill: parent
                        color: "#e2e8f0"
                    }

                    Repeater {
                        id: tileRepeater
                        model: ListModel {}

                        delegate: Image {
                            required property int tileX
                            required property int tileY
                            required property int tileZ

                            x: (tileX - mapView.centerTileX) * 256 + mapView.width / 2 - mapView.centerPixelX
                            y: (tileY - mapView.centerTileY) * 256 + mapView.height / 2 - mapView.centerPixelY
                            width: 256
                            height: 256

                            source: "file://" + offlineTilesPath + "/" + tileZ + "/" + tileX + "/" + tileY + ".png"

                            fillMode: Image.PreserveAspectFit
                            cache: false
                            asynchronous: true

                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.color: "#cbd5e1"
                                border.width: 1
                            }

                            Text {
                                anchors.centerIn: parent
                                text: tileX + "," + tileY + "\nz" + tileZ
                                font.pixelSize: 10
                                color: "#64748b"
                                visible: parent.status !== Image.Ready
                            }
                        }
                    }

                    property int centerTileX: {
                        var n = Math.pow(2, zoomLevel)
                        return Math.floor((centerLongitude + 180) / 360 * n)
                    }

                    property int centerTileY: {
                        var n = Math.pow(2, zoomLevel)
                        var lat_rad = centerLatitude * Math.PI / 180
                        return Math.floor((1 - Math.log(Math.tan(lat_rad) + 1 / Math.cos(lat_rad)) / Math.PI) / 2 * n)
                    }

                    // Calculate pixel offset within the center tile
                    property real centerPixelX: {
                        var n = Math.pow(2, zoomLevel)
                        var tileX = (centerLongitude + 180) / 360 * n
                        return (tileX - Math.floor(tileX)) * 256
                    }

                    property real centerPixelY: {
                        var n = Math.pow(2, zoomLevel)
                        var lat_rad = centerLatitude * Math.PI / 180
                        var tileY = (1 - Math.log(Math.tan(lat_rad) + 1 / Math.cos(lat_rad)) / Math.PI) / 2 * n
                        return (tileY - Math.floor(tileY)) * 256
                    }

                    function updateTiles() {
                        var zoom = zoomLevel
                        var n = Math.pow(2, zoom)

                        var tileBounds = {
                            11: { minX: 1062, maxX: 1102, minY: 655, maxY: 715 }
                        }

                        var bounds = tileBounds[zoom]
                        if (!bounds) {
                            console.log("No tile bounds defined for zoom level", zoom)
                            tileRepeater.model.clear()
                            return
                        }

                        var tilesX = Math.ceil(width / 256) + 2
                        var tilesY = Math.ceil(height / 256) + 2

                        var startX = centerTileX - Math.floor(tilesX / 2)
                        var startY = centerTileY - Math.floor(tilesY / 2)

                        tileRepeater.model.clear()

                        for (var x = 0; x < tilesX; x++) {
                            for (var y = 0; y < tilesY; y++) {
                                var currentX = startX + x
                                var currentY = startY + y

                                if (currentX >= bounds.minX && currentX <= bounds.maxX &&
                                    currentY >= bounds.minY && currentY <= bounds.maxY) {
                                    tileRepeater.model.append({
                                        tileX: currentX,
                                        tileY: currentY,
                                        tileZ: zoom
                                    })
                                }
                            }
                        }
                    }

                    Component.onCompleted: {
                        console.log("Map view loaded. Zoom:", zoomLevel, "Center:", centerLatitude, centerLongitude)
                        console.log("Center tile:", centerTileX, centerTileY)
                        console.log("Pixel offset:", centerPixelX, centerPixelY)
                        updateTiles()
                    }
                    onZoomLevelChanged: updateTiles()
                    onCenterLatitudeChanged: updateTiles()
                    onCenterLongitudeChanged: updateTiles()
                    onWidthChanged: updateTiles()
                    onHeightChanged: updateTiles()
                }

                Rectangle {
                    x: parent.width / 2 - width / 2
                    y: parent.height / 2 - height / 2
                    width: 20
                    height: 20
                    radius: 10
                    color: "red"
                    border.color: "white"
                    border.width: 3
                    z: 100
                }
            }
        }
    }

    Component {
        id: sensorPage
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#b8c6db" }
                GradientStop { position: 1.0; color: "#f5f7fa" }
            }

            property int baseFontSize: 18

            // Main grid layout
            Grid {
                anchors.fill: parent
                anchors.margins: 20
                anchors.topMargin: 40
                rows: 2
                columns: 2
                rowSpacing: 20
                columnSpacing: 20

                // Airspeed Data GroupBox
                GroupBox {
                    id: speed_groupBox
                    width: (parent.width - parent.columnSpacing) / 2
                    height: (parent.height - parent.rowSpacing) / 2
                    font.pointSize: 14
                    title: qsTr("Airspeed Data")
                    background: Rectangle {
                                color: "transparent"
                                border.width: 0
                            }

                    Grid {
                        anchors.fill: parent
                        anchors.margins: 10
                        columns: 2
                        rowSpacing: 15
                        columnSpacing: 40

                        // Labels column
                        Column {
                            spacing: 15
                            Text { text: qsTr("IAS"); font.pointSize: 18 }
                            Text { text: qsTr("TAS"); font.pointSize: 18 }
                            Text { text: qsTr("GPS Speed"); font.pointSize: 18 }
                            Text { text: "V<sub>n</sub>"; textFormat: Text.RichText; font.pointSize: 18 }
                            Text { text: "V<sub>e</sub>"; textFormat: Text.RichText; font.pointSize: 18 }
                            Text { text: "V<sub>d</sub>"; textFormat: Text.RichText; font.pointSize: 18 }
                        }

                        // Values column
                        Column {
                            spacing: 15
                            Text {
                                text: ias.toFixed(2) + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: tas.toFixed(2) + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: gpsSpeed.toFixed(2) + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: vn.toFixed(2) + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: ve.toFixed(2) + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: vd.toFixed(2) + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                        }
                    }
                }

                // Attitude GroupBox
                GroupBox {
                    id: attitude_groupBox
                    width: (parent.width - parent.columnSpacing) / 2
                    height: (parent.height - parent.rowSpacing) / 2
                    font.pointSize: 14
                    title: qsTr("Attitude")
                    background: Rectangle {
                                color: "transparent"
                                border.width: 0
                            }

                    Grid {
                        anchors.fill: parent
                        anchors.margins: 10
                        columns: 2
                        rowSpacing: 15
                        columnSpacing: 40

                        // Labels column
                        Column {
                            spacing: 15
                            Text { text: qsTr("Roll"); font.pointSize: 18 }
                            Text { text: qsTr("Pitch"); font.pointSize: 18 }
                            Text { text: qsTr("Yaw"); font.pointSize: 18 }
                            Text { text: "Roll Rate"; font.pointSize: 18 }
                            Text { text: "Pitch Rate"; font.pointSize: 18 }
                            Text { text: "Yaw Rate"; font.pointSize: 18 }
                        }

                        // Values column
                        Column {
                            spacing: 15
                            Text {
                                text: roll.toFixed(1) + "°"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: pitch.toFixed(1) + "°"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: yaw.toFixed(1) + "°"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: rollRate.toFixed(2) + " rad/s"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: pitchRate.toFixed(2) + " rad/s"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: yawRate.toFixed(2) + " rad/s"
                                font.pointSize: 18
                                font.bold: true
                            }
                        }
                    }
                }

                // Environment Data GroupBox
                GroupBox {
                    id: env_groupBox
                    width: (parent.width - parent.columnSpacing) / 2
                    height: (parent.height - parent.rowSpacing) / 2
                    font.pointSize: 14
                    title: qsTr("Environment Data")

                    background: Rectangle {
                                color: "transparent"
                                border.width: 0
                            }
                    Grid {
                        anchors.fill: parent
                        anchors.margins: 10
                        columns: 2
                        rowSpacing: 15
                        columnSpacing: 40

                        // Labels column
                        Column {
                            spacing: 15
                            Text { text: "Temperature"; font.pointSize: 18 }
                            Text { text: "Humidity"; font.pointSize: 18 }
                            Text { text: "Static Pressure"; font.pointSize: 18 }
                            Text { text: "Dynamic Pressure"; font.pointSize: 18 }
                            Text { text: "Altitude"; font.pointSize: 18 }
                            Text { text: "Air Density"; font.pointSize: 18 }
                        }

                        // Values column
                        Column {
                            spacing: 15
                            Text {
                                text: temperature.toFixed(1) + " °C"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: humidity.toFixed(1) + " %"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: baro_pressure.toFixed(2) + " hPa"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: diff_pressure.toFixed(2) + " Pa"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: altitude.toFixed(1) + " m"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: air_density.toFixed(3) + " kg/m³"
                                font.pointSize: 18
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: packPage
        Rectangle {
            anchors.fill: parent
            color: "#1a1a1a"

            Grid {
                anchors.centerIn: parent
                columns: 3
                rows: 2
                spacing: 20

                // Top Row - Airspeed Indicator
                Item {
                    width: 280
                    height: 280

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        radius: width / 2
                        border.color: "#4a4a4a"
                        border.width: 3

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.95
                            height: parent.height * 0.95
                            radius: width / 2
                            color: "#0a0a0a"

                            Canvas {
                                id: airspeedCanvas
                                anchors.fill: parent
                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    var cx = width / 2
                                    var cy = height / 2
                                    var radius = Math.min(width, height) / 2 - 30

                                    ctx.strokeStyle = "white"
                                    ctx.fillStyle = "white"
                                    ctx.font = "bold 12px Arial"
                                    ctx.textAlign = "center"
                                    ctx.textBaseline = "middle"

                                    for (var speed = 0; speed <= 200; speed += 10) {
                                        var angle = (speed / 200) * 270 - 45
                                        var rad = angle * Math.PI / 180

                                        var isMajor = speed % 20 === 0
                                        var tickLength = isMajor ? 12 : 6
                                        ctx.lineWidth = isMajor ? 2 : 1

                                        var x1 = cx + radius * Math.cos(rad)
                                        var y1 = cy + radius * Math.sin(rad)
                                        var x2 = cx + (radius - tickLength) * Math.cos(rad)
                                        var y2 = cy + (radius - tickLength) * Math.sin(rad)

                                        ctx.beginPath()
                                        ctx.moveTo(x1, y1)
                                        ctx.lineTo(x2, y2)
                                        ctx.stroke()

                                        if (isMajor) {
                                            var labelRadius = radius - 25
                                            var labelX = cx + labelRadius * Math.cos(rad)
                                            var labelY = cy + labelRadius * Math.sin(rad)
                                            ctx.fillText(speed.toString(), labelX, labelY)
                                        }
                                    }
                                }
                            }

                            Item {
                                anchors.centerIn: parent
                                rotation: ((tas  * 1.94384)/ 200) * 270 + 45

                                Rectangle {
                                    width: 3
                                    height: parent.parent.height * 0.35
                                    color: "white"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.verticalCenter
                                }

                                Rectangle {
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: "white"
                                    anchors.centerIn: parent
                                }
                            }

                            Text {
                                text: "AIRSPEED"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 15
                            }
                            Text {
                                text: "Knots"
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 65
                            }
                        }
                    }
                }

                // Attitude Indicator
                Item {
                    id: root
                    width: 280
                    height: 280

                    Item {
                        id: circularMask
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: circularMask.width
                                height: circularMask.height
                                radius: width / 2
                            }
                        }

                        Rectangle {
                            id: background
                            anchors.fill: parent
                            color: "#2a2a2a"
                            clip: true

                            Item{
                                id: horizon
                                anchors.centerIn: parent
                                width: parent.width * 2
                                height: parent.height * 2
                                rotation: -roll

                                Item {
                                    x: horizon.width / 2
                                    y: horizon.height / 2 + pitch

                                    Rectangle {
                                        id: sky
                                        width: horizon.width
                                        height: horizon.height / 2
                                        anchors.bottom: ground.top
                                        gradient: Gradient{
                                            GradientStop { position: 0.0; color: "#4a9eff"}
                                            GradientStop { position: 1.0; color: "#87ceeb"}
                                        }
                                    }

                                    Rectangle {
                                        id: ground
                                        width: horizon.width
                                        height: horizon.height / 2
                                        color: "#8b4513"

                                        Rectangle {
                                            width: parent.width
                                            height: 2
                                            color: "white"
                                            anchors.top: parent.top
                                        }
                                    }

                                    Repeater {
                                        model: [-60, -45, -30, -20, -10, 10, 20, 30, 45, 60]

                                        Item {
                                            y: -modelData * 2
                                            x: -50

                                            Rectangle {
                                                width: modelData % 30 === 0 ? 100 : 60
                                                height: 2
                                                color: "white"
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }

                                            Text {
                                                text: Math.abs(modelData)
                                                color: "white"
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: -20
                                                font.pixelSize: 12
                                                font.bold: true
                                            }

                                            Text {
                                                text: Math.abs(modelData)
                                                color: "white"
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.rightMargin: -20
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                anchors.centerIn: parent
                                width: 120
                                height: 60

                                Rectangle {
                                    width: 50
                                    height: 4
                                    color: "#ffaa00"
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    width: 50
                                    height: 4
                                    color: "#ffaa00"
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    width: 4
                                    height: 20
                                    color: "#ffaa00"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.verticalCenter
                                }
                            }

                            Item {
                                anchors.fill: parent
                                rotation: -roll

                                Canvas {
                                    anchors.fill: parent

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)

                                        var cx = width / 2
                                        var cy = height / 2
                                        var r = Math.min(width, height) / 2 - 20

                                        ctx.strokeStyle = "white"
                                        ctx.lineWidth = 2
                                        ctx.fillStyle = "white"

                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, -Math.PI * 0.7, -Math.PI * 0.3, false)
                                        ctx.stroke()

                                        var angles = [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]
                                        for (var i = 0; i < angles.length; i++) {
                                            var angle = angles[i] * Math.PI / 180 - Math.PI / 2
                                            var len = (angles[i] % 30 === 0) ? 15 : 10

                                            ctx.beginPath()
                                            ctx.moveTo(cx + r * Math.cos(angle), cy + r * Math.sin(angle))
                                            ctx.lineTo(cx + (r - len) * Math.cos(angle), cy + (r - len) * Math.sin(angle))
                                            ctx.stroke()
                                        }

                                        ctx.fillStyle = "#ffaa00"
                                        ctx.beginPath()
                                        ctx.moveTo(cx, cy - r + 5)
                                        ctx.lineTo(cx - 8, cy - r + 18)
                                        ctx.lineTo(cx + 8, cy - r + 18)
                                        ctx.closePath()
                                        ctx.fill()
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width
                        color: "transparent"
                        border.color: "#2a2a2a"
                        border.width: 3
                        radius: width / 2
                    }
                }


                // Altimeter
                Item {
                    width: 280
                    height: 280

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        radius: width / 2
                        border.color: "#4a4a4a"
                        border.width: 3

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.95
                            height: parent.height * 0.95
                            radius: width / 2
                            color: "#0a0a0a"

                            Canvas {
                                anchors.fill: parent
                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    var cx = width / 2
                                    var cy = height / 2
                                    var radius = Math.min(width, height) / 2 - 25

                                    ctx.strokeStyle = "white"
                                    ctx.fillStyle = "white"
                                    ctx.font = "bold 11px Arial"
                                    ctx.textAlign = "center"
                                    ctx.textBaseline = "middle"

                                    for (var i = 0; i <= 15; i++) {
                                        var angle = (i / 16) * 360 - 90
                                        var rad = angle * Math.PI / 180

                                        ctx.lineWidth = 2
                                        var x1 = cx + radius * Math.cos(rad)
                                        var y1 = cy + radius * Math.sin(rad)
                                        var x2 = cx + (radius - 12) * Math.cos(rad)
                                        var y2 = cy + (radius - 12) * Math.sin(rad)

                                        ctx.beginPath()
                                        ctx.moveTo(x1, y1)
                                        ctx.lineTo(x2, y2)
                                        ctx.stroke()

                                        var labelRadius = radius - 25
                                        var labelX = cx + labelRadius * Math.cos(rad)
                                        var labelY = cy + labelRadius * Math.sin(rad)
                                        ctx.fillText(i.toString(), labelX, labelY)
                                    }
                                }
                            }

                            Item {
                                anchors.centerIn: parent
                                rotation: ((altitude * 3.28084) / 15000) * 360
                                Rectangle {
                                    width: 3
                                    height: parent.parent.height * 0.3
                                    color: "white"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.verticalCenter
                                }
                            }

                            Rectangle {
                                width: 15
                                height: 15
                                radius: 7.5
                                color: "#333"
                                anchors.centerIn: parent
                                border.color: "white"
                                border.width: 2
                            }

                            Text {
                                text: "x1000 ft"
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 75
                            }
                            Text {
                                text: "ALT"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 55
                            }
                        }
                    }
                }

                // Turn Coordinator
                Item {
                    width: 280
                    height: 280

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        radius: width / 2
                        border.color: "#4a4a4a"
                        border.width: 3

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.95
                            height: parent.height * 0.95
                            radius: width / 2
                            color: "#0a0a0a"

                            Canvas {
                                anchors.fill: parent
                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    var cx = width / 2
                                    var cy = height / 2 - 20

                                    ctx.strokeStyle = "white"
                                    ctx.lineWidth = 2

                                    ctx.beginPath()
                                    ctx.moveTo(cx - 60, cy)
                                    ctx.lineTo(cx - 60, cy + 12)
                                    ctx.stroke()

                                    ctx.beginPath()
                                    ctx.moveTo(cx + 60, cy)
                                    ctx.lineTo(cx + 60, cy + 12)
                                    ctx.stroke()

                                    ctx.fillStyle = "white"
                                    ctx.font = "bold 12px Arial"
                                    ctx.textAlign = "center"
                                    ctx.fillText("L", cx - 60, cy + 25)
                                    ctx.fillText("R", cx + 60, cy + 25)
                                }
                            }

                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height / 2 - 70
                                rotation: Math.max(-30, Math.min(30, yawRate * 3))

                                Canvas {
                                    width: 120
                                    height: 60
                                    anchors.centerIn: parent
                                    Component.onCompleted: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)

                                        var cx = width / 2
                                        var cy = height / 2

                                        ctx.strokeStyle = "white"
                                        ctx.fillStyle = "white"
                                        ctx.lineWidth = 2

                                        ctx.beginPath()
                                        ctx.moveTo(cx - 50, cy)
                                        ctx.lineTo(cx - 8, cy)
                                        ctx.stroke()

                                        ctx.beginPath()
                                        ctx.moveTo(cx + 8, cy)
                                        ctx.lineTo(cx + 50, cy)
                                        ctx.stroke()

                                        ctx.beginPath()
                                        ctx.moveTo(cx, cy - 6)
                                        ctx.lineTo(cx, cy + 20)
                                        ctx.stroke()
                                    }
                                }
                            }

                            Text {
                                text: "TURN COORD"
                                color: "white"
                                font.pixelSize: 9
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 15
                            }
                        }
                    }
                }

                // Compass heading Indicator
                Item {
                    width: 280
                    height: 280

                    property real heading: yaw

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        radius: width / 2
                        border.color: "#4a4a4a"
                        border.width: 3

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.95
                            height: parent.height * 0.95
                            radius: width / 2
                            color: "#0a0a0a"
                            clip: true

                            Item {
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.height
                                rotation: -parent.parent.parent.heading

                                Canvas {
                                    anchors.fill: parent

                                    Component.onCompleted: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)

                                        var cx = width / 2
                                        var cy = height / 2
                                        var radius = Math.min(width, height) / 2 - 30

                                        ctx.strokeStyle = "white"
                                        ctx.fillStyle = "white"
                                        ctx.textAlign = "center"
                                        ctx.textBaseline = "middle"

                                        var directions = [
                                            {deg: 0, label: "N", major: true},
                                            {deg: 30, label: "3", major: false},
                                            {deg: 60, label: "6", major: false},
                                            {deg: 90, label: "E", major: true},
                                            {deg: 120, label: "12", major: false},
                                            {deg: 150, label: "15", major: false},
                                            {deg: 180, label: "S", major: true},
                                            {deg: 210, label: "21", major: false},
                                            {deg: 240, label: "24", major: false},
                                            {deg: 270, label: "W", major: true},
                                            {deg: 300, label: "30", major: false},
                                            {deg: 330, label: "33", major: false}
                                        ]

                                        for (var i = 0; i < directions.length; i++) {
                                            var dir = directions[i]
                                            var angle = (dir.deg - 90) * Math.PI / 180

                                            var tickLength = dir.major ? 15 : 10
                                            ctx.lineWidth = dir.major ? 2 : 1

                                            var x1 = cx + radius * Math.cos(angle)
                                            var y1 = cy + radius * Math.sin(angle)
                                            var x2 = cx + (radius - tickLength) * Math.cos(angle)
                                            var y2 = cy + (radius - tickLength) * Math.sin(angle)

                                            ctx.beginPath()
                                            ctx.moveTo(x1, y1)
                                            ctx.lineTo(x2, y2)
                                            ctx.stroke()

                                            ctx.font = dir.major ? "bold 14px Arial" : "bold 11px Arial"
                                            var labelRadius = radius - 28
                                            var labelX = cx + labelRadius * Math.cos(angle)
                                            var labelY = cy + labelRadius * Math.sin(angle)

                                            ctx.save()
                                            ctx.translate(labelX, labelY)
                                            ctx.rotate(angle + Math.PI/2)
                                            ctx.fillText(dir.label, 0, 0)
                                            ctx.restore()
                                        }
                                    }
                                }
                            }

                            Canvas {
                                anchors.fill: parent

                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    var cx = width / 2
                                    var cy = height / 2
                                    var radius = Math.min(width, height) / 2 - 15

                                    ctx.fillStyle = "#ffaa00"
                                    ctx.beginPath()
                                    ctx.moveTo(cx, cy - radius + 5)
                                    ctx.lineTo(cx - 8, cy - radius + 20)
                                    ctx.lineTo(cx + 8, cy - radius + 20)
                                    ctx.closePath()
                                    ctx.fill()
                                }
                            }

                            Text {
                                text: "HDG"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                // Vertical Speed Indicator
                Item {
                    width: 280
                    height: 280

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        radius: width / 2
                        border.color: "#4a4a4a"
                        border.width: 3

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.95
                            height: parent.height * 0.95
                            radius: width / 2
                            color: "#0a0a0a"

                            Canvas {
                                anchors.fill: parent
                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    var cx = width / 2
                                    var cy = height / 2
                                    var radius = Math.min(width, height) / 2 - 30

                                    ctx.strokeStyle = "white"
                                    ctx.fillStyle = "white"

                                    var arcSpan = 162

                                    // Top arc (UP)
                                    for (var i = 0; i <= 20; i++) {
                                        var angle = 180 - (i / 20) * arcSpan
                                        var rad = (angle) * Math.PI / 180

                                        var isMajor = (i % 5 === 0)
                                        var tickLength = isMajor ? 15 : 8
                                        ctx.lineWidth = isMajor ? 2 : 1

                                        var x1 = cx + radius * Math.cos(rad)
                                        var y1 = cy + radius * Math.sin(rad)
                                        var x2 = cx + (radius - tickLength) * Math.cos(rad)
                                        var y2 = cy + (radius - tickLength) * Math.sin(rad)

                                        ctx.beginPath()
                                        ctx.moveTo(x1, y1)
                                        ctx.lineTo(x2, y2)
                                        ctx.stroke()

                                        if (isMajor) {
                                            ctx.font = "bold 13px Arial"
                                            ctx.textAlign = "center"
                                            ctx.textBaseline = "middle"
                                            var labelRadius = radius - 28
                                            var labelX = cx + labelRadius * Math.cos(rad)
                                            var labelY = cy + labelRadius * Math.sin(rad)
                                            ctx.fillText(i.toString(), labelX, labelY)
                                        }
                                    }

                                    // Bottom arc (DOWN)
                                    for (var j = 0; j <= 20; j++) {
                                        if (j === 0) continue

                                        var angleDown = 180 + (j / 20) * arcSpan
                                        var radDown = (angleDown) * Math.PI / 180

                                        var isMajorDown = (j % 5 === 0)
                                        var tickLengthDown = isMajorDown ? 15 : 8
                                        ctx.lineWidth = isMajorDown ? 2 : 1

                                        var x1Down = cx + radius * Math.cos(radDown)
                                        var y1Down = cy + radius * Math.sin(radDown)
                                        var x2Down = cx + (radius - tickLengthDown) * Math.cos(radDown)
                                        var y2Down = cy + (radius - tickLengthDown) * Math.sin(radDown)

                                        ctx.beginPath()
                                        ctx.moveTo(x1Down, y1Down)
                                        ctx.lineTo(x2Down, y2Down)
                                        ctx.stroke()

                                        if (isMajorDown) {
                                            ctx.font = "bold 13px Arial"
                                            ctx.textAlign = "center"
                                            ctx.textBaseline = "middle"
                                            var labelRadiusDown = radius - 28
                                            var labelXDown = cx + labelRadiusDown * Math.cos(radDown)
                                            var labelYDown = cy + labelRadiusDown * Math.sin(radDown)
                                            ctx.fillText(j.toString(), labelXDown, labelYDown)
                                        }
                                    }

                                    ctx.font = "bold 10px Arial"
                                    ctx.textAlign = "center"
                                    ctx.fillText("VERTICAL", cx + 20, cy - 15)
                                    ctx.fillText("SPEED", cx + 20, cy - 3)
                                    ctx.font = "8px Arial"
                                    ctx.fillText("x100 ft", cx + 20, cy + 10)
                                    ctx.fillText("PER MINUTE", cx + 20, cy + 20)
                                    ctx.font = "bold 9px Arial"
                                    ctx.fillText("UP", cx - 35, cy - 45)
                                    ctx.fillText("DN", cx - 35, cy + 45)
                                }
                            }

                            Item {
                                anchors.centerIn: parent

                                property real vdFpm: vd * 196.85  // Convert m/s to feet per minute
                                property real clampedSpeed: Math.max(-2000, Math.min(2000, vdFpm))
                                property real scaledValue: clampedSpeed / 100

                                rotation: {
                                    var arcSpan = 162
                                    var needleRotation = 0

                                    if (scaledValue >= 0) {
                                        needleRotation = 180 - (scaledValue / 20) * arcSpan
                                    } else {
                                        needleRotation = 180 + (Math.abs(scaledValue) / 20) * arcSpan
                                    }

                                    return needleRotation + 90
                                }

                                Rectangle {
                                    width: 3
                                    height: parent.parent.height * 0.38
                                    color: "white"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.verticalCenter
                                    antialiasing: true
                                }

                                Rectangle {
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: "white"
                                    anchors.centerIn: parent
                                }
                            }

                            Rectangle {
                                width: 15
                                height: 15
                                radius: 7.5
                                color: "#0a0a0a"
                                anchors.centerIn: parent
                                border.color: "white"
                                border.width: 2
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: pfdPage
        Rectangle {
            anchors.fill: parent
            color: "#0a0a0a"

            // Main PFD Container
            Rectangle {
                anchors.fill: parent
                anchors.margins: 20
                color: "#1a1a1a"
                border.color: "#333"
                border.width: 2

                // Attitude Indicator (Center)
                Item {
                    id: pfdAttitude
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.5, parent.height * 0.7)
                    height: width

                    Item {
                        id: circularMask
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: circularMask.width
                                height: circularMask.height
                                radius: width / 2
                            }
                        }

                        Rectangle {
                            id: background
                            anchors.fill: parent
                            color: "#2a2a2a"
                            clip: true

                            Item {
                                id: horizon
                                anchors.centerIn: parent
                                width: parent.width * 2
                                height: parent.height * 2
                                rotation: -roll

                                Item {
                                    x: horizon.width / 2
                                    y: horizon.height / 2 + pitch * 3

                                    Rectangle {
                                        id: sky
                                        width: horizon.width
                                        height: horizon.height / 2
                                        anchors.bottom: ground.top
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "#1e3a8a" }
                                            GradientStop { position: 1.0; color: "#3b82f6" }
                                        }
                                    }

                                    Rectangle {
                                        id: ground
                                        width: horizon.width
                                        height: horizon.height / 2
                                        color: "#92400e"

                                        Rectangle {
                                            width: parent.width
                                            height: 3
                                            color: "#fbbf24"
                                            anchors.top: parent.top
                                        }
                                    }

                                    Repeater {
                                        model: [-60, -50, -40, -30, -20, -10, 10, 20, 30, 40, 50, 60]

                                        Item {
                                            y: -modelData * 3
                                            x: -80

                                            Rectangle {
                                                width: modelData % 30 === 0 ? 160 : 100
                                                height: 3
                                                color: "white"
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }

                                            Text {
                                                text: Math.abs(modelData)
                                                color: "white"
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: -25
                                                font.pixelSize: 16
                                                font.bold: true
                                            }

                                            Text {
                                                text: Math.abs(modelData)
                                                color: "white"
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.rightMargin: -25
                                                font.pixelSize: 16
                                                font.bold: true
                                            }
                                        }
                                    }
                                }
                            }

                            // Aircraft symbol (fixed)
                            Item {
                                anchors.centerIn: parent
                                width: 160
                                height: 80

                                Rectangle {
                                    width: 80
                                    height: 6
                                    color: "#fbbf24"
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    width: 80
                                    height: 6
                                    color: "#fbbf24"
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    width: 6
                                    height: 30
                                    color: "#fbbf24"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.verticalCenter
                                }

                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: "transparent"
                                    border.color: "#fbbf24"
                                    border.width: 3
                                    anchors.centerIn: parent
                                }
                            }

                            // Roll indicator arc
                            Item {
                                anchors.fill: parent
                                rotation: -roll

                                Canvas {
                                    anchors.fill: parent

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)

                                        var cx = width / 2
                                        var cy = height / 2
                                        var r = Math.min(width, height) / 2 - 30

                                        ctx.strokeStyle = "white"
                                        ctx.lineWidth = 3
                                        ctx.fillStyle = "white"

                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, -Math.PI * 0.75, -Math.PI * 0.25, false)
                                        ctx.stroke()

                                        var angles = [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]
                                        for (var i = 0; i < angles.length; i++) {
                                            var angle = angles[i] * Math.PI / 180 - Math.PI / 2
                                            var len = (angles[i] % 30 === 0) ? 20 : 12

                                            ctx.lineWidth = (angles[i] % 30 === 0) ? 3 : 2
                                            ctx.beginPath()
                                            ctx.moveTo(cx + r * Math.cos(angle), cy + r * Math.sin(angle))
                                            ctx.lineTo(cx + (r - len) * Math.cos(angle), cy + (r - len) * Math.sin(angle))
                                            ctx.stroke()
                                        }

                                        // Roll pointer
                                        ctx.fillStyle = "#fbbf24"
                                        ctx.beginPath()
                                        ctx.moveTo(cx, cy - r + 8)
                                        ctx.lineTo(cx - 12, cy - r + 28)
                                        ctx.lineTo(cx + 12, cy - r + 28)
                                        ctx.closePath()
                                        ctx.fill()
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        color: "transparent"
                        border.color: "#4a4a4a"
                        border.width: 4
                        radius: width / 2
                    }
                }

                // Airspeed Tape (Left)
                Item {
                    id: airspeedTape
                    anchors.left: parent.left
                    anchors.leftMargin: 40
                    anchors.verticalCenter: parent.verticalCenter
                    width: 120
                    height: parent.height * 0.6

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        border.color: "#4a4a4a"
                        border.width: 2
                        clip: true

                        Column {
                            id: speedColumn
                            anchors.centerIn: parent
                            y: parent.height / 2 - (tas * 1.94384 * 5)
                            spacing: 0

                            Repeater {
                                model: 60

                                Item {
                                    width: airspeedTape.width - 4
                                    height: 50

                                    property int speed: index * 10

                                    Rectangle {
                                        width: speed % 20 === 0 ? 30 : 15
                                        height: 2
                                        color: "white"
                                        anchors.right: parent.right
                                        anchors.rightMargin: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: speed
                                        color: "white"
                                        font.pixelSize: 18
                                        font.bold: true
                                        anchors.right: parent.right
                                        anchors.rightMargin: 35
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: speed % 20 === 0
                                    }
                                }
                            }
                        }
                    }

                    // Current speed indicator
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 90
                        height: 40
                        color: "#000"
                        border.color: "#fbbf24"
                        border.width: 3

                        Text {
                            text: (tas * 1.94384).toFixed(0)
                            color: "#fbbf24"
                            font.pixelSize: 24
                            font.bold: true
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        text: "KIAS"
                        color: "white"
                        font.pixelSize: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 5
                    }
                }

                // Altitude Tape (Right)
                Item {
                    id: altitudeTape
                    anchors.right: parent.right
                    anchors.rightMargin: 40
                    anchors.verticalCenter: parent.verticalCenter
                    width: 120
                    height: parent.height * 0.6

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        border.color: "#4a4a4a"
                        border.width: 2
                        clip: true

                        Column {
                            anchors.centerIn: parent
                            y: parent.height / 2 - ((altitude * 3.28084) / 100 * 50)
                            spacing: 0

                            Repeater {
                                model: 200

                                Item {
                                    width: altitudeTape.width - 4
                                    height: 50

                                    property int alt: index * 100

                                    Rectangle {
                                        width: alt % 500 === 0 ? 30 : 15
                                        height: 2
                                        color: "white"
                                        anchors.left: parent.left
                                        anchors.leftMargin: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: (alt / 100).toFixed(0)
                                        color: "white"
                                        font.pixelSize: 18
                                        font.bold: true
                                        anchors.left: parent.left
                                        anchors.leftMargin: 35
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: alt % 500 === 0
                                    }
                                }
                            }
                        }
                    }

                    // Current altitude indicator
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 90
                        height: 40
                        color: "#000"
                        border.color: "#fbbf24"
                        border.width: 3

                        Text {
                            text: (altitude * 3.28084).toFixed(0)
                            color: "#fbbf24"
                            font.pixelSize: 24
                            font.bold: true
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        text: "ALT FT"
                        color: "white"
                        font.pixelSize: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 5
                    }
                }

                // Heading Strip (Bottom)
                Item {
                    id: headingStrip
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.5
                    height: 80

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        border.color: "#4a4a4a"
                        border.width: 2
                        clip: true

                        Row {
                            anchors.centerIn: parent
                            x: parent.width / 2 - ((yaw + 360) % 360 * 5)
                            spacing: 0

                            Repeater {
                                model: 72

                                Item {
                                    width: 50
                                    height: headingStrip.height - 4

                                    property int hdg: (index * 5) % 360

                                    Rectangle {
                                        width: 2
                                        height: hdg % 30 === 0 ? 25 : 15
                                        color: "white"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: 2
                                    }

                                    Text {
                                        text: {
                                            if (hdg === 0) return "N"
                                            if (hdg === 90) return "E"
                                            if (hdg === 180) return "S"
                                            if (hdg === 270) return "W"
                                            return hdg % 30 === 0 ? (hdg / 10).toFixed(0) : ""
                                        }
                                        color: "white"
                                        font.pixelSize: 16
                                        font.bold: true
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: 30
                                        visible: hdg % 30 === 0
                                    }
                                }
                            }
                        }
                    }

                    // Current heading indicator
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: 70
                        height: 35
                        color: "#000"
                        border.color: "#fbbf24"
                        border.width: 3

                        Text {
                            text: ((yaw + 360) % 360).toFixed(0).padStart(3, '0')
                            color: "#fbbf24"
                            font.pixelSize: 22
                            font.bold: true
                            anchors.centerIn: parent
                        }
                    }

                    Canvas {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        width: 30
                        height: 20

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = "#fbbf24"
                            ctx.beginPath()
                            ctx.moveTo(width / 2, 0)
                            ctx.lineTo(0, height)
                            ctx.lineTo(width, height)
                            ctx.closePath()
                            ctx.fill()
                        }
                    }
                }

                // Vertical Speed Indicator (Far Right)
                Item {
                    id: vsiIndicator
                    anchors.right: altitudeTape.left
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    width: 60
                    height: parent.height * 0.5

                    Rectangle {
                        anchors.fill: parent
                        color: "#1a1a1a"
                        border.color: "#4a4a4a"
                        border.width: 2

                        Column {
                            anchors.fill: parent
                            anchors.margins: 5

                            Repeater {
                                model: [2000, 1000, 500, 0, -500, -1000, -2000]

                                Item {
                                    width: parent.width
                                    height: vsiIndicator.height / 7

                                    property int vsiValue: modelData

                                    Rectangle {
                                        width: 20
                                        height: 2
                                        color: "white"
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: Math.abs(vsiValue / 100)
                                        color: "white"
                                        font.pixelSize: 12
                                        anchors.left: parent.left
                                        anchors.leftMargin: 25
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: vsiValue !== 0
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width - 4
                            height: 3
                            color: "#fbbf24"
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: {
                                var vdFpm = vd * 196.85
                                var clampedVd = Math.max(-2000, Math.min(2000, vdFpm))
                                var normalized = clampedVd / 2000
                                return parent.height / 2 - (normalized * parent.height / 2.3)
                            }
                        }
                    }

                    Text {
                        text: "VSI"
                        color: "white"
                        font.pixelSize: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 5
                    }
                }

                // Flight data info (Top)
                Row {
                    anchors.top: parent.top
                    anchors.topMargin: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 40

                    Column {
                        spacing: 5
                        Text {
                            text: "GS"
                            color: "#9ca3af"
                            font.pixelSize: 14
                        }
                        Text {
                            text: gpsSpeed.toFixed(1) + " m/s"
                            color: "white"
                            font.pixelSize: 18
                            font.bold: true
                        }
                    }

                    Column {
                        spacing: 5
                        Text {
                            text: "TAS"
                            color: "#9ca3af"
                            font.pixelSize: 14
                        }
                        Text {
                            text: (tas * 1.94384).toFixed(0) + " kt"
                            color: "white"
                            font.pixelSize: 18
                            font.bold: true
                        }
                    }

                    Column {
                        spacing: 5
                        Text {
                            text: "BARO"
                            color: "#9ca3af"
                            font.pixelSize: 14
                        }
                        Text {
                            text: qnhSetting.toFixed(2)
                            color: "#22c55e"
                            font.pixelSize: 18
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    Component {
        id: settingsPage
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#b8c6db" }
                GradientStop { position: 1.0; color: "#f5f7fa" }
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: 40
                contentHeight: settingsColumn.height
                clip: true

                Column {
                    id: settingsColumn
                    width: parent.width
                    spacing: 30

                    GroupBox {
                        width: parent.width
                        title: "Altimeter Setting (QNH)"
                        font.pointSize: 14

                        background: Rectangle {
                            color: "white"
                            border.color: "#cbd5e1"
                            border.width: 2
                            radius: 8
                        }

                        Column {
                            width: parent.width
                            spacing: 20

                            Text {
                                text: "Set the current atmospheric pressure at sea level for accurate altitude readings."
                                wrapMode: Text.WordWrap
                                width: parent.width
                                color: "#64748b"
                                font.pixelSize: 14
                            }

                            Row {
                                spacing: 20
                                anchors.horizontalCenter: parent.horizontalCenter

                                Column {
                                    spacing: 10

                                    Text {
                                        text: "Hectopascals (hPa/mb)"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Row {
                                        spacing: 10

                                        Button {
                                            text: "-"
                                            width: 50
                                            height: 50
                                            font.pixelSize: 24
                                            onClicked: {
                                                qnhSetting = Math.max(950, qnhSetting - 1)
                                            }
                                        }

                                        Rectangle {
                                            width: 150
                                            height: 50
                                            border.color: "#3b82f6"
                                            border.width: 2
                                            radius: 4

                                            TextInput {
                                                id: qnhInput
                                                anchors.centerIn: parent
                                                text: qnhSetting.toFixed(2)
                                                font.pixelSize: 22
                                                font.bold: true
                                                horizontalAlignment: TextInput.AlignHCenter
                                                validator: DoubleValidator {
                                                    bottom: 950.0
                                                    top: 1050.0
                                                    decimals: 2
                                                }
                                                onEditingFinished: {
                                                    var newValue = parseFloat(text)
                                                    if (!isNaN(newValue) && newValue >= 950 && newValue <= 1050) {
                                                        qnhSetting = newValue
                                                    } else {
                                                        text = qnhSetting.toFixed(2)
                                                    }
                                                }
                                            }
                                        }

                                        Button {
                                            text: "+"
                                            width: 50
                                            height: 50
                                            font.pixelSize: 24
                                            onClicked: {
                                                qnhSetting = Math.min(1050, qnhSetting + 1)
                                            }
                                        }
                                    }

                                    Text {
                                        text: qnhSetting.toFixed(2) + " hPa"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        font.pixelSize: 18
                                        color: "#3b82f6"
                                        font.bold: true
                                    }
                                }

                                Rectangle {
                                    width: 2
                                    height: 150
                                    color: "#cbd5e1"
                                }

                                Column {
                                    spacing: 10

                                    Text {
                                        text: "Inches of Mercury (inHg)"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Row {
                                        spacing: 10

                                        Button {
                                            text: "-"
                                            width: 50
                                            height: 50
                                            font.pixelSize: 24
                                            onClicked: {
                                                qnhSetting = Math.max(950, qnhSetting - 0.03386)
                                            }
                                        }

                                        Rectangle {
                                            width: 150
                                            height: 50
                                            border.color: "#3b82f6"
                                            border.width: 2
                                            radius: 4

                                            TextInput {
                                                id: qnhInHgInput
                                                anchors.centerIn: parent
                                                text: (qnhSetting * 0.02953).toFixed(2)
                                                font.pixelSize: 22
                                                font.bold: true
                                                horizontalAlignment: TextInput.AlignHCenter
                                                validator: DoubleValidator {
                                                    bottom: 28.0
                                                    top: 31.0
                                                    decimals: 2
                                                }
                                                onEditingFinished: {
                                                    var newValue = parseFloat(text)
                                                    if (!isNaN(newValue) && newValue >= 28 && newValue <= 31) {
                                                        qnhSetting = newValue / 0.02953
                                                    } else {
                                                        text = (qnhSetting * 0.02953).toFixed(2)
                                                    }
                                                }
                                            }
                                        }

                                        Button {
                                            text: "+"
                                            width: 50
                                            height: 50
                                            font.pixelSize: 24
                                            onClicked: {
                                                qnhSetting = Math.min(1050, qnhSetting + 0.03386)
                                            }
                                        }
                                    }

                                    Text {
                                        text: (qnhSetting * 0.02953).toFixed(2) + " inHg"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        font.pixelSize: 18
                                        color: "#3b82f6"
                                        font.bold: true
                                    }
                                }
                            }

                            Row {
                                spacing: 15
                                anchors.horizontalCenter: parent.horizontalCenter

                                Button {
                                    text: "Standard (1013.25 hPa - 29.92 inHg)"
                                    onClicked: qnhSetting = 1013.25
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Button {
        id: flagButton
        text: "Flag: " + flagValue
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 30
        z: 10
        onClicked: {
            console.log("Flag button clicked")
            flagValue++  // Increment the flag value

            if (socket1.isConnected && socket1.isAdvertised) {
                var flagMsg = {
                    "ros_stamp": ros_ts,
                    "esp32_stamp": esp_ts,
                    "flag": flagValue
                }
                socket1.publishMessage(flagMsg)

            } else {
                console.log("Cannot publish: Rosbridge not connected or topic not advertised")
            }
        }
    }

    Text {
        id: statusText
        text: "Initializing..."
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 30
        font.pixelSize: 14
        font.bold: true
        z: 10
    }

    Dialog {
        id: recordConfirmDialog
        title: "Confirm Recording"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No

        property bool isStarting: true

        contentItem: Column {
            spacing: 20
            padding: 20

            Text {
                text: recordConfirmDialog.isStarting ?
                      "Are you sure you want to start recording?" :
                      "Are you sure you want to stop recording?"
                font.pixelSize: 16
                wrapMode: Text.WordWrap
                width: 300
            }

            Text {
                text: recordConfirmDialog.isStarting ?
                      "This will create a new ROS2 bag file." :
                      "Recording will be stopped and saved."
                font.pixelSize: 14
                color: "#64748b"
                wrapMode: Text.WordWrap
                width: 300
            }
        }

        onAccepted: {
            if (recordConfirmDialog.isStarting) {
                // Start recording
                recordButton.recordingCounter++
                var command = "ros2 bag record -o /transcend/fmpi_" + recordButton.recordingCounter +
                             " /fmu/out/sensor_combined /fmu/out/vehicle_odometry /fmu/out/vehicle_gps_position /esp32/wing_data /app/flag" // the rosbag recording command
                socket.sendTextMessage(command)
                statusText.text = "Starting recording..."
                statusText.color = "orange"
                console.log("Sent command: " + command)
            } else {
                // Stop recording
                socket.sendTextMessage("stop_recording")
                statusText.text = "Stopping recording..."
                statusText.color = "orange"
                console.log("Sent stop recording command")
            }
        }

        onRejected: {
            console.log("Recording action cancelled")
        }
    }

    Button {
        id: recordButton
        text: "Record"
        anchors.right: parent.right
        anchors.bottom: flagButton.top
        anchors.margins: 30
        z: 10

        property int recordingCounter: 0

        onClicked: {
            if (socket.status === WebSocket.Open) {
                recordConfirmDialog.isStarting = !isRecording
                recordConfirmDialog.open()
            } else {
                statusText.text = "Error: Not connected to WebSocket"
                statusText.color = "red"
                console.log("Cannot send - WebSocket not connected")
            }
        }
    }

    Component.onCompleted: {
        if (Qt.platform.os === "android") {
            Qt.application.keepScreenOn = true
        }
    }
}
