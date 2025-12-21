cmake_minimum_required(VERSION 3.16)
project(HMI0 VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Quick
    Network
    WebSockets
    Location
    Positioning
    Gui
    Core5Compat
    QuickControls2
)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(appHMI0
    main.cpp
)

qt_add_qml_module(appHMI0
    URI HMI0
    VERSION 1.0
    QML_FILES Main.qml
)

set_target_properties(appHMI0 PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

if(ANDROID)
    set_property(TARGET appHMI0 APPEND PROPERTY QT_ANDROID_PACKAGE_SOURCE_DIR
        ${CMAKE_CURRENT_SOURCE_DIR}/android)

    message(STATUS "Android package source: ${CMAKE_CURRENT_SOURCE_DIR}/android")

    # Check if offline tiles exist in assets
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/android/assets/offline_tiles")
        file(GLOB_RECURSE ASSET_TILES "${CMAKE_CURRENT_SOURCE_DIR}/android/assets/offline_tiles/*.png")
        list(LENGTH ASSET_TILES TILE_COUNT)

        message(STATUS "Found offline tiles in Android assets")
        message(STATUS "Total tiles: ${TILE_COUNT}")
        message(STATUS "Tiles will be packaged as assets (NOT compiled)")

        file(GLOB ZOOM_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/android/assets/offline_tiles/*")
        set(ZOOM_LEVELS "")
        foreach(ZOOM_DIR ${ZOOM_DIRS})
            if(IS_DIRECTORY ${ZOOM_DIR})
                get_filename_component(ZOOM_LEVEL ${ZOOM_DIR} NAME)
                list(APPEND ZOOM_LEVELS ${ZOOM_LEVEL})
            endif()
        endforeach()
        message(STATUS "Zoom levels available: ${ZOOM_LEVELS}")

        if(TILE_COUNT GREATER 10000)
            message(STATUS "Note: Large tile set detected. First app launch will take time to extract tiles.")
        endif()
    else()
        message(WARNING "=================================================")
        message(WARNING "Android assets directory not found!")
        message(WARNING "Expected: ${CMAKE_CURRENT_SOURCE_DIR}/android/assets/offline_tiles/")
        message(WARNING "")
        message(WARNING "To add offline tiles:")
        message(WARNING "1. Create directory: android/assets/offline_tiles/")
        message(WARNING "2. Copy your tiles there with structure: offline_tiles/z/x/y.png")
        message(WARNING "3. Rebuild the project")
        message(WARNING "")
        message(WARNING "Map will try to use online tiles if offline tiles are missing.")
        message(WARNING "=================================================")
    endif()

    message(STATUS "===================================")

elseif(WIN32 OR UNIX OR APPLE)
    message(STATUS "=== Desktop Build Configuration ===")
    message(STATUS "Platform: Desktop")
    message(STATUS "For desktop builds, place offline_tiles/ folder next to the executable")
    message(STATUS "Expected structure: <app_dir>/offline_tiles/z/x/y.png")
    message(STATUS "===================================")
endif()

target_link_libraries(appHMI0 PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Location
    Qt6::Positioning
    Qt6::Network
    Qt6::WebSockets
    Qt6::Core5Compat
    Qt6::QuickControls2
)

include(GNUInstallDirs)

install(TARGETS appHMI0
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

if(NOT ANDROID AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/offline_tiles")
    message(STATUS "Desktop: Copying offline_tiles to build directory for testing")
    file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/offline_tiles
         DESTINATION ${CMAKE_CURRENT_BINARY_DIR})
endif()
