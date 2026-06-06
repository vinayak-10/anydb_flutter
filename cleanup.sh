#!/bin/bash
# cleanup.sh - Free up disk space, CPU, and RAM resources in anydb_flutter project

echo "=== 🧹 Starting anydb_flutter Resource Cleanup ==="

# 1. Clear massive heap dump files from android/ directory
echo "👉 Deleting JVM heap dump (.hprof) files..."
find android/ -name "*.hprof" -maxdepth 1 -print -delete

# 2. Stop Gradle Daemons
echo "👉 Stopping running Gradle daemons..."
if [ -f "android/gradlew" ]; then
    (cd android && ./gradlew --stop)
else
    echo "gradlew not found in android/ folder."
fi

# 3. Kill lingering compiler and analysis processes
echo "👉 Killing lingering Dart, Flutter, and Java compile daemons..."
pkill -f "dart"
pkill -f "flutter_tools"
pkill -f "KotlinCompileDaemon"

# 4. Clean Flutter build output caches
echo "👉 Running flutter clean..."
flutter clean

echo "=== ✅ Cleanup complete! Resources freed. ==="
