import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../../state/launch.dart';
import '../../state/live_sources.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/pressable.dart';
import '../demo/moments_sheet.dart';
import '../details/detail_sheet.dart';
import '../places/place_picker.dart';
import '../assistant/assistant_screen.dart';
import '../settings/settings_screen.dart';
import '../sources/sources_sheet.dart';
import 'hero_card.dart';
import 'info_tile.dart';
import 'week_card.dart';
import '../../widgets/glass.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  @override
  void initState() {
    super.initState();
    // Arrivé par une notification, le widget ou un raccourci : la bonne fiche
    // s'ouvre par-dessus, une fois l'écran dessiné.
    ref.listenManual(launchTargetProvider, (_, kind) {
      if (kind == null) return;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(launchTargetProvider.notifier).consumed();
          showDetailSheet(context, kind);
        })
        // Rien d'autre ne redessine l'écran à ce moment : on demande l'image suivante.
        ..scheduleFrame();
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final place = ref.watch(placeProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowProvider);
    final week = ref.watch(weekProvider);
    if (place == null || today == null) return const Scaffold();

    final columns = MediaQuery.sizeOf(context).width >= 720 ? 3 : 2;
    final tiles = today.tiles;
    final rows = (tiles.length / columns).ceil();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: RefreshIndicator(
              onRefresh: () => refreshLiveSources(ref.read, force: true),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    sliver: SliverToBoxAdapter(child: _TopBar(place: place)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
                    sliver: SliverToBoxAdapter(child: _Greeting(now: now)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: HeroCard(
                        signal: today.hero,
                        onTap: today.hero == null
                            ? null
                            : () => showDetailSheet(context, today.hero!.kind),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 10),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Aussi aujourd’hui',
                        style: text.labelLarge?.copyWith(color: c.ink3),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.separated(
                      itemCount: rows,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, row) {
                        final start = row * columns;
                        final end = math.min(start + columns, tiles.length);
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = start; i < start + columns; i++) ...[
                                if (i > start) const SizedBox(width: 12),
                                Expanded(
                                  child: i < end
                                      ? FadeIn(
                                          key: ValueKey('${tiles[i].kind}-${tiles[i].value}'),
                                          index: i,
                                          child: InfoTile(
                                            tile: tiles[i],
                                            onTap: () => showDetailSheet(context, tiles[i].kind),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (week != null) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 10),
                      sliver: SliverToBoxAdapter(
                        child: Text('Ta semaine', style: text.labelLarge?.copyWith(color: c.ink3)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: WeekCard(
                          week: week,
                          now: now,
                          onTap: (kind) => showDetailSheet(context, kind),
                        ),
                      ),
                    ),
                  ],
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(28, 26, 28, 28 + bottom),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          TextButton(
                            onPressed: () => showSourcesSheet(context),
                            child: Text(
                              'D’où viennent ces infos ?',
                              style: text.labelLarge?.copyWith(color: c.ink2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Projet indépendant, non affilié à la Ville de Saguenay ni à la STS.',
                            textAlign: TextAlign.center,
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Pressable(
            onTap: () => showPlacePicker(context),
            semanticLabel: 'Adresse : ${place.label}. Changer d’adresse',
            child: Glass(
              radius: 99,
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place_rounded, size: 17, color: c.ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      place.label,
                      style: text.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more_rounded, size: 20, color: c.ink3),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Pressable(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const AssistantScreen())),
          semanticLabel: 'Demande à l’app',
          child: Glass(
            circle: true,
            child: SizedBox.square(
              dimension: 40,
              child: Icon(Icons.chat_bubble_outline_rounded, size: 19, color: c.ink),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Pressable(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          semanticLabel: 'Réglages',
          child: Glass(
            circle: true,
            child: SizedBox.square(
              dimension: 40,
              child: Icon(Icons.tune_rounded, size: 20, color: c.ink),
            ),
          ),
        ),
      ],
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final frozen = ref.watch(demoTimeProvider) != null;
    // Le réseau manque : on le dit doucement, sans alarmer. Tout ce qui se
    // calcule sur le téléphone reste juste.
    final offline =
        !frozen &&
        [
          ref.watch(weatherProvider).value,
          ref.watch(emergenciesProvider).value,
        ].any((s) => s?.origin == SourceOrigin.cached);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting(now), style: text.displaySmall),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                frozen
                    ? '${capitalize(longDate(now))}, ${clockTimeOf(now)}'
                    : capitalize(longDate(now)),
                style: text.bodyMedium?.copyWith(color: c.ink3),
              ),
            ),
            if (offline) ...[
              const SizedBox(width: 10),
              Pressable(
                onTap: () => showSourcesSheet(context),
                semanticLabel: 'Hors ligne. Voir les sources',
                child: Glass(
                  radius: 99,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 13, color: c.ink2),
                      const SizedBox(width: 5),
                      Text('Hors ligne', style: text.labelSmall?.copyWith(color: c.ink2)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 10),
            Pressable(
              onTap: () => showMomentsSheet(context),
              semanticLabel: 'Mode démo. Rejouer un moment',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'Démo',
                  style: text.labelSmall?.copyWith(color: c.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
