import 'package:flutter/material.dart';

import '../models/drop.dart';
import '../util/codes.dart';
import '../util/format.dart';
import 'errors.dart';
import 'services_scope.dart';
import 'theme.dart';
import 'widgets/share_card.dart';

/// The user's own drops and usage counters.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  List<Drop>? _drops;
  UsageStats? _usage;
  String? _error;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_drops == null && !_loading) refresh();
  }

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final drops = ServicesScope.of(context).drops;
    try {
      final results = await Future.wait([drops.myDrops(), drops.usage()]);
      if (!mounted) return;
      setState(() {
        _drops = results[0] as List<Drop>;
        _usage = results[1] as UsageStats;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Drop drop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(drop.isPublic
            ? 'Delete this public link?'
            : 'Delete ${DropCodes.format(drop.code)}?'),
        content: const Text(
            'The code stops working and its files are deleted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ServicesScope.of(context).drops.delete(drop);
      if (!mounted) return;
      setState(() => _drops?.remove(drop));
      showMessage(context, 'Drop deleted');
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    }
  }

  Future<void> _cleanup() async {
    try {
      final removed = await ServicesScope.of(context).drops.cleanup();
      if (!mounted) return;
      showMessage(context,
          removed == 0 ? 'Nothing to clean up' : 'Removed $removed old drop(s)');
      await refresh();
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final drops = _drops;
    final inactive = drops?.where((d) => !d.isActive()).length ?? 0;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_usage != null) _UsageCard(usage: _usage!),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('My drops', style: text.titleMedium)),
                    if (inactive > 0)
                      TextButton.icon(
                        onPressed: _cleanup,
                        icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                        label: Text('Clean up $inactive'),
                      ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _loading ? null : refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loading && drops == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error))
                else if (drops == null || drops.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No drops yet. Create one from Send.')),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final (i, d) in drops.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _DropTile(
                            drop: d,
                            onShare: () => showShareDialog(context, d),
                            onDelete: () => _delete(d),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.usage});

  final UsageStats usage;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Sent', '${usage.dropsCreated}', Icons.upload),
      ('Uploaded', formatBytes(usage.bytesUploaded), Icons.cloud_upload_outlined),
      ('Received', '${usage.dropsReceived}', Icons.download),
      ('Downloaded', formatBytes(usage.bytesDownloaded), Icons.cloud_download_outlined),
    ];
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth < 420 ? 2 : 4;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (label, value, icon) in items)
                SizedBox(
                  width: width,
                  child: Row(
                    children: [
                      Icon(icon, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(value,
                                style: text.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(label,
                                style: text.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _DropTile extends StatelessWidget {
  const _DropTile({required this.drop, required this.onShare, required this.onDelete});

  final Drop drop;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = drop.burned
        ? 'burned'
        : drop.isExpired()
            ? 'expired'
            : 'expires in ${formatRemaining(drop.expiresAt)}';
    final contents = [
      if (drop.hasFiles) '${drop.files.length} file(s), ${formatBytes(drop.totalBytes)}',
      if (drop.hasText) 'text',
    ].join(' + ');

    return ListTile(
      onTap: drop.isActive() ? onShare : null,
      leading: Icon(
        drop.isActive()
            ? (drop.isPublic
                ? Icons.public
                : drop.hasFiles
                    ? Icons.folder_zip_outlined
                    : Icons.notes)
            : Icons.local_fire_department_outlined,
        color: drop.isActive() ? scheme.primary : scheme.outline,
      ),
      title: drop.isPublic
          ? Text('Public link',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: drop.isActive() ? null : scheme.outline))
          : Text(DropCodes.format(drop.code),
              style: BurnerTheme.codeStyle(context, size: 16).copyWith(
                  color: drop.isActive() ? null : scheme.outline)),
      subtitle: Text('$contents\n$status · opened ${drop.downloads}×'),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (drop.isActive())
            IconButton(
              tooltip: drop.isPublic ? 'Show link' : 'Show code',
              icon: const Icon(Icons.qr_code_2),
              onPressed: onShare,
            ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
