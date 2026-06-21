# 📱 Android Database Storage & Backup Architecture Context

This document outlines the directory structure, storage paths, and filesystem access/navigability rules for the **anydb** Flutter application on Android devices.

---

## 💾 Storage Directories Overview

The application utilizes three main storage locations on Android:

### 1. Active WAL SQLite Database (Internal/Private)
The live SQLite database is stored in the application's private sandbox folder.
* **Path**: `/data/user/0/com.example.anydbFlutter/app_flutter/xyz.maya/anydb/anydb_storage.db`
* **Purpose**: Houses the SQLite database running in WAL (Write-Ahead Logging) mode, indexes, metadata checkpoints, and caching layers.
* **Navigability**: **Locked/Not Navigable.** This directory is protected by Android's user-isolation security model and cannot be viewed or accessed unless the device is rooted.

### 2. Local Backup & Export Files (External/App-Specific)
When the user executes a local export or initiates a database schema backup, JSON records and generated Excel reports are written to both internal sandboxed storage and external app-specific storage.

* **External Directory (Public-Facing)**:
  * **Path**: `/storage/emulated/0/Android/data/com.example.anydbFlutter/files/xyz.maya/anydb/`
  * **Subfolders**:
    * `[SchemaName]/Database/` - Local JSON backups of collections.
    * `[SchemaName]/Aggregators/` - Generated spreadsheet reports.
    * `[SchemaName]/logs/` - Crash/exception logs.
* **Internal Directory (Sandboxed)**:
  * **Path**: `/data/user/0/com.example.anydbFlutter/app_flutter/xyz.maya/anydb/`

### 3. Cloud Backup (Google Drive)
Manual database backups are uploaded to Google Drive.
* **Folder Path**: `/xyz.maya/anydb/Database/`
* **File Format**: `[DatabaseName]_backup_[Timestamp].json`

---

## 🧭 Navigability & File Access Guide

Since the local files are stored under `/Android/data/`, modern Android OS restrictions apply:

### 1. Android 10 and Below
* **Navigability**: **Fully Navigable.**
* **Method**: Any standard Android File Explorer app (e.g., Files by Google) can navigate directly to the directory.

### 2. Android 11+ (Scoped Storage Limitations)
Google introduced Scoped Storage, blocking standard on-device apps from directly reading/writing to `/Android/data/`.
* **Method A: USB to Computer (Recommended)**:
  1. Connect the Android device to a PC or Mac via USB in **File Transfer (MTP)** mode.
  2. Open the computer's File Explorer.
  3. Navigate to: `Internal Shared Storage > Android > data > com.example.anydbFlutter > files > xyz.maya > anydb`
  4. Files can be copied, deleted, or imported directly.
* **Method B: Advanced File Managers**:
  1. Install an app that supports Android's **Storage Access Framework (SAF)** (e.g., Solid Explorer, MiXplorer, FV File Manager).
  2. Attempt to navigate to `/Android/data/`. The app will prompt to open a system-picker redirect.
  3. Click **"Use this folder"** to grant permission. The path will then be navigable.
