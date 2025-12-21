#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDebug>
#include <QDir>
#include <QStandardPaths>
#include <QFile>
#include <QFileInfoList>
#include <QSettings>

// --- Recursive Copy Function ---
bool copyRecursive(const QString &sourcePath, const QString &destinationPath)
{
    QDir sourceDir(sourcePath);
    QDir destinationDir(destinationPath);

    if (!sourceDir.exists()) {
        qWarning() << "Source path does not exist:" << sourcePath;
        return false;
    }

    if (!destinationDir.exists() && !destinationDir.mkpath(destinationPath)) {
        qWarning() << "Could not create destination directory:" << destinationPath;
        return false;
    }

    QFileInfoList entries = sourceDir.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot);

    qDebug() << "Copying from" << sourcePath << "found" << entries.count() << "entries";

    for (const QFileInfo &entry : entries) {
        QString newSourcePath = entry.filePath();
        QString newDestinationPath = destinationPath + QDir::separator() + entry.fileName();

        if (entry.isDir()) {
            qDebug() << "Copying directory:" << entry.fileName();
            if (!copyRecursive(newSourcePath, newDestinationPath)) {
                return false;
            }
        } else if (entry.isFile()) {
            if (QFile::exists(newDestinationPath)) {
                continue;
            }
            if (!QFile::copy(newSourcePath, newDestinationPath)) {
                qWarning() << "Could not copy file:" << newSourcePath << "to" << newDestinationPath;
                return false;
            }
        }
    }

    return true;
}

int main(int argc, char *argv[])
{
    qputenv("QT_LOGGING_RULES", "qt.network.ssl=false");
    qputenv("QT_IM_MODULE", QByteArray("qtvirtualkeyboard"));

#ifdef Q_OS_ANDROID
    qputenv("QSG_RHI_BACKEND", "opengl");
    qputenv("QT_ANDROID_DISABLE_ACCESSIBILITY", "1");
#else
    qputenv("QSG_RHI_BACKEND", "opengl");
#endif

    QGuiApplication app(argc, argv);

    qDebug() << "=== APPLICATION START ===";

    QString sourcePath;

#ifdef Q_OS_ANDROID
    sourcePath = "assets:/offline_tiles";
    qDebug() << "Platform: Android - using assets";

    QDir assetsCheck(sourcePath);
    qDebug() << "Assets path exists:" << assetsCheck.exists();

    if (assetsCheck.exists()) {
        QStringList assetContents = assetsCheck.entryList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot);
        qDebug() << "Assets contents:" << assetContents;
        qDebug() << "Assets count:" << assetContents.count();
    } else {
        qCritical() << "Assets NOT accessible!";
        qCritical() << "Make sure android/assets/offline_tiles exists and was included in the build.";
    }
#else
    sourcePath = QCoreApplication::applicationDirPath() + "/offline_tiles";
    qDebug() << "Platform: Desktop - using application directory";
#endif

    QString appDataRoot = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QString offlineTilesPath = appDataRoot + QDir::separator() + "osm_tiles";

    qDebug() << "Source:" << sourcePath;
    qDebug() << "Destination:" << offlineTilesPath;

    QDir destinationDir(offlineTilesPath);
    if (!destinationDir.mkpath(offlineTilesPath)) {
        qCritical() << "Failed to create destination:" << offlineTilesPath;
        return -1;
    }

    bool needsCopy = destinationDir.isEmpty(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot);

    qDebug() << "Destination exists:" << destinationDir.exists();
    qDebug() << "Destination is empty:" << needsCopy;

    // Force recopy if directory exists but has no zoom levels
    if (!needsCopy) {
        QStringList zoomCheck = destinationDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        if (zoomCheck.isEmpty()) {
            qWarning() << "Tiles directory exists but is empty! Forcing recopy...";
            destinationDir.removeRecursively();
            destinationDir.mkpath(offlineTilesPath);
            needsCopy = true;
        }
    }

    if (needsCopy) {
        qDebug() << "Starting tile copy (this may take a few minutes)...";

        QDir sourceDir(sourcePath);
        if (!sourceDir.exists()) {
            qCritical() << "Source tiles not found at:" << sourcePath;
            return -1;
        }

        if (!copyRecursive(sourcePath, offlineTilesPath)) {
            qCritical() << "Failed to copy tiles!";
            return -1;
        }
        qDebug() << "Tiles copied successfully!";
    } else {
        qDebug() << "Tiles already present.";
    }

    qDebug() << "=== TILE VERIFICATION ===";

    QDir tilesCheck(offlineTilesPath);
    QStringList zoomLevels = tilesCheck.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    qDebug() << "Zoom levels found:" << zoomLevels;
    qDebug() << "Zoom level count:" << zoomLevels.count();

    QString testTile1 = offlineTilesPath + "/8/134/87.png";
    QString testTile2 = offlineTilesPath + "/8/133/88.png";
    qDebug() << "Tile 8/134/87.png exists:" << QFile::exists(testTile1);
    qDebug() << "Tile 8/133/88.png exists:" << QFile::exists(testTile2);

    if (zoomLevels.isEmpty()) {
        qCritical() << "NO ZOOM LEVELS FOUND!";
        qCritical() << "Contents:" << tilesCheck.entryList(QDir::AllEntries | QDir::NoDotAndDotDot);
    } else {
        QString firstZoom = offlineTilesPath + "/" + zoomLevels.first();
        QDir firstZoomDir(firstZoom);
        QStringList xDirs = firstZoomDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        qDebug() << "Zoom level" << zoomLevels.first() << "has" << xDirs.count() << "X directories";
        qDebug() << "Sample X dirs:" << xDirs.mid(0, 5);

        if (!xDirs.isEmpty()) {
            QString firstXDir = firstZoom + "/" + xDirs.first();
            QDir xDir(firstXDir);
            QStringList yFiles = xDir.entryList(QDir::Files);
            qDebug() << "First X directory has" << yFiles.count() << "tile files";
            qDebug() << "Sample tiles:" << yFiles.mid(0, 5);
        }
    }

    qDebug() << "========================";

    QString tilePattern = "file:///" + offlineTilesPath + "/%z/%x/%y.png";
    tilePattern.replace("\\", "/");

    qDebug() << "Tile pattern:" << tilePattern;

    QSettings settings("qt.labs.location", "osm");
    settings.setValue("osm.mapping.custom.host", tilePattern);
    settings.setValue("osm.mapping.cache.directory", offlineTilesPath);
    settings.setValue("osm.mapping.offline.directory", offlineTilesPath);
    settings.setValue("osm.mapping.offline.enabled", true);
    settings.setValue("osm.mapping.providersrepository.disabled", true);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("offlineTilesPath", offlineTilesPath);

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/HMI0/Main.qml")));

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    qDebug() << "Application started successfully";
    return app.exec();
}
