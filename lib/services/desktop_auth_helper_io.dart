import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';

Future<http.Client?> getLinuxClient(
  String clientId,
  String clientSecret,
  List<String> scopes,
) async {
  final id = ClientId(clientId, clientSecret);
  try {
    final client = await clientViaUserConsent(id, scopes, (url) async {
      final uri = Uri.parse(url);
      final modifiedUrl = uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              'access_type': 'offline',
              'prompt': 'consent',
            },
          )
          .toString();

      if (await canLaunchUrl(Uri.parse(modifiedUrl))) {
        await launchUrl(
          Uri.parse(modifiedUrl),
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw "Could not launch $modifiedUrl";
      }
    });
    return client;
  } catch (e) {
    return null;
  }
}
