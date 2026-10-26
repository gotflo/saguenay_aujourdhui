import 'package:flutter/material.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../../theme/colors.dart';
import '../../theme/kind_style.dart';
import '../../widgets/pressable.dart';
import '../../widgets/glass.dart';

class InfoTile extends StatelessWidget {
  const InfoTile({super.key, required this.tile, this.onTap});

  final Tile tile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final color = tile.kind.color(c);

    return Pressable(
      onTap: onTap,
      semanticLabel: '${tile.label} : ${tile.value}, ${tile.detail}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 132),
        child: Glass(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(tile.kind.icon, size: 19, color: color),
              ),
              const SizedBox(height: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tile.label,
                    style: text.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tile.value,
                    style: text.titleMedium?.copyWith(color: tile.quiet ? c.ink2 : c.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tile.detail,
                    style: text.bodySmall?.copyWith(color: c.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
