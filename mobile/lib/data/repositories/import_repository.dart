import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/import_models.dart';
import '../models/page_result.dart';

abstract class ImportRepository {
  Future<PageResult<ImportBatch>> listImports({int limit = 50, int offset = 0});
  Future<ImportBatch> getImport(String id);

  /// Uploads a sales CSV. The server always records a batch; check its status.
  Future<ImportBatch> uploadSalesCsv({
    required String filename,
    required Uint8List bytes,
  });

  /// CSV header plus an example row built from the org's own catalogue.
  Future<String> downloadTemplate();
}

class ApiImportRepository implements ImportRepository {
  ApiImportRepository(this._api);

  final ApiClient _api;

  @override
  Future<PageResult<ImportBatch>> listImports({int limit = 50, int offset = 0}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/imports',
      query: {'limit': limit, 'offset': offset},
    );
    return PageResult.fromJson(json, ImportBatch.fromJson);
  }

  @override
  Future<ImportBatch> getImport(String id) async =>
      ImportBatch.fromJson(await _api.get<Map<String, dynamic>>('/imports/$id'));

  @override
  Future<ImportBatch> uploadSalesCsv({
    required String filename,
    required Uint8List bytes,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType('text', 'csv'),
      ),
    });
    final json = await _api.post<Map<String, dynamic>>(
      '/imports',
      data: form,
      options: Options(
        contentType: Headers.multipartFormDataContentType,
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    return ImportBatch.fromJson(json);
  }

  @override
  Future<String> downloadTemplate() => _api.get<String>(
        '/imports/template',
        options: Options(responseType: ResponseType.plain),
      );
}
