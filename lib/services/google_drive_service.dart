import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_check.dart';
import '../core/logger.dart';
import 'web_history_helper.dart' as web_helper;
import 'desktop_auth_helper.dart' as desktop_auth;
import 'io_helper.dart' as io;

/// A unified user model to bridge official GoogleSignInAccount and manual OAuth flows
class GoogleUser {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  GoogleUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  factory GoogleUser.fromOfficial(GoogleSignInAccount official) {
    return GoogleUser(
      id: official.id,
      email: official.email,
      displayName: official.displayName,
      photoUrl: official.photoUrl,
    );
  }
}

class GoogleDriveService {
  GoogleUser? _currentUser;
  http.Client? _httpClient;

  static Completer<void>? _initCompleter;

  // OAuth Constants for Linux/Manual Flow
  static String get _clientId {
    if (isLinux() || isWindows() || isMacOS()) {
      return "59875824101-q3f8p7c55kl4loc9mq25108k775lrh2b.apps.googleusercontent.com";
    }
    return "59875824101-8i46efacu12v4g9vvseu7k59711qe0u9.apps.googleusercontent.com";
  }
  // Note: For Desktop App client types, a secret is mandatory.
  // This is now securely provided at compile-time via --dart-define-from-file=secrets.json
  static const String _clientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
    defaultValue: '',
  );

  GoogleUser? get currentUser => _currentUser;

  Future<void> init() async {
    if (_initCompleter != null && !_initCompleter!.isCompleted)
      return _initCompleter!.future;
    if (_initCompleter != null && _initCompleter!.isCompleted) return;

    _initCompleter = Completer<void>();
    try {
      await GoogleSignIn.instance.initialize(clientId: _clientId);
      logger.log(
        "GoogleDriveService: Initializing with clientId: ${isAndroid() ? 'FROM_SERVICES_JSON' : _clientId}",
      );

      if (isLinux()) {
        await _restoreLinuxSession();
      }

      _initCompleter!.complete();
    } catch (e) {
      logger.log("GoogleDriveService: Init error: $e");
      _initCompleter!.complete(); // Complete anyway to unblock UI
    }
    return _initCompleter!.future;
  }

  /// Attempts to restore a previous session silently without showing a UI modal.
  Future<GoogleUser?> restoreSession() async {
    try {
      await init();

      if (kIsWeb) {
        // If we have an access token in the URL hash, handle it immediately!
        final fragment = Uri.base.fragment;
        if (fragment.contains('access_token=')) {
          logger.log(
            "GoogleDriveService: Found access_token in URL fragment on startup.",
          );
          final user = await _handleWebCallbackFragment(fragment);
          web_helper.clearUrlFragment();
          if (user != null) {
            return user;
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final wasLoggedIn = prefs.getBool('was_logged_in') ?? false;

      if (!wasLoggedIn) {
        logger.log(
          "GoogleDriveService: Skipping session restoration (user not previously logged in).",
        );
        return null;
      }

      if (isLinux()) return _currentUser;

      if (kIsWeb) {
        return await _restoreWebSession();
      }

      logger.log(
        "GoogleDriveService: Attempting silent session restoration...",
      );
      final official = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (official != null) {
        logger.log(
          "GoogleDriveService: Session restored for ${official.email}",
        );
        _currentUser = GoogleUser.fromOfficial(official);

        final List<String> scopes = [
          drive.DriveApi.driveFileScope,
          'email',
          'profile',
        ];
        final authz = await official.authorizationClient.authorizationForScopes(
          scopes,
        );
        if (authz != null) {
          _httpClient = authz.authClient(scopes: scopes);
        }
      }
      return _currentUser;
    } catch (e) {
      logger.log("GoogleDriveService: Session restoration skip: $e");
      return null;
    }
  }

  Future<void> _restoreLinuxSession() async {
    final prefs = await SharedPreferences.getInstance();
    final credsJson = prefs.getString('google_drive_creds');
    if (credsJson != null) {
      try {
        final creds = AccessCredentials.fromJson(jsonDecode(credsJson));
        final id = ClientId(_clientId, _clientSecret);

        if (creds.refreshToken != null) {
          _httpClient = autoRefreshingClient(id, creds, http.Client());
        } else {
          _httpClient = authenticatedClient(http.Client(), creds);
        }

        // Fetch user info to populate _currentUser
        final response = await _httpClient!.get(
          Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          _currentUser = GoogleUser(
            id: data['id'],
            email: data['email'],
            displayName: data['name'],
            photoUrl: data['picture'],
          );
        }
      } catch (e) {
        debugPrint("GoogleDriveService: Linux session restoration failed: $e");
      }
    }
  }

  Completer<GoogleUser?>? _webLoginCompleter;

  Future<GoogleUser?> _loginWebImplicit() async {
    logger.log("GoogleDriveService: Starting Web Implicit OAuth Flow...");
    _webLoginCompleter = Completer<GoogleUser?>();

    // Register listener for the redirect popup callback
    web_helper.registerWebMessageListener((fragment) async {
      try {
        final user = await _handleWebCallbackFragment(fragment);
        if (_webLoginCompleter != null && !_webLoginCompleter!.isCompleted) {
          _webLoginCompleter!.complete(user);
        }
      } catch (e) {
        logger.log("GoogleDriveService: Web OAuth callback error: $e");
        if (_webLoginCompleter != null && !_webLoginCompleter!.isCompleted) {
          _webLoginCompleter!.complete(null);
        }
      }
    });

    final scopes = [drive.DriveApi.driveFileScope, 'email', 'profile'];
    final redirectUri = "${Uri.base.origin}/";
    final authUrl =
        "https://accounts.google.com/o/oauth2/v2/auth"
        "?client_id=$_clientId"
        "&redirect_uri=${Uri.encodeComponent(redirectUri)}"
        "&response_type=token"
        "&scope=${Uri.encodeComponent(scopes.join(' '))}";

    logger.log("GoogleDriveService: Launching OAuth popup centered: $authUrl");

    // Centered popup to avoid popup blockers and keep users in app
    web_helper.openPopup(authUrl, "Google Login", 500, 650);

    return _webLoginCompleter!.future;
  }

  Future<GoogleUser?> login() async {
    try {
      await init();
      final List<String> scopes = [
        drive.DriveApi.driveFileScope,
        'email',
        'profile',
      ];

      if (kIsWeb) {
        return await _loginWebImplicit();
      }

      if (isLinux()) {
        final user = await _loginLinux(scopes);
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('was_logged_in', true);
        }
        return user;
      }
      logger.log("GoogleDriveService: Starting official sign-in flow...");
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        logger.log(
          "GoogleDriveService: authenticate() not supported on this platform. Use renderButton in UI.",
        );
        return null;
      }
      final official = await GoogleSignIn.instance.authenticate();
      _currentUser = GoogleUser.fromOfficial(official);

      logger.log(
        "GoogleDriveService: Authenticated as ${official.email}. Obtaining Auth Client...",
      );
      final authClientManager = official.authorizationClient;
      final authz = await authClientManager.authorizationForScopes(scopes);
      final finalAuthz =
          authz ?? await authClientManager.authorizeScopes(scopes);
      _httpClient = finalAuthz.authClient(scopes: scopes);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('was_logged_in', true);

      logger.log("GoogleDriveService: Authorization successful.");
      return _currentUser;
    } catch (error) {
      if (error.toString().contains("code 16") ||
          error.toString().contains("Account reauth failed")) {
        logger.log(
          "GoogleDriveService: ERROR - ACCOUNT REAUTH FAILED (Code 16). This usually means the SHA-1/SHA-256 fingerprint in the Google Console does not match the app's signature.",
        );
      }
      logger.log('GoogleDriveService: Login Error: $error');
      return null;
    }
  }

  Future<GoogleUser?> _loginLinux(List<String> scopes) async {
    try {
      final client = await desktop_auth.getLinuxClient(
        _clientId,
        _clientSecret,
        scopes,
      );
      if (client == null) return null;

      _httpClient = client;
      final creds = (client as AuthClient).credentials;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('google_drive_creds', jsonEncode(creds.toJson()));

      // Fetch profile
      final response = await client.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentUser = GoogleUser(
          id: data['id'],
          email: data['email'],
          displayName: data['name'],
          photoUrl: data['picture'],
        );
      }
      return _currentUser;
    } catch (e) {
      debugPrint("GoogleDriveService: Linux login error: $e");
      return null;
    }
  }

  Future<GoogleUser?> _restoreWebSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('google_drive_web_token');
      final expiryStr = prefs.getString('google_drive_web_token_expiry');

      if (token != null && expiryStr != null) {
        final expiryTime = DateTime.parse(expiryStr).toUtc();
        if (expiryTime.isAfter(DateTime.now().toUtc())) {
          logger.log(
            "GoogleDriveService: Restoring web session from SharedPreferences.",
          );
          final accessToken = AccessToken('Bearer', token, expiryTime);
          final creds = AccessCredentials(accessToken, null, [
            drive.DriveApi.driveFileScope,
            'email',
            'profile',
          ]);
          _httpClient = authenticatedClient(http.Client(), creds);

          // Fetch user info
          final response = await _httpClient!.get(
            Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            _currentUser = GoogleUser(
              id: data['id'],
              email: data['email'],
              displayName: data['name'],
              photoUrl: data['picture'],
            );
            logger.log(
              "GoogleDriveService: Session successfully restored for ${_currentUser?.email}",
            );
            return _currentUser;
          }
        }
      }

      logger.log(
        "GoogleDriveService: Attempting silent session restoration via SDK...",
      );
      final official = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (official != null) {
        _currentUser = GoogleUser.fromOfficial(official);

        final List<String> scopes = [
          drive.DriveApi.driveFileScope,
          'email',
          'profile',
        ];
        final authz = await official.authorizationClient.authorizationForScopes(
          scopes,
        );
        if (authz != null) {
          _httpClient = authz.authClient(scopes: scopes);
        }
        logger.log(
          "GoogleDriveService: Session restored for ${_currentUser?.email}",
        );
      }
      return _currentUser;
    } catch (e) {
      logger.log("GoogleDriveService: Silent restoration error: $e");
      return null;
    }
  }

  Future<GoogleUser?> _handleWebCallbackFragment(String fragment) async {
    try {
      final params = _parseFragment(fragment);
      final token = params['access_token'];
      final expiresInStr = params['expires_in'];

      if (token == null) {
        logger.log("GoogleDriveService: No access_token in fragment.");
        return null;
      }

      final expiresIn = int.tryParse(expiresInStr ?? '3600') ?? 3600;
      final expiryTime = DateTime.now().toUtc().add(
        Duration(seconds: expiresIn),
      );

      // Save token & expiry
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('google_drive_web_token', token);
      await prefs.setString(
        'google_drive_web_token_expiry',
        expiryTime.toIso8601String(),
      );
      await prefs.setBool('was_logged_in', true);

      // Construct auth client
      final accessToken = AccessToken('Bearer', token, expiryTime);
      final creds = AccessCredentials(accessToken, null, [
        drive.DriveApi.driveFileScope,
        'email',
        'profile',
      ]);
      _httpClient = authenticatedClient(http.Client(), creds);

      // Fetch user profile
      final response = await _httpClient!.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentUser = GoogleUser(
          id: data['id'],
          email: data['email'],
          displayName: data['name'],
          photoUrl: data['picture'],
        );
        logger.log(
          "GoogleDriveService: Web user info fetched: ${_currentUser?.email}",
        );
      } else {
        logger.log(
          "GoogleDriveService: Failed to fetch user info: ${response.statusCode} - ${response.body}",
        );
      }
      return _currentUser;
    } catch (e) {
      logger.log("GoogleDriveService: Error handling web OAuth fragment: $e");
      return null;
    }
  }

  Map<String, String> _parseFragment(String fragment) {
    String clean = fragment;
    if (clean.startsWith('#')) clean = clean.substring(1);
    if (clean.startsWith('?')) clean = clean.substring(1);

    final Map<String, String> result = {};
    final pairs = clean.split('&');
    for (var pair in pairs) {
      final parts = pair.split('=');
      if (parts.length >= 2) {
        final key = Uri.decodeComponent(parts[0]);
        final value = Uri.decodeComponent(parts.sublist(1).join('='));
        result[key] = value;
      }
    }
    return result;
  }

  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('was_logged_in');

      if (kIsWeb) {
        await prefs.remove('google_drive_web_token');
        await prefs.remove('google_drive_web_token_expiry');
      } else if (!isLinux()) {
        await GoogleSignIn.instance.signOut();
        try {
          await GoogleSignIn.instance.disconnect();
        } catch (_) {}
      } else {
        await prefs.remove('google_drive_creds');
      }
    } catch (e) {
      debugPrint("GoogleDriveService: Logout error: $e");
    }
    _currentUser = null;
    _httpClient = null;
  }

  bool get isLoggedIn => _httpClient != null || _currentUser != null;

  Future<String?> _resolvePath(drive.DriveApi api, List<String> path) async {
    String? currentParentId;
    for (final folderName in path) {
      currentParentId = await _getOrCreateFolder(
        api,
        folderName,
        parentId: currentParentId,
      );
      if (currentParentId == null) return null;
    }
    return currentParentId;
  }

  Future<String?> _getOrCreateFolder(
    drive.DriveApi api,
    String folderName, {
    String? parentId,
  }) async {
    try {
      String query =
          "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      if (parentId != null) {
        query += " and '$parentId' in parents";
      }

      final found = await api.files.list(q: query, spaces: 'drive');

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
          archiveFolderId ??= await _getOrCreateFolder(
            api,
            'archive',
            parentId: folderId,
          );
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

  Future<void> uploadFile(
    String filePath,
    String fileName, {
    List<String>? path,
  }) async {
    if (_httpClient == null) await login();
    if (_httpClient == null)
      throw "Not authenticated with Google. Please log in again.";

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
      ..mimeType =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    if (folderId != null) file.parents = [folderId];

    final bytes = await io.readBytes(filePath);
    if (bytes == null) throw "File not found: $filePath";
    final fileStream = Stream<List<int>>.value(bytes);
    final length = bytes.length;

    try {
      await api.files.create(
        file,
        uploadMedia: drive.Media(fileStream, length),
      );
    } catch (e) {
      debugPrint("GoogleDrive: Upload Error: $e");
      if (e is drive.DetailedApiRequestError) {
        throw "Google Drive Error: ${e.message} (Code: ${e.status})";
      }
      rethrow;
    }
  }

  Future<void> uploadJson(
    String jsonStr,
    String fileName, {
    List<String>? path,
  }) async {
    if (_httpClient == null) await login();
    if (_httpClient == null)
      throw "Not authenticated with Google. Please log in again.";

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
      await api.files.create(
        file,
        uploadMedia: drive.Media(stream, bytes.length),
      );
    } catch (e) {
      debugPrint("GoogleDrive: Upload Error: $e");
      if (e is drive.DetailedApiRequestError) {
        throw "Google Drive Error: ${e.message} (Code: ${e.status})";
      }
      rethrow;
    }
  }

  Future<void> manualBackup(
    String dbName,
    List<dynamic> data, {
    String? schemaName,
  }) async {
    String jsonStr;
    try {
      final sanitizedData = _sanitizeForJson(data);
      jsonStr = jsonEncode(sanitizedData);
    } catch (e) {
      throw "Failed to prepare data for backup: $e";
    }

    final fileName = formatBackupFileName(dbName, DateTime.now());
    final List<String> path = schemaName != null
        ? ['xyz.maya', 'anydb', 'schema', schemaName, 'database', dbName]
        : ['xyz.maya'];
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

class GoogleUserNotifier extends Notifier<GoogleUser?> {
  @override
  GoogleUser? build() => null;
  void setUser(GoogleUser? user) => state = user;
}

final googleUserProvider = NotifierProvider<GoogleUserNotifier, GoogleUser?>(
  GoogleUserNotifier.new,
);

String formatBackupFileName(String dbName, DateTime dt) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  
  final dayName = weekdays[dt.weekday - 1];
  final monthName = months[dt.month - 1];
  final day = dt.day;
  final year = dt.year;
  
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final second = dt.second.toString().padLeft(2, '0');
  
  final offset = dt.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
  final offsetMinutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final tzString = 'GMT$sign$offsetHours$offsetMinutes';
  
  final formattedDate = '${dayName}_${monthName}_${day}_${year}_${hour}_${minute}_${second}_$tzString';
  return '${dbName}_$formattedDate.json'.replaceAll('+', '_');
}
