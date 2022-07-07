import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class DownloadOptions {
  final File file;
  final bool deleteOnCancel;
  final bool deleteOnError;

  http.BaseClient? httpClient;
  void Function()? onDone;
  ProgressCallback? progressCallback;

  DownloadOptions({
    required this.file,
    this.deleteOnCancel = false,
    this.deleteOnError = true,
    this.httpClient,
    this.onDone,
    this.progressCallback,
  });
}

class DownloadController {
  StreamSubscription _inner;
  final DownloadOptions _options;
  final String _url;
  bool isCancelled = false;
  bool isDownloading = true;

  DownloadController._(
    StreamSubscription inner,
    DownloadOptions options,
    String url,
  ) : _inner = inner,
        _options = options,
        _url = url;

  Future<void> pause() async {
    _checkIfStillValid();
    if (isDownloading) {
      await _inner.cancel();
      isDownloading = false;
    }
  }

  Future<void> resume() async {
    _checkIfStillValid();
    if (isDownloading) {
      return;
    }
    _inner = await _download(_url, _options);
    isDownloading = true;
  }

  Future<void> cancel() async {
    _checkIfStillValid();
    await _inner.cancel();
    if (_options.deleteOnCancel) {
      await _options.file.delete();
    }
    isCancelled = true;
  }

  void _checkIfStillValid() {
    if (isCancelled) throw StateError('Already cancelled');
  }
}

/// Callback to listen the progress for receiving data.
///
/// [count] is the length of the bytes have been received.
/// [total] is the content length of the response/file body.
typedef ProgressCallback = void Function(int count, int total);

Future<DownloadController> download(
  String url,
  DownloadOptions options,
) async {
  try {
    final subscription = await _download(url, options);
    return DownloadController._(subscription, options, url);
  } catch (e) {
    rethrow;
  }
}

Future<StreamSubscription> _download(
  String url,
  DownloadOptions options,
) async {
  final client = options.httpClient ?? http.Client();
  try {
    var lastProgress = await options.file.exists() ? await options.file.length() : 0;
    final request = http.Request('GET', Uri.parse(url));
    request.headers['Range'] = 'bytes=$lastProgress-';
    final target = await options.file.create(recursive: false);
    final response = await client.send(request);
    final total = response.contentLength == null ? -1 : (lastProgress + response.contentLength!);
    final sink = await target.open(mode: FileMode.writeOnlyAppend);
    late StreamSubscription subscription;
    subscription = response.stream.listen(
      (data) async {
        subscription.pause();
        await sink.writeFrom(data);
        final currentProgress = lastProgress + data.length;
        lastProgress = currentProgress;
        options.progressCallback?.call(currentProgress, total);
        subscription.resume();
      },
      onDone: () async {
        options.onDone?.call();
        await sink.close();
        client.close();
      },
    );
    return subscription;
  } catch (e) {
    if (options.deleteOnError) {
      await options.file.delete();
    }
    rethrow;
  }
}
