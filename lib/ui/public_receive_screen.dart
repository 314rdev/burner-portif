import 'package:flutter/material.dart';

import '../models/drop.dart';
import '../services/drop_service.dart';
import '../services/file_saver.dart';
import '../util/format.dart';
import 'errors.dart';
import 'services_scope.dart';
import 'splash_screen.dart';
import 'theme.dart';
import 'widgets/drop_contents.dart';

/// Opens a public-link drop (`?p=<token>`) without signing in.
///
/// The drop burns when the receiver taps "Open", not on page load, so link
/// previews or an accidental visit don't use up the single open. Files stay
/// downloadable for [DropService.publicDownloadWindow] after that.
class PublicReceiveScreen extends StatefulWidget {
  const PublicReceiveScreen({super.key, required this.token, this.onLeave});

  final String token;

  /// Called by "Open Burner" when shown as the app's start page. When null
  /// (pushed from the Receive page), the screen simply pops.
  final VoidCallback? onLeave;

  @override
  State<PublicReceiveScreen> createState() => _PublicReceiveScreenState();
}

class _PublicReceiveScreenState extends State<PublicReceiveScreen> {
  bool _loading = true;
  bool _opening = false;
  bool _opened = false;
  Drop? _drop;
  String? _error;
  final _progress = <String, double>{};
  final _saved = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _drop == null && _error == null) _lookup();
  }

  Future<void> _lookup() async {
    try {
      final drop = await ServicesScope.of(context).drops.findPublic(widget.token);
      if (!mounted) return;
      setState(() {
        _drop = drop;
        if (drop == null) {
          _error = 'This link has expired or was already opened.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      await ServicesScope.of(context).drops.openPublic(_drop!);
      if (mounted) setState(() => _opened = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _drop = null;
        _error = 'This link was just opened by someone else, or it expired.';
      });
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _download(DropFile file) async {
    final drops = ServicesScope.of(context).drops;
    setState(() => _progress[file.path] = 0);
    try {
      final bytes = await drops.downloadPublic(file, onProgress: (got, total) {
        if (mounted && total > 0) setState(() => _progress[file.path] = got / total);
      });
      final where =
          await saveDownloadedFile(file.name, bytes, mimeType: file.contentType);
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

  void _leave() {
    if (widget.onLeave != null) {
      widget.onLeave!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.onLeave == null,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BurnerFlame(size: 26),
            SizedBox(width: 8),
            Text('Burner', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            ContentWidth(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final drop = _drop;
    if (drop == null) {
      return _Message(
        icon: Icons.local_fire_department_outlined,
        title: 'Nothing here',
        body: _error ?? 'This link has expired or was already opened.',
        action: FilledButton.tonal(
          onPressed: _leave,
          child: const Text('Open Burner'),
        ),
      );
    }

    if (_opened) {
      final minutes = DropService.publicDownloadWindow.inMinutes;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropContentsView(
            drop: drop,
            justBurned: true,
            showCode: false,
            burnedMessage: 'The link no longer works. '
                '${drop.hasFiles ? 'Download the files within $minutes minutes. ' : ''}'
                'Save what you need before leaving this page.',
            progress: _progress,
            saved: _saved,
            onDownload: _download,
            onDownloadAll: _downloadAll,
          ),
          const SizedBox(height: 24),
          TextButton(onPressed: _leave, child: const Text('Open Burner')),
        ],
      );
    }

    final parts = [
      if (drop.hasFiles) '${drop.files.length} file(s) · ${formatBytes(drop.totalBytes)}',
      if (drop.hasText) 'a text note',
    ];
    return _Message(
      icon: Icons.mark_email_unread_outlined,
      title: 'Someone sent you a drop',
      body: '${parts.join(' and ')}.\n\n'
          'It can be opened only once. After you open it the link stops '
          'working, so open it on the device where you want to keep it.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _opening ? null : _open,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _opening
                ? const SizedBox.square(
                    dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.local_fire_department),
            label: const Text('Open'),
          ),
          const SizedBox(height: 8),
          Text(
            'Expires in ${formatRemaining(drop.expiresAt)}',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: text.titleLarge),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            action,
          ],
        ),
      ),
    );
  }
}
