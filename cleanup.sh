#!/bin/bash
# cleanup.sh - Clean up project and Linux system resources to free up disk, CPU, and RAM.

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

echo "=== ✅ Project cleanup complete! ==="


# === 🖥️ Section B: Linux System Resource Cleanup ===
echo ""
echo "=== 🖥️ Starting Overall System Cleanup ==="

# Check for package manager (APT-based systems like Debian/Ubuntu/Mint)
if command -v apt-get &>/dev/null; then
    echo "👉 Cleaning up system package cache (APT)..."
    sudo apt-get autoremove -y
    sudo apt-get autoclean
    sudo apt-get clean
fi

# Check for Systemd journalctl logs
if command -v journalctl &>/dev/null; then
    echo "👉 Vacuuming systemd journal logs (retaining last 3 days or 100MB)..."
    sudo journalctl --vacuum-time=3d || true
    sudo journalctl --vacuum-size=100M || true
fi

# Clean up Docker system resources (if docker is installed and running)
if command -v docker &>/dev/null; then
    echo "👉 Pruning unused Docker containers, images, and networks..."
    docker system prune -f || true
fi

# Clean User Thumbnail Cache
if [ -d "$HOME/.cache/thumbnails" ]; then
    echo "👉 Clearing user thumbnail cache..."
    rm -rf "$HOME/.cache/thumbnails"/* || true
fi

# Clean Temp directories
echo "👉 Clearing system temporary files..."
sudo rm -rf /tmp/* 2>/dev/null || true
sudo rm -rf /var/tmp/* 2>/dev/null || true

# Reclaim RAM Cache (PageCache, dentries, and inodes)
echo "👉 Attempting to sync and free RAM PageCache/buffers..."
if [ "$EUID" -ne 0 ]; then
    sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' && echo "RAM PageCache cleared successfully." || echo "Skipped RAM Cache reclamation (needs sudo)."
else
    sync && echo 3 > /proc/sys/vm/drop_caches && echo "RAM PageCache cleared successfully."
fi

echo "=== ✅ Overall System Cleanup complete! ==="
