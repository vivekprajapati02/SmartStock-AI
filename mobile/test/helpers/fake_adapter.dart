import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.headers, this.body, this.query);

  final String method;
  final Map<String, dynamic> query;
  final String path;
  final Map<String, dynamic> headers;
  final Object? body;
}

typedef Responder = Future<(int, Object?)> Function(RequestOptions options);

/// Dio adapter that answers from a function and records every request.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.responder);

  Responder responder;
  final List<RecordedRequest> requests = [];

  /// When true, every request fails with a connection error.
  bool offline = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(RecordedRequest(
      options.method,
      options.path,
      Map.of(options.headers),
      options.data,
      Map.of(options.queryParameters),
    ));
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final (status, body) = await responder(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
