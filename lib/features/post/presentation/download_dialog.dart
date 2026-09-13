import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_exception.dart';
import '../application/post_controller.dart';
import '../data/attachment_types.dart';
import '../data/post_models.dart';

/// Download a file with a progress dialog, then open it.
///
/// Ports the old web app's `DownloadProgressModal`: filename, a real progress
/// bar with bytes received, Cancel, and an error state with Retry — because a
/// 40 MB slide deck on campus Wi-Fi otherwise looks like a frozen app.
Future<void> downloadAndOpen(BuildContext context, AssetInfo asset) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DownloadDialog(asset: asset),
  );
}

enum _Phase { preparing, downloading, failed }

class _DownloadDialog extends ConsumerStatefulWidget {
  const _DownloadDialog({required this.asset});

  final AssetInfo asset;

  @override
  ConsumerState<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends ConsumerState<_DownloadDialog> {
  final _cancelToken = CancelToken();
  _Phase _phase = _Phase.preparing;
  int _received = 0;
  int? _total;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel('closed');
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.preparing;
      _error = null;
      _received = 0;
      _total = widget.asset.sizeBytes;
    });

    final repository = ref.read(postRepositoryProvider);
    final navigator = Navigator.of(context);

    try {
      // A fresh link per attempt: a retry after fifteen minutes would
      // otherwise reuse an expired signature.
      final link = await repository.downloadLink(widget.asset.id);

      // Per-asset folder, so two different files both named "slides.pdf"
      // cannot overwrite one another.
      final base = await getApplicationDocumentsDirectory();
      final folder = Directory('${base.path}/downloads/${widget.asset.id}');
      await folder.create(recursive: true);
      final path = '${folder.path}/${safeFilename(link.filename)}';

      if (!mounted) return;
      setState(() => _phase = _Phase.downloading);

      await repository.downloadTo(
        link,
        savePath: path,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total > 0) _total = total;
          });
        },
      );

      if (!mounted) return;
      navigator.pop();

      final opened = await OpenFilex.open(path, type: link.contentType);
      if (opened.type != ResultType.done && navigator.mounted) {
        ScaffoldMessenger.of(navigator.context).showSnackBar(
          SnackBar(
            content: Text(
              opened.type == ResultType.noAppToOpen
                  ? 'Downloaded, but no app on this phone opens ${link.filename}'
                  : 'Downloaded to ${folder.path}',
            ),
          ),
        );
      }
    } on DioException catch (error) {
      // Cancelled by the person; the dialog is already closing.
      if (CancelToken.isCancel(error)) return;
      _fail('Download failed. Please try again.');
    } on ApiException catch (error) {
      _fail(error.message);
    } on FileSystemException catch (error) {
      _fail('Could not save the file: ${error.message}');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;
    final fraction =
        total != null && total > 0 ? (_received / total).clamp(0.0, 1.0) : null;

    return AlertDialog(
      title: Text(
        widget.asset.filename,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_phase == _Phase.failed) ...[
            Text(
              _error ?? 'Download failed',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ] else ...[
            LinearProgressIndicator(
              value: _phase == _Phase.preparing ? null : fraction,
            ),
            const SizedBox(height: 10),
            Text(
              switch (_phase) {
                _Phase.preparing => 'Preparing…',
                _ when fraction != null => '${(fraction * 100).round()}% · '
                    '${formatBytes(_received)} of ${formatBytes(total)}',
                _ => formatBytes(_received),
              },
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelToken.cancel('cancelled');
            Navigator.of(context).pop();
          },
          child: Text(_phase == _Phase.failed ? 'Close' : 'Cancel'),
        ),
        if (_phase == _Phase.failed)
          FilledButton(onPressed: _start, child: const Text('Retry')),
      ],
    );
  }
}
