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

    property int selectedIndex: 0

    property double ros_ts: 0
    property double esp_ts: 0
    property double latitude: 49.8728
    property double longitude: 8.6512

    property bool isRecording: false

    property int flagValue: 0

    property real rollRate: 0.000
    property real pitchRate: 0.000
    property real yawRate: 0.000

    property real roll: 0.000
    property real pitch: 0.000
    property real yaw: 0.000

    property real vn: 0.000
    property real ve: 0.000
    property real vd: 0.000

    property real gpsSpeed: 0.000
    property real altitude: 0.000

    property real temperature: 0.000
    property real humidity: 0.000
    property real diff_pressure: 0.000
    property real baro_pressure: 0.000
    property real air_density: 0.000

    property real ias: 0.000
    property real tas: 0.000

    WebSocket {
        id: socket
        url: "ws://192.168.1.84:9099"
        active: true

        onTextMessageReceived: function(message){
            console.log("Received message: " + message)

            try {
                var response = JSON.parse(message)

                if (response.status === "success") {
                    statusText.text = response.message
                    statusText.color = "green"

                    // Update recording state based on server response
                    if (response.recording !== undefined) {
                        // Status check response
                        isRecording = response.recording
                        recordButton.text = isRecording ? "Stop Recording" : "Record"
                    } else if (response.message.indexOf("Started recording") !== -1) {
                        isRecording = true
                        recordButton.text = "Stop Recording"
                    } else if (response.message.indexOf("stopped") !== -1) {
                        isRecording = false
                        recordButton.text = "Record"
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
            } else if (socket.status === WebSocket.Closed) {
                statusText.text = "Disconnected"
                statusText.color = "orange"
                reconnectTimer.start()
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
        interval: 2000  // Check status every 2 seconds
        repeat: true
        running: socket.status === WebSocket.Open
        onTriggered: {
            if (socket.status === WebSocket.Open) {
                socket.sendTextMessage("status")
            }
        }
    }


    WebSocket {
        id: socket1
        url: "ws://192.168.1.84:9090"
        active: true

        property bool isConnected: false
        property string publishTopicName: "/app/flag"
        property string publishMessageType: "flag_msgs/msg/Flag"
        property bool isAdvertised: false
        property int reconnectAttempts: 0
        property int maxReconnectAttempts: 10

        // Subscription tracking
        property var subscribedTopics: ({})

        onTextMessageReceived: function(message) {
            try {
                var rosMsg = JSON.parse(message)

                // Check if this is a published topic message
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
                            rollRate = msg.gyro_rad[0].toFixed(3)
                            pitchRate = msg.gyro_rad[1].toFixed(3)
                            yawRate = msg.gyro_rad[2].toFixed(3)
                        }

                        // Barometer data
                        if (msg.baro_temp_celcius !== undefined) {
                            temperature = msg.baro_temp_celcius.toFixed(2)
                        }
                        if (msg.baro_pressure_pa !== undefined) {
                            baro_pressure = (msg.baro_pressure_pa / 100).toFixed(2) // Convert Pa to hPa
                        }

                        // Differential pressure (for airspeed)
                        if (msg.differential_pressure_pa !== undefined) {
                            diff_pressure = msg.differential_pressure_pa.toFixed(2)

                            // Calculate IAS from differential pressure
                            // IAS = sqrt(2 * diff_pressure / air_density)
                            // Using standard air density of 1.225 kg/m³
                            var rho = 1.225
                            if (air_density > 0) {
                                rho = air_density
                            }
                            if (msg.differential_pressure_pa > 0) {
                                ias = Math.sqrt(2 * msg.differential_pressure_pa / rho).toFixed(2)
                            } else {
                                ias = 0
                            }
                        }
                    }

                    // Handle /fmu/out/vehicle_gps_position
                    else if (topic === "/fmu/out/vehicle_gps_position") {
                        if (msg.lat !== undefined && msg.lon !== undefined) {
                            latitude = (msg.lat / 1e7).toFixed(6) // GPS coords are in degrees * 1e7
                            longitude = (msg.lon / 1e7).toFixed(6)
                        }

                        if (msg.alt !== undefined) {
                            altitude = (msg.alt / 1000).toFixed(2) // Convert mm to m
                        }

                        if (msg.vel_m_s !== undefined) {
                            gpsSpeed = msg.vel_m_s.toFixed(2)
                        }
                    }

                    // Handle /fmu/out/vehicle_odometry
                    else if (topic === "/fmu/out/vehicle_odometry") {
                        // Velocity in NED frame
                        if (msg.velocity !== undefined && msg.velocity.length >= 3) {
                            vn = msg.velocity[0].toFixed(3)
                            ve = msg.velocity[1].toFixed(3)
                            vd = msg.velocity[2].toFixed(3)
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
                            roll = (Math.atan2(sinr_cosp, cosr_cosp) * 180 / Math.PI).toFixed(2)

                            // Pitch (y-axis rotation)
                            var sinp = 2 * (qw * qy - qz * qx)
                            if (Math.abs(sinp) >= 1)
                                pitch = (Math.sign(sinp) * 90).toFixed(2)
                            else
                                pitch = (Math.asin(sinp) * 180 / Math.PI).toFixed(2)

                            // Yaw (z-axis rotation)
                            var siny_cosp = 2 * (qw * qz + qx * qy)
                            var cosy_cosp = 1 - 2 * (qy * qy + qz * qz)
                            yaw = (Math.atan2(siny_cosp, cosy_cosp) * 180 / Math.PI).toFixed(2)
                        }
                    }

                    // Handle /esp32/wing_data
                    else if (topic === "/esp32/wing_data") {
                        if (msg.temperature !== undefined) {
                            temperature = msg.temperature.toFixed(2)
                        }
                        if (msg.humidity !== undefined) {
                            humidity = msg.humidity.toFixed(2)
                        }
                        if (msg.air_density !== undefined) {
                            air_density = msg.air_density.toFixed(3)
                        }
                        if (msg.timestamp !== undefined) {
                            esp_ts = msg.timestamp.toFixed(0)
                        }
                        if (msg.baro_pressure !== undefined) {
                            baro_pressure = msg.baro_pressure.toFixed(4)
                        }
                        if (msg.diff_pressure !== undefined) {
                            diff_pressure = msg.diff_pressure.toFixed(4)
                        }
                        // Calculate TAS if we have IAS and air density
                        if (ias > 0 && air_density > 0) {
                            // TAS = IAS * sqrt(rho_0 / rho)
                            // where rho_0 = 1.225 kg/m³ (standard air density at sea level)
                            tas = (ias * Math.sqrt(1.225 / air_density)).toFixed(2)
                        }
                    }
                }
            } catch (e) {
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

        // Function to unadvertise the topic (call when closing app)
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

                // Force close and reopen connection
                socket1.active = false
                // Small delay before reactivating
                reopenTimer.start()
            }
        }
    }

    // Small delay timer for reopening connection
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
                text: "Six pack"
                onClicked: selectedIndex = 2
            }

            TabButton {
                text: "Settings"
                onClicked: selectedIndex = 3
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
                         settingsPage
    }


    Component {
        id: mapPage
        Rectangle {
            anchors.fill: parent
            color: "lightblue"

            Map {
                id: map1
                anchors.fill: parent
                activeMapType: map1.supportedMapTypes[0]
                plugin: Plugin {
                    name: "osm"
                    PluginParameter {
                        name: "osm.mapping.offline.directory"
                        value: ":/offline_tiles/"
                    }
                }

                center {
                    latitude: latitude
                    longitude: longitude
                }
                zoomLevel: 8
                minimumZoomLevel: 8
                maximumZoomLevel: 12

                // Red marker at current position
                MapQuickItem {
                    anchorPoint.x: marker.width / 2
                    anchorPoint.y: marker.height
                    coordinate: QtPositioning.coordinate(latitude, longitude)

                    sourceItem: Rectangle {
                        id: marker
                        width: 20
                        height: 20
                        radius: 10
                        color: "red"
                        border.color: "white"
                        border.width: 3
                    }
                }
            }

            // Zoom controls
            Column {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 20
                spacing: 10
                z: 10

                Button {
                    text: "+"
                    width: 50
                    height: 50
                    font.pixelSize: 24
                    font.bold: true
                    onClicked: {
                        if (map1.zoomLevel < map1.maximumZoomLevel) {
                            map1.zoomLevel += 1
                        }
                    }

                    background: Rectangle {
                        color: parent.pressed ? "#0066cc" : "#0080ff"
                        radius: 25
                        border.color: "white"
                        border.width: 2
                    }

                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        font: parent.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    text: "−"
                    width: 50
                    height: 50
                    font.pixelSize: 24
                    font.bold: true
                    onClicked: {
                        if (map1.zoomLevel > map1.minimumZoomLevel) {
                            map1.zoomLevel -= 1
                        }
                    }

                    background: Rectangle {
                        color: parent.pressed ? "#0066cc" : "#0080ff"
                        radius: 25
                        border.color: "white"
                        border.width: 2
                    }

                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        font: parent.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
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

            // Main grid layout for better organization
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
                                text: ias + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: tas + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: gpsSpeed + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: vn + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: ve + " m/s"
                                font.pixelSize: baseFontSize
                                font.bold: true
                            }
                            Text {
                                text: vd + " m/s"
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
                                text: roll + "°"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: pitch + "°"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: yaw + "°"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: rollRate + " rad/s"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: pitchRate + " rad/s"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: yawRate + " rad/s"
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
                                text: temperature + " °C"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: humidity + " %"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: baro_pressure + " hPa"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: diff_pressure + " Pa"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: altitude + " m"
                                font.pointSize: 18
                                font.bold: true
                            }
                            Text {
                                text: air_density + " kg/m³"
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

                // Top Row - Airspeed Indicator (using tas)
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

                                    for (var speed = 0; speed <= 270; speed += 10) {
                                        var angle = (speed / 270) * 270 - 225
                                        var rad = angle * Math.PI / 180

                                        var isMajor = speed % 30 === 0
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
                                rotation: (Math.min(tas, 270) / 270) * 270 - 135

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
                                font.pixelSize: 10
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 15
                            }
                        }
                    }
                }

                // Attitude Indicator (using roll and pitch)
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
                                    y: horizon.height / 2 + pitch * 2

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


                // Altimeter (using altitude)
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

                                    for (var i = 0; i <= 10; i++) {
                                        var angle = (i / 10) * 360 - 90
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
                                        ctx.fillText((i * 4).toString(), labelX, labelY)
                                    }
                                }
                            }

                            Item {
                                anchors.centerIn: parent
                                rotation: (altitude / 4000) * 360

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
                                text: "ALT"
                                color: "white"
                                font.pixelSize: 10
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 15
                            }
                        }
                    }
                }

                // Turn Coordinator (using yawRate)
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

                // Heading Indicator
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
                                            ctx.fillText(dir.label, labelX, labelY)
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
                                font.pixelSize: 10
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 15
                            }
                        }
                    }
                }

                // Vertical Speed Indicator (using vd)
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

                                    var values = [
                                        {val: 2, angle: -70},
                                        {val: 1, angle: -35},
                                        {val: 0, angle: 0},
                                        {val: -1, angle: 35},
                                        {val: -2, angle: 70}
                                    ]

                                    for (var i = 0; i < values.length; i++) {
                                        var item = values[i]
                                        var angle = (90 + item.angle) * Math.PI / 180

                                        var tickLength = item.val === 0 ? 15 : 12
                                        ctx.lineWidth = item.val === 0 ? 2 : 1

                                        var x1 = cx + radius * Math.cos(angle)
                                        var y1 = cy + radius * Math.sin(angle)
                                        var x2 = cx + (radius - tickLength) * Math.cos(angle)
                                        var y2 = cy + (radius - tickLength) * Math.sin(angle)

                                        ctx.beginPath()
                                        ctx.moveTo(x1, y1)
                                        ctx.lineTo(x2, y2)
                                        ctx.stroke()

                                        var labelRadius = radius - 28
                                        var labelX = cx + labelRadius * Math.cos(angle)
                                        var labelY = cy + labelRadius * Math.sin(angle)

                                        var label = item.val === 0 ? "0" : Math.abs(item.val).toString()
                                        ctx.fillText(label, labelX, labelY)
                                    }

                                    ctx.font = "bold 10px Arial"
                                    ctx.fillText("UP", cx, cy - radius + 20)
                                    ctx.fillText("DN", cx, cy + radius - 12)
                                }
                            }

                            Item {
                                anchors.centerIn: parent
                                rotation: {
                                    var vdFpm = vd * 196.85
                                    var clampedSpeed = Math.max(-2000, Math.min(2000, vdFpm))
                                    return (clampedSpeed / 2000) * 70
                                }

                                Rectangle {
                                    width: 2
                                    height: parent.parent.height * 0.35
                                    color: "white"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.verticalCenter
                                    antialiasing: true

                                    Canvas {
                                        width: 10
                                        height: 12
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: -12
                                        Component.onCompleted: requestPaint()

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.fillStyle = "white"

                                            ctx.beginPath()
                                            ctx.moveTo(width / 2, 0)
                                            ctx.lineTo(0, height)
                                            ctx.lineTo(width, height)
                                            ctx.closePath()
                                            ctx.fill()
                                        }
                                    }
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
                                text: "VSI"
                                color: "white"
                                font.pixelSize: 10
                                font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 15
                            }
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

    Button {
        id: recordButton
        text: "Record"
        anchors.right: parent.right
        anchors.bottom: flagButton.top
        anchors.margins: 30
        z: 10

        onClicked: {
            if (socket.status === WebSocket.Open) {
                if (isRecording) {
                    // Stop recording - send the correct command
                    socket.sendTextMessage("stop_recording")
                    statusText.text = "Stopping recording..."
                    statusText.color = "orange"
                    console.log("Sent stop_recording command")
                } else {
                    // Start recording
                    var command = "ros2 bag record /fmu/out/sensor_combined /fmu/out/vehicle_odometry /fmu/out/vehicle_gps_position /esp32/wing_data /app/flag"
                    socket.sendTextMessage(command)
                    statusText.text = "Starting recording..."
                    statusText.color = "orange"
                    console.log("Sent command: " + command)
                }
            } else {
                statusText.text = "Error: Not connected to WebSocket"
                statusText.color = "red"
                console.log("Cannot send - WebSocket not connected")
            }
        }
    }
}
