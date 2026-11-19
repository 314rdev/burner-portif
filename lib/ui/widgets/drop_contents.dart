import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/drop.dart';
import '../../util/codes.dart';
import '../../util/format.dart';
import '../theme.dart';

/// Shows a drop's text and files with download buttons. Used by the signed-in
/// Receive page and by the public-link screen.
class DropContentsView extends StatelessWidget {
  const DropContentsView({
    super.key,
    required this.drop,
    required this.justBurned,
    required this.progress,
    required this.saved,
    required this.onDownload,
    required this.onDownloadAll,
    this.burnedMessage =
        'Nobody else can open it. Save what you need before leaving this page.',
    this.showCode = true,
  });

  final Drop drop;
  final bool justBurned;
  final Map<String, double> progress;
  final Set<String> saved;
  final ValueChanged<DropFile> onDownload;
  final VoidCallback onDownloadAll;
  final String burnedMessage;

  /// Public drops have a secret token instead of a code; don't show it.
  final bool showCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (showCode)
              Text(DropCodes.format(drop.code),
                  style: BurnerTheme.codeStyle(context, size: 20))
            else
              Text('Shared with you', style: text.titleMedium),
            const Spacer(),
            Text('expires in ${formatRemaining(drop.expiresAt)}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        if (justBurned) ...[
          const SizedBox(height: 12),
          Card(
            color: scheme.errorContainer,
            child: ListTile(
              leading: Icon(Icons.local_fire_department, color: scheme.onErrorContainer),
              title: Text('This drop is now burned',
                  style: TextStyle(color: scheme.onErrorContainer)),
              subtitle: Text(
                burnedMessage,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ),
        ],
        if (drop.hasText) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('Text', style: text.labelLarge),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: drop.text));
                          if (context.mounted) showMessage(context, 'Text copied');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ],
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: SelectableText(drop.text, style: text.bodyLarge),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (drop.hasFiles) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text('${drop.files.length} file(s)'),
                  subtitle: Text(formatBytes(drop.totalBytes)),
                  trailing: drop.files.length > 1
                      ? FilledButton.tonal(
                          onPressed: progress.isEmpty ? onDownloadAll : null,
                          child: const Text('Download all'),
                        )
                      : null,
                ),
                const Divider(height: 1),
                for (final f in drop.files)
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: progress.containsKey(f.path)
                        ? LinearProgressIndicator(
                            value: progress[f.path]! > 0 ? progress[f.path] : null)
                        : Text(formatBytes(f.size)),
                    trailing: saved.contains(f.path)
                        ? Icon(Icons.check_circle, color: scheme.primary)
                        : IconButton(
                            tooltip: 'Download',
                            icon: const Icon(Icons.download),
                            onPressed:
                                progress.containsKey(f.path) ? null : () => onDownload(f),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
