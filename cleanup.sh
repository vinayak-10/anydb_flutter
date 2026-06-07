#!/bin/bash
# cleanup.sh - Free up disk space, CPU, and RAM resources in anydb_flutter project

echo "=== 🧹 Starting anydb_flutter Resource Cleanup ==="

# 1. Clear massive heap dump files from android/ directory
echo "👉 Deleting JVM heap dump (.hprof) files..."
find android/ -name "*.hprof" -maxdepth 1 -print -delete 2>/dev/null || true

# 2. Stop Gradle Daemons
echo "👉 Stopping running Gradle daemons..."
if [ -f "android/gradlew" ]; then
    (cd android && ./gradlew --stop)
else
    echo "gradlew not found in android/ folder."
fi

# 3. Kill lingering compiler and analysis processes
echo "👉 Killing lingering Dart, Flutter, and Java compile daemons..."
pkill -f "dart" || true
pkill -f "flutter_tools" || true
pkill -f "KotlinCompileDaemon" || true

# 4. Clean Flutter build output caches
echo "👉 Running flutter clean..."
flutter clean

# 5. Clear Windows build outputs
echo "👉 Deleting build_win/ directory..."
rm -rf build_win/

# 6. Clear local .xwin-cache directory (SDK cross-compilation caches)
echo "👉 Deleting .xwin-cache/ directory..."
rm -rf .xwin-cache/

# 7. Clear generated reports, large test data exports, and logs in root directory
echo "👉 Clearing local generated reports (.xlsx), data exports, and log files..."
rm -f *.xlsx
rm -f Patients_*.json
rm -f *.log
rm -f test_sign_in.dart

# 8. Prune unreachable git objects to fix git warnings
echo "👉 Pruning unreachable loose git objects..."
rm -f .git/gc.log
git gc --prune=now --quiet

echo "=== ✅ Cleanup complete! Resources freed. ==="
