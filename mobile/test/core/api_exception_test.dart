import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartstock/core/network/api_exception.dart';

import '../helpers/fixtures.dart';

void main() {
  final request = RequestOptions(path: '/x');

  DioException bad(int status, Object? body) => DioException.badResponse(
        statusCode: status,
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: status, data: body),
      );

  test('maps the error envelope with field details', () {
    final e = ApiException.fromDio(bad(
      422,
      errorJson('validation_error', 'The request payload failed validation.', [
        {'field': 'body.email', 'message': 'value is not a valid email address', 'type': 'value_error'},
      ]),
    ));
    expect(e.kind, ApiErrorKind.validation);
    expect(e.code, 'validation_error');
    expect(e.requestId, 'req-123');
    expect(e.fieldErrors, {'email': 'value is not a valid email address'});
    expect(e.displayMessage, 'value is not a valid email address');
  });

  test('uses the server message for insufficient stock', () {
    final e = ApiException.fromDio(
        bad(422, errorJson('unprocessable', 'Insufficient stock: on hand 2, requested 5.')));
    expect(e.kind, ApiErrorKind.validation);
    expect(e.displayMessage, 'Insufficient stock: on hand 2, requested 5.');
  });

  test('maps status codes to kinds', () {
    expect(ApiException.fromDio(bad(401, null)).kind, ApiErrorKind.unauthenticated);
    expect(ApiException.fromDio(bad(403, null)).kind, ApiErrorKind.forbidden);
    expect(ApiException.fromDio(bad(404, null)).kind, ApiErrorKind.notFound);
    expect(ApiException.fromDio(bad(409, null)).kind, ApiErrorKind.conflict);
    expect(ApiException.fromDio(bad(500, 'oops')).kind, ApiErrorKind.server);
  });

  test('connection errors and timeouts count as offline', () {
    final offline = ApiException.fromDio(
        DioException.connectionError(requestOptions: request, reason: 'x'));
    expect(offline.kind, ApiErrorKind.offline);
    expect(offline.isOffline, isTrue);

    final timeout = ApiException.fromDio(DioException.connectionTimeout(
      requestOptions: request,
      timeout: const Duration(seconds: 1),
    ));
    expect(timeout.kind, ApiErrorKind.timeout);
    expect(timeout.isOffline, isTrue);
  });
}
