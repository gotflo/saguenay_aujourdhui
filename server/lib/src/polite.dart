import 'package:http/http.dart' as http;

/// Se présente aux sites qu'on lit, sans cookie ni jeton.
class PoliteClient extends http.BaseClient {
  PoliteClient(this._inner);

  static const agent = 'saguenay-aujourdhui-assistant/0.1';

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['User-Agent'] = agent;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
