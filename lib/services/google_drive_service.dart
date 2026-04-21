import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _currentUser;
  http.Client? _httpClient;
  
  static Completer<void>? _initCompleter;

  GoogleSignInAccount? get currentUser => _currentUser;

  Future<void> init() async {
    if (_initCompleter != null && !_initCompleter!.isCompleted) return _initCompleter!.future;
    if (_initCompleter != null && _initCompleter!.isCompleted) return;
    
    _initCompleter = Completer<void>();
    try {
      debugPrint("GoogleDriveService: Initializing API for Web/GIS...");
      await _googleSignIn.initialize(
        clientId: "147495577253-vdubk4el5gt3kv0rehttchu1f5ka2v2b.apps.googleusercontent.com",
      );
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null; 
      rethrow;
    }
    return _initCompleter!.future;
  }

  Future<bool> login() async {
    try {
      await init();
      
      final List<String> scopes = [drive.DriveApi.driveFileScope];

      if (kIsWeb) {
        debugPrint("GoogleDriveService: Web direct auth...");
        final auth = await _googleSignIn.authorizationClient.authorizeScopes(scopes);
        _httpClient = auth.authClient(scopes: scopes);
        return true; 
      } else {
        _currentUser = await _googleSignIn.authenticate();
        if (_currentUser != null) {
          var auth = await _currentUser!.authorizationClient.authorizationForScopes(scopes);
          auth ??= await _currentUser!.authorizationClient.authorizeScopes(scopes);
          _httpClient = auth.authClient(scopes: scopes);
        }
        return _currentUser != null;
      }
    } catch (error) {
      debugPrint('Google Sign-In Error: $error');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
    _currentUser = null;
    _httpClient = null;
  }

  bool get isLoggedIn => _httpClient != null || _currentUser != null;

  Future<String?> _resolvePath(drive.DriveApi api, List<String> path) async {
    String? currentParentId;
    for (final folderName in path) {
      currentParentId = await _getOrCreateFolder(api, folderName, parentId: currentParentId);
      if (currentParentId == null) return null;
    }
    return currentParentId;
  }

  Future<String?> _getOrCreateFolder(drive.DriveApi api, String folderName, {String? parentId}) async {
    try {
      String query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      if (parentId != null) {
        query += " and '$parentId' in parents";
      }

      final found = await api.files.list(
        q: query,
        spaces: 'drive',
      );

      if (found.files != null && found.files!.isNotEmpty) {
        return found.files!.first.id;
      }

      debugPrint("GoogleDrive: Creating folder '$folderName'...");
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';
      
      if (parentId != null) {
        folder.parents = [parentId];
      }
      
      final created = await api.files.create(folder);
      return created.id;
    } catch (e) {
      debugPrint("GoogleDrive: Folder error: $e");
      return null;
    }
  }

  Future<void> runAutoArchive(drive.DriveApi api, String folderId) async {
    try {
      final response = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields: 'files(id, name, mimeType, createdTime)',
      );

      final files = response.files;
      if (files == null) return;

      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      String? archiveFolderId;

      for (var file in files) {
        if (file.mimeType == 'application/vnd.google-apps.folder') continue;
        if (file.id == null) continue;

        final createdTime = file.createdTime;
        if (createdTime != null && createdTime.isBefore(thirtyDaysAgo)) {
          archiveFolderId ??= await _getOrCreateFolder(api, 'archive', parentId: folderId);
          if (archiveFolderId != null) {
            debugPrint("GoogleDrive: Archiving ${file.name}...");
            await api.files.update(
              drive.File(),
              file.id!,
              addParents: archiveFolderId,
              removeParents: folderId,
            );
          }
        }
      }
    } catch (e) {
      debugPrint("GoogleDrive: Auto-Archive error: $e");
    }
  }

  Future<void> uploadFile(String filePath, String fileName, {List<String>? path}) async {
    if (_httpClient == null) await login();
    if (_httpClient == null) throw "Not authenticated with Google. Please log in again.";

    final api = drive.DriveApi(_httpClient!);
    String? folderId;
    
    if (path != null && path.isNotEmpty) {
      folderId = await _resolvePath(api, path);
    } else {
      folderId = await _getOrCreateFolder(api, "xyz.maya");
    }

    if (folderId != null) {
      await runAutoArchive(api, folderId);
    }

    final file = drive.File()
      ..name = fileName
      ..mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    
    if (folderId != null) file.parents = [folderId];

    final ioFile = File(filePath);
    final fileStream = ioFile.openRead();
    final length = await ioFile.length();

    try {
      await api.files.create(file, uploadMedia: drive.Media(fileStream, length));
    } catch (e) {
      debugPrint("GoogleDrive: Upload Error: $e");
      if (e is drive.DetailedApiRequestError) {
        throw "Google Drive Error: ${e.message} (Code: ${e.status})";
      }
      rethrow;
    }
  }

  Future<void> uploadJson(String jsonStr, String fileName, {List<String>? path}) async {
    if (_httpClient == null) await login();
    if (_httpClient == null) throw "Not authenticated with Google. Please log in again.";

    final api = drive.DriveApi(_httpClient!);
    String? folderId;

    if (path != null && path.isNotEmpty) {
      folderId = await _resolvePath(api, path);
    } else {
      folderId = await _getOrCreateFolder(api, "xyz.maya");
    }

    if (folderId != null) {
      await runAutoArchive(api, folderId);
    }

    final file = drive.File()
      ..name = fileName
      ..mimeType = 'application/json';
    
    if (folderId != null) file.parents = [folderId];

    final bytes = utf8.encode(jsonStr);
    final stream = Stream.fromIterable([bytes]);

    try {
      await api.files.create(file, uploadMedia: drive.Media(stream, bytes.length));
    } catch (e) {
      debugPrint("GoogleDrive: Upload Error: $e");
      if (e is drive.DetailedApiRequestError) {
        throw "Google Drive Error: ${e.message} (Code: ${e.status})";
      }
      rethrow;
    }
  }

  Future<void> manualBackup(String dbName, List<dynamic> data, {String? schemaName}) async {
    String jsonStr;
    try {
      final sanitizedData = _sanitizeForJson(data);
      jsonStr = jsonEncode(sanitizedData);
    } catch (e) {
      throw "Failed to prepare data for backup: $e";
    }
    
    final fileName = '${dbName}_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final path = schemaName != null ? ['xyz.maya', 'anydb', schemaName, 'Database'] : ['xyz.maya'];
    await uploadJson(jsonStr, fileName, path: path);
  }

  dynamic _sanitizeForJson(dynamic data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), _sanitizeForJson(v)));
    } else if (data is List) {
      return data.map((e) => _sanitizeForJson(e)).toList();
    }
    return data;
  }
}

final googleDriveServiceProvider = Provider((ref) => GoogleDriveService());

class GoogleLoginNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool val) => state = val;
}

final googleLoginProvider = NotifierProvider<GoogleLoginNotifier, bool>(GoogleLoginNotifier.new);
