cmake_minimum_required(VERSION 3.16)
project(HMI0 VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Find required Qt components
find_package(Qt6 REQUIRED COMPONENTS
    Core
    Quick
    Network
    WebSockets
    Location
    Positioning
    Gui
)

qt_standard_project_setup(REQUIRES 6.8)

# Create executable with all source files
qt_add_executable(appHMI0
    main.cpp
)

qt_add_qml_module(appHMI0
    URI HMI0
    VERSION 1.0
    QML_FILES Main.qml
    RESOURCES resources.qrc
    RESOURCES qml.qrc
)

# Set general target properties
set_target_properties(appHMI0 PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

# Link Qt libraries
target_link_libraries(appHMI0 PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Location
    Qt6::Positioning
    Qt6::Network
    Qt6::WebSockets
)

# Installation
include(GNUInstallDirs)
install(TARGETS appHMI0
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
