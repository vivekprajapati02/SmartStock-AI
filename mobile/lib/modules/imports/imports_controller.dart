import 'package:get/get.dart';

import '../../core/files/csv_file_picker.dart';
import '../../core/network/api_exception.dart';
import '../../core/paging/paged_controller.dart';
import '../../data/models/fetched.dart';
import '../../data/models/import_models.dart';
import '../../data/models/page_result.dart';
import '../../data/repositories/import_repository.dart';
import '../dashboard/dashboard_controller.dart';

/// Import history plus the upload action.
class ImportsController extends PagedController<ImportBatch> {
  ImportsController(this._repo, this._picker);

  final ImportRepository _repo;
  final CsvFilePicker _picker;

  final RxBool uploading = false.obs;
  final RxnString uploadError = RxnString();

  /// Result of the most recent upload in this session (with its error report).
  final Rxn<ImportBatch> lastResult = Rxn<ImportBatch>();

  @override
  Future<Fetched<PageResult<ImportBatch>>> fetchPage(int offset, int limit) async =>
      Fetched(await _repo.listImports(offset: offset, limit: limit));

  /// Lets the user pick a CSV and uploads it. Returns the recorded batch, or
  /// null when cancelled or the request itself failed ([uploadError] is set).
  Future<ImportBatch?> pickAndUpload() async {
    if (uploading.value) return null;
    uploadError.value = null;
    final PickedCsv? file;
    try {
      file = await _picker.pick();
    } catch (e) {
      uploadError.value = 'Could not open the file: $e';
      return null;
    }
    if (file == null) return null;
    return upload(file);
  }

  Future<ImportBatch?> upload(PickedCsv file) async {
    uploading.value = true;
    uploadError.value = null;
    try {
      final batch = await _repo.uploadSalesCsv(filename: file.name, bytes: file.bytes);
      lastResult.value = batch;
      await reload();
      // Imported sales feed the dashboard demand trend.
      if (batch.validRows > 0 && Get.isRegistered<DashboardController>()) {
        Get.find<DashboardController>().load();
      }
      return batch;
    } on ApiException catch (e) {
      uploadError.value = e.displayMessage;
      return null;
    } finally {
      uploading.value = false;
    }
  }

  Future<String?> template() async {
    try {
      return await _repo.downloadTemplate();
    } on ApiException catch (e) {
      uploadError.value = e.displayMessage;
      return null;
    }
  }
}

class ImportDetailController extends GetxController {
  ImportDetailController(this._repo, this.batchId);

  final ImportRepository _repo;
  final String batchId;

  final Rxn<ImportBatch> batch = Rxn<ImportBatch>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxBool offline = false.obs;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    offline.value = false;
    try {
      batch.value = await _repo.getImport(batchId);
    } on ApiException catch (e) {
      error.value = e.displayMessage;
      offline.value = e.isOffline;
    } finally {
      loading.value = false;
    }
  }
}
