import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/drop.dart';
import '../services/file_saver.dart';
import '../util/codes.dart';
import 'errors.dart';
import 'services_scope.dart';
import 'public_receive_screen.dart';
import 'theme.dart';
import 'widgets/drop_contents.dart';

/// Open a drop by code (or pasted link) and download its contents.
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key, this.initialCode});

  /// Code taken from the launch URL (`?code=ABC234`), opened automatically.
  final String? initialCode;

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final _input = TextEditingController();
  bool _loading = false;
  String? _error;
  Drop? _drop;
  bool _justBurned = false;

  /// Per-file download progress (0..1), keyed by storage path.
  final _progress = <String, double>{};
  final _saved = <String>{};

  @override
  void initState() {
    super.initState();
    final code = widget.initialCode;
    if (code != null) {
      _input.text = DropCodes.format(code);
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _pasteAndOpen() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text ?? '';
    if (value.isEmpty) return;
    _input.text = value.trim();
    await _open();
  }

  Future<void> _open() async {
    final publicToken = DropCodes.parsePublicToken(_input.text);
    if (publicToken != null) {
      setState(() => _error = null);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PublicReceiveScreen(token: publicToken),
      ));
      return;
    }
    final code = DropCodes.parse(_input.text);
    if (code == null) {
      setState(() => _error = 'Enter a 6-character code like ABC-234, or paste a Burner link.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _drop = null;
      _justBurned = false;
      _progress.clear();
      _saved.clear();
    });
    final drops = ServicesScope.of(context).drops;
    try {
      final drop = await drops.find(code);
      if (drop == null) {
        setState(() => _error = 'No drop found for ${DropCodes.format(code)}. '
            'It may have expired or already been burned.');
        return;
      }
      setState(() => _drop = drop);
      try {
        await drops.markReceived(drop);
        if (mounted && drop.burnAfterRead) setState(() => _justBurned = true);
      } catch (e) {
        if (mounted && drop.burnAfterRead) {
          showMessage(context, 'Could not burn this drop: ${describeError(e)}',
              error: true);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(DropFile file) async {
    final drops = ServicesScope.of(context).drops;
    setState(() => _progress[file.path] = 0);
    try {
      final bytes = await drops.download(file, onProgress: (got, total) {
        if (mounted && total > 0) setState(() => _progress[file.path] = got / total);
      });
      final where = await saveDownloadedFile(file.name, bytes, mimeType: file.contentType);
      if (!mounted) return;
      if (where != null) {
        setState(() => _saved.add(file.path));
        showMessage(context, where);
      }
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _progress.remove(file.path));
    }
  }

  Future<void> _downloadAll() async {
    for (final f in _drop!.files) {
      if (!_saved.contains(f.path)) await _download(f);
      if (!mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter a code', style: text.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _input,
                enabled: !_loading,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _open(),
                style: BurnerTheme.codeStyle(context, size: 24),
                decoration: InputDecoration(
                  hintText: 'ABC-234',
                  errorText: _error,
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
                    tooltip: 'Paste and open',
                    icon: const Icon(Icons.content_paste_go),
                    onPressed: _loading ? null : _pasteAndOpen,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _open,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: const Text('Open drop'),
              ),
              if (_drop != null) ...[
                const SizedBox(height: 24),
                DropContentsView(
                  drop: _drop!,
                  justBurned: _justBurned,
                  progress: _progress,
                  saved: _saved,
                  onDownload: _download,
                  onDownloadAll: _downloadAll,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
