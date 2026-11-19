import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/drop.dart';
import '../services/drop_service.dart';
import '../util/format.dart';
import 'errors.dart';
import 'services_scope.dart';
import 'theme.dart';
import 'widgets/share_card.dart';

/// Create a drop: drag files in (or pick them), add text, choose expiry.
class SendPage extends StatefulWidget {
  const SendPage({super.key, this.dropEnabled = true});

  /// Disable the drop target while another page is in front (desktop_drop
  /// keeps receiving events for hidden targets otherwise).
  final bool dropEnabled;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _PendingFile {
  _PendingFile(this.file, this.size);
  final XFile file;
  final int size;
}

class _SendPageState extends State<SendPage> {
  final _text = TextEditingController();
  final _files = <_PendingFile>[];
  Duration _ttl = DropLimits.defaultTtl;
  bool _burnAfterRead = false;
  bool _public = false;
  bool _dragging = false;
  bool _sending = false;
  double? _progress;
  Drop? _created;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && (_files.isNotEmpty || _text.text.trim().isNotEmpty);

  Future<void> _addFiles(Iterable<XFile> files) async {
    final added = <_PendingFile>[];
    for (final f in files) {
      // Directories show up as zero-length entries without a usable stream.
      final size = await f.length().catchError((_) => -1);
      if (size < 0) continue;
      added.add(_PendingFile(f, size));
    }
    if (!mounted) return;
    setState(() {
      _created = null;
      _files.addAll(added);
    });
    final skipped = files.length - added.length;
    if (skipped > 0) {
      showMessage(context, 'Skipped $skipped item(s) that are not files (folders are not supported yet).');
    }
  }

  Future<void> _pickFiles() async {
    try {
      final picked = await FilePicker.pickFiles(dialogTitle: 'Choose files to send');
      await _addFiles(picked.map((p) => p.xFile));
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Could not open the file picker: ${describeError(e)}',
            error: true);
      }
    }
  }

  void _onDragDone(DropDoneDetails details) {
    setState(() => _dragging = false);
    if (details.files.isNotEmpty) {
      _addFiles(details.files);
    } else if ((details.rawText ?? '').trim().isNotEmpty) {
      final current = _text.text;
      _text.text = current.isEmpty ? details.rawText! : '$current\n${details.rawText}';
      setState(() => _created = null);
    }
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _progress = _files.isEmpty ? null : 0;
    });
    try {
      final drop = await ServicesScope.of(context).drops.create(
            DropRequest(
              text: _text.text,
              files: _files.map((f) => f.file).toList(),
              ttl: _ttl,
              burnAfterRead: _burnAfterRead,
              isPublic: _public,
            ),
            onProgress: (sent, total) {
              if (mounted && total > 0) setState(() => _progress = sent / total);
            },
          );
      if (!mounted) return;
      setState(() {
        _created = drop;
        _files.clear();
        _text.clear();
      });
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isMobile = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final totalBytes = _files.fold(0, (s, f) => s + f.size);

    return DropTarget(
      enable: widget.dropEnabled && !_sending,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDragDone,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_created != null) ...[
                  ShareCard(
                    drop: _created!,
                    trailing: TextButton.icon(
                      onPressed: () => setState(() => _created = null),
                      icon: const Icon(Icons.add),
                      label: const Text('New drop'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _DropZone(
                  dragging: _dragging,
                  isMobile: isMobile,
                  onPick: _sending ? null : _pickFiles,
                ),
                if (_files.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        for (final f in _files)
                          ListTile(
                            leading: const Icon(Icons.insert_drive_file_outlined),
                            title: Text(f.file.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(formatBytes(f.size)),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close),
                              onPressed: _sending
                                  ? null
                                  : () => setState(() => _files.remove(f)),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Row(
                            children: [
                              Text(
                                '${_files.length} file(s) · ${formatBytes(totalBytes)}',
                                style: text.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _sending
                                    ? null
                                    : () => setState(_files.clear),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  enabled: !_sending,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: DropLimits.maxTextChars,
                  buildCounter: (context,
                          {required currentLength, required isFocused, maxLength}) =>
                      currentLength > 1000 ? Text('$currentLength / $maxLength') : null,
                  onChanged: (_) => setState(() => _created = null),
                  decoration: const InputDecoration(
                    labelText: 'Text (optional)',
                    hintText: 'Paste a note, link, snippet…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Expires after', style: text.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<Duration>(
                  showSelectedIcon: false,
                  segments: [
                    for (final d in DropLimits.ttlOptions)
                      ButtonSegment(value: d, label: Text(_shortTtl(d))),
                  ],
                  selected: {_ttl},
                  onSelectionChanged:
                      _sending ? null : (s) => setState(() => _ttl = s.first),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _public,
                  onChanged: _sending ? null : (v) => setState(() => _public = v),
                  secondary: const Icon(Icons.public),
                  title: const Text('Public link'),
                  subtitle: const Text(
                      'Anyone with the link can open it once, without signing in.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _public || _burnAfterRead,
                  onChanged: _sending || _public
                      ? null
                      : (v) => setState(() => _burnAfterRead = v),
                  secondary: const Icon(Icons.local_fire_department_outlined),
                  title: const Text('Burn after first open'),
                  subtitle: Text(_public
                      ? 'Public links always burn when opened.'
                      : 'Only the first device to open the code gets it.'),
                ),
                const SizedBox(height: 8),
                if (_sending) ...[
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(
                    _progress == null
                        ? 'Creating drop…'
                        : 'Uploading… ${(_progress! * 100).round()}%',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: _canSend ? _send : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.local_fire_department),
                  label: Text('Create drop · ${formatDuration(_ttl)}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortTtl(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.dragging,
    required this.isMobile,
    required this.onPick,
  });

  final bool dragging;
  final bool isMobile;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: isMobile ? 28 : 44),
      decoration: BoxDecoration(
        color: dragging ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dragging ? scheme.primary : scheme.outlineVariant,
          width: dragging ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        children: [
          Icon(
            dragging ? Icons.file_download : Icons.upload_file,
            size: 48,
            color: dragging ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            dragging
                ? 'Release to add'
                : isMobile
                    ? 'Pick files to send'
                    : 'Drag files here',
            style: text.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (!dragging) ...[
            const SizedBox(height: 4),
            Text(
              isMobile ? 'Up to 100 MB each' : 'or choose them · up to 100 MB each',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose files'),
            ),
          ],
        ],
      ),
    );
  }
}
