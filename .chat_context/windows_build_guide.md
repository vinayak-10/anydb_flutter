# 🪟 Windows Desktop Cross-Compilation Guide from Linux

This guide outlines how to build a native Windows executable (`.exe`) for your **anydb** Flutter application directly from your Linux host environment. It details the technical challenges of cross-compilation, provides a production-grade CI/CD automation pipeline (the recommended standard), and explores advanced local Linux cross-compilation alternatives.

---

## 🔍 The Core Challenge: Why Doesn't it Work Out-of-the-Box?

When you run `flutter build windows` on Linux, the Flutter toolchain blocks you with an error. This is because Flutter's Windows desktop shell is built in native C++ and depends on three Microsoft-proprietary components:

1. **The MSVC Build Tools:** The Microsoft Visual C++ compiler (`cl.exe`) and linker (`link.exe`) are natively compiled for Windows systems only.
2. **The Windows SDK:** The native C++ runner requires Windows header files (e.g., `windows.h`, Win32 API declarations) and runtime import libraries (`.lib` files).
3. **Precompiled Windows Engine Binaries:** The Flutter engine binary (`flutter_windows.dll`) is compiled by Google using MSVC, creating strict link-compatibility requirements.

To build for Windows from Linux, we must use one of three architectural workarounds:

---

## 🚀 Solution A: GitHub Actions CI/CD Pipeline (Recommended Standard)

Using a free Cloud CI/CD runner is the **industry standard** for cross-compiling desktop apps. Since your code is version-controlled, you can let Google’s native Windows toolchain compile your executable automatically in the cloud on every git push, uploading a packaged release `.zip` in under 5 minutes.

Here is a fully functional, production-ready GitHub Actions workflow.

### Setup Instructions:
Create a file at `.github/workflows/build_windows.yml` in your project folder and paste the following content:

```yaml
name: 🪟 Windows Desktop Release Build

on:
  push:
    branches: [ main, dev ]
  workflow_dispatch: # Allows manual trigger from the GitHub UI

jobs:
  build-windows:
    runs-on: windows-latest
    
    steps:
      # 1. Checkout codebase
      - name: 📥 Checkout Code
        uses: actions/checkout@v4

      # 2. Setup Java Environment (Required for Flutter dependencies)
      - name: ☕ Setup Java JDK
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'

      # 3. Setup Flutter Environment
      - name: 🐦 Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      # 4. Inject Compile-time Secrets
      - name: 🔑 Inject Secrets
        shell: bash
        run: |
          # Recreates secrets.json in the cloud using secret environment variables
          echo '${{ secrets.SECRETS_JSON }}' > secrets.json

      # 5. Fetch dependencies
      - name: 📦 Fetch Packages
        run: flutter pub get

      # 6. Compile Windows Native Release Binary
      - name: ⚙️ Build Windows Executable
        run: |
          flutter build windows --release --dart-define-from-file=secrets.json

      # 7. Package Release Directory into ZIP
      - name: 📦 Archive Release
        shell: bash
        run: |
          mkdir -p output/
          cd build/windows/x64/runner/Release/
          zip -r ../../../../../output/anydb_windows_x64.zip . *

      # 8. Upload Build Artifacts
      - name: 📤 Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: anydb-windows-x64-release
          path: output/anydb_windows_x64.zip
          retention-days: 7
```

*Note: In your GitHub Repository Settings under **Secrets and Variables > Actions**, add your `SECRETS_JSON` environment variable containing the contents of your `secrets.json` to allow the build to authenticate cloud database backups successfully!*

---

## 🐳 Solution B: Local Clang/LLVM Cross-Compilation (Advanced Linux Setup)

If you must compile completely offline on your Linux host without a Windows VM or internet CI/CD pipelines, you can configure **LLVM / Clang** as a cross-compiler.

Unlike GCC, Clang is inherently a cross-compiler out of the box and can target `x86_64-pc-windows-msvc`.

### 1. Toolchain Setup on Linux
Install the compiler tools on your Linux host:
```bash
sudo apt update
sudo apt install -y clang lld llvm-dev cmake
```

### 2. Extracting Windows SDK and MSVC Headers (using `xwin`)
To compile against Windows APIs, Clang needs the official Windows SDK header files and MSVC runtime libraries. You can download and package these legally from Microsoft servers using a rust-based developer tool called `xwin`:

1. Install `xwin`:
   ```bash
   cargo install xwin
   ```
2. Download and unpack the SDK and MSVC libraries to your local directory (e.g., `/opt/xwin`):
   ```bash
   xwin --accept-license splat --output /opt/xwin
   ```

### 3. Cross-Compiling Custom Flutter Runner C++
To instruct CMake to build for Windows using Clang on your Linux host, create a custom CMake toolchain file at `windows/toolchain.cmake`:

```cmake
# toolchain.cmake for targeting Windows from Linux
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Set compilers to Clang/Clang++
set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_RC_COMPILER llvm-rc)

# Point to xwin directory headers and libraries
set(XWIN_DIR "/opt/xwin")
set(CMAKE_SYSROOT ${XWIN_DIR})

# Configure Clang Target Triplet and MSVC headers
set(TARGET_TRIPLE "x86_64-pc-windows-msvc")
set(CMAKE_C_FLAGS "-target ${TARGET_TRIPLE} -I${XWIN_DIR}/headers" CACHE STRING "")
set(CMAKE_CXX_FLAGS "-target ${TARGET_TRIPLE} -I${XWIN_DIR}/headers" CACHE STRING "")
set(CMAKE_EXE_LINKER_FLAGS "-fuse-ld=lld -L${XWIN_DIR}/crt/lib/x86_64 -L${XWIN_DIR}/sdk/lib/um/x86_64" CACHE STRING "")
```

When building, you override the compilation target of Flutter's internal C++ generator with this toolchain file.

---

## 🍷 Solution C: Wine-Emulated MSVC Compilation (Local Linux Emulation)

Another local alternative is running the official Microsoft Visual Studio compiler toolchain (`cl.exe`, `link.exe`) directly inside **Wine** on your Linux desktop.

### 1. Setup a Clean 64-bit Wine Prefix
Configure a stable 64-bit environment:
```bash
export WINEPREFIX=~/.wine-msvc
export WINEARCH=win64
winecfg
```

### 2. Install MSVC Build Tools via `msvc-wine`
Rather than installing the heavy Visual Studio UI inside Wine, you can use the open-source **`msvc-wine`** project to download, extract, and wrap only the raw command-line compiler tools (`cl.exe` and `link.exe`):

1. Clone the wrapper repository:
   ```bash
   git clone https://github.com/mstorsjo/msvc-wine.git
   cd msvc-wine
   ```
2. Run the downloader to extract the MSVC compiler binaries and SDK files into a local folder:
   ```bash
   ./vsdownload.py --dest /opt/msvc
   ```
3. Set up wrapper symlinks so that when you call `cl` or `link` in Linux, it automatically routes them through Wine:
   ```bash
   ./install.sh /usr/local/bin
   ```

### 3. Build Your App
With `cl` and `link` successfully wrapped under your Linux bin environment, you can now run Flutter C++ compiles natively, and the build tool will output the completed Windows executable to `build/windows/x64/runner/Release/anydb_flutter.exe` right inside your Linux environment!
