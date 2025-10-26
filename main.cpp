#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDebug>
#include <QDir>
#include <QStandardPaths>

int main(int argc, char *argv[])
{
    // Set Qt environment variables BEFORE QGuiApplication
    qputenv("QT_LOGGING_RULES", "qt.network.ssl=false");
    qputenv("QSG_RHI_BACKEND", "opengl");
    qputenv("QT_IM_MODULE", QByteArray("qtvirtualkeyboard"));

    // Disable OpenGL if causing issues on Android
#ifdef Q_OS_ANDROID
    qputenv("QSG_RHI_BACKEND", "vulkan");  // Try Vulkan instead of OpenGL
    qputenv("QT_ANDROID_DISABLE_ACCESSIBILITY", "1");
#endif

    QGuiApplication app(argc, argv);

    // Debug info
    qDebug() << "=== APPLICATION START ===";
    qDebug() << "Platform:" << QGuiApplication::platformName();
    qDebug() << "App dir:" << QCoreApplication::applicationDirPath();

#ifdef Q_OS_ANDROID
    qDebug() << "Android detected";
    qDebug() << "Writable location:" << QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
#endif

    // Create QML engine
    QQmlApplicationEngine engine;

    // Set up error handling BEFORE loading QML
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() {
            qCritical() << "QML object creation failed!";
            QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::warnings,
        [](const QList<QQmlError> &warnings) {
            for (const QQmlError &warning : warnings) {
                qWarning() << "QML Warning:" << warning.toString();
            }
        });

    // Load QML with error checking
    const QUrl url(QStringLiteral("qrc:/qt/qml/HMI0/Main.qml"));

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                qCritical() << "Failed to load QML from:" << objUrl;
                QCoreApplication::exit(-1);
            } else {
                qDebug() << "QML loaded successfully from:" << objUrl;
            }
        },
        Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qCritical() << "No root objects loaded - exiting";
        return -1;
    }

    qDebug() << "Application started successfully";
    return app.exec();
}
