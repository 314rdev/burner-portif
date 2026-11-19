import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/drop.dart';
import '../../util/codes.dart';
import '../../util/format.dart';
import '../services_scope.dart';
import '../theme.dart';

/// Shows a drop's code, link and QR so another device can pick it up.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.drop, this.trailing});

  final Drop drop;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final link = ServicesScope.of(context).linkFor(drop.code);
    final qrData = link ?? drop.code;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your code', style: text.labelLarge),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SelectableText(
            DropCodes.format(drop.code),
            style: BurnerTheme.codeStyle(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            'Expires in ${formatRemaining(drop.expiresAt)}',
            if (drop.burnAfterRead) 'burns after first open',
          ].join(' · '),
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _copy(context, drop.code, 'Code copied'),
              icon: const Icon(Icons.copy),
              label: const Text('Copy code'),
            ),
            if (link != null)
              FilledButton.tonalIcon(
                onPressed: () => _copy(context, link, 'Link copied'),
                icon: const Icon(Icons.link),
                label: const Text('Copy link'),
              ),
            ?trailing,
          ],
        ),
      ],
    );

    final qr = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(data: qrData, size: 148, padding: EdgeInsets.zero),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 20), Center(child: qr)],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: details),
              const SizedBox(width: 20),
              qr,
            ],
          );
        }),
      ),
    );
  }

  static Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) showMessage(context, message);
  }
}

/// Opens a dialog with the [ShareCard] for [drop].
Future<void> showShareDialog(BuildContext context, Drop drop) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ShareCard(
          drop: drop,
          trailing: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ),
    ),
  );
}
