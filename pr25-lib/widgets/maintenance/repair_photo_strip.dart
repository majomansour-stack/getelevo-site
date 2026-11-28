import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../theme/theme.dart';

/// Small camera mark for a repair that has photos.
class RepairPhotoIndicator extends StatelessWidget {
  final int count;
  final Color color;

  const RepairPhotoIndicator({
    super.key,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.camera, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Thumbnails for paths stored on a repair. Each one is signed when shown.
class RepairPhotoStrip extends StatelessWidget {
  final List<String> paths;
  final String? groupId;

  const RepairPhotoStrip({super.key, required this.paths, this.groupId});

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).extension<ElevoColors>()!;
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return _SignedRepairPhoto(
            key: ValueKey('${groupId ?? 'repair'}|$index|${paths[index]}'),
            stored: paths[index],
            colors: colors,
            onTap: (url) {
              showDialog<void>(
                context: context,
                builder: (ctx) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SignedRepairPhoto extends StatefulWidget {
  final String stored;
  final ElevoColors colors;
  final void Function(String url) onTap;

  const _SignedRepairPhoto({
    super.key,
    required this.stored,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_SignedRepairPhoto> createState() => _SignedRepairPhotoState();
}

class _SignedRepairPhotoState extends State<_SignedRepairPhoto> {
  late final Future<String?> _url = _sign();

  Future<String?> _sign() async {
    final path = storageObjectPath(widget.stored, repairPhotoBucket);
    if (path == null) return null;
    try {
      return await Supabase.instance.client.storage
          .from(repairPhotoBucket)
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        final url = snapshot.data;
        final child = url == null
            ? Icon(LucideIcons.image, color: widget.colors.taupe)
            : Image.network(url, width: 72, height: 72, fit: BoxFit.cover);
        return GestureDetector(
          onTap: url == null ? null : () => widget.onTap(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: Container(
              width: 72,
              height: 72,
              color: widget.colors.midnight.withAlpha(20),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
