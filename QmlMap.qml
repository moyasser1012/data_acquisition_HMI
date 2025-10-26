import QtQuick
import QtLocation
import QtPositioning

Rectangle {
    id: window
    property double latitude: 51.5072
    property double longitude: 0.1276

    property Component Locationmarker: maker
    Plugin {
        id: googlemapview
        name: "osm"
    }
    Map {
        id: mapView
        anchors.fill: parent
        plugin: googlemapview
        center: QtPositioning.coordinate(latitude, longitude)
        zoomLevel: 10
    }
}
