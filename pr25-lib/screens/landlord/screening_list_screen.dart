import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/screening_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/screening_provider.dart';
import '../../services/rentspree_links.dart';
import '../../theme/theme.dart';
import '../../widgets/screening/rentspree_how_it_works.dart';
import 'screening_form_screen.dart';
import 'screening_detail_screen.dart';

class ScreeningListScreen extends StatefulWidget {
  const ScreeningListScreen({super.key});

  @override
  State<ScreeningListScreen> createState() => _ScreeningListScreenState();
}

class _ScreeningListScreenState extends State<ScreeningListScreen> {
  final _searchCtrl = TextEditingController();
  ScreeningStatus? _filterStatus; // null = All
  String _query = '';

  bool _disclosureDismissed = true; // default true until loaded

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScreeningProvider>().load();
      _checkDisclosure();
    });
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.toLowerCase());
    });
  }

  Future<void> _checkDisclosure() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('users')
          .select('rentspree_disclosure_dismissed')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      final dismissed = row?['rentspree_disclosure_dismissed'] as bool? ?? false;
      setState(() => _disclosureDismissed = dismissed);
    } catch (_) {}
  }

  Future<void> _dismissDisclosure() async {
    setState(() => _disclosureDismissed = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client
          .from('users')
          .update({'rentspree_disclosure_dismissed': true})
          .eq('id', uid);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<TenantScreening> _filtered(List<TenantScreening> all) {
    return all.where((s) {
      final matchesStatus =
          _filterStatus == null || s.status == _filterStatus;
      final matchesQuery = _query.isEmpty ||
          s.applicantFullName.toLowerCase().contains(_query) ||
          s.applicantEmail.toLowerCase().contains(_query);
      return matchesStatus && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final provider = context.watch<ScreeningProvider>();
    final items = _filtered(provider.screenings);
    final savedLink = context.watch<AuthProvider>().currentUser?.rentspreeInviteLink;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Tenant Screening'),
      ),
      body: Column(
        children: [
          // ── RentSpree disclosure card (shown once until dismissed) ───────
          if (!_disclosureDismissed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingMd, AppTheme.spacingMd,
                  AppTheme.spacingMd, 0),
              child: RentSpreeBeforeYouBegin(
                onOpen: () async {
                  final uid = Supabase.instance.client.auth.currentUser?.id;
                  final link = await loadRentspreeLink(uid);
                  await launchUrl(
                    Uri.parse(link),
                    mode: LaunchMode.externalApplication,
                  );
                },
                onDismiss: _dismissDisclosure,
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingMd,
              AppTheme.spacingMd,
              AppTheme.spacingMd,
              0,
            ),
            child: RentSpreeHowItWorks(
              needsLink: _disclosureDismissed &&
                  (savedLink == null || savedLink.trim().isEmpty),
            ),
          ),

          // ── Gold request button ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingMd, AppTheme.spacingMd,
                AppTheme.spacingMd, AppTheme.spacingSm),
            child: OutlinedButton.icon(
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: context.read<ScreeningProvider>(),
                      child: const ScreeningFormScreen(),
                    ),
                  ),
                );
                if (result == true && mounted) {
                  context.read<ScreeningProvider>().load();
                }
              },
              icon: const Icon(LucideIcons.userPlus),
              label: const Text('Request New Screening'),
            ),
          ),

          // ── Description ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: Text(
              'Request a background screening for any rental applicant. '
              'The applicant pays the screening fee directly to RentSpree. '
              'Results are delivered to your email. ELEVO does not collect '
              'or handle any screening fees.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
            ),
          ),

          const SizedBox(height: AppTheme.spacingMd),

          // ── Search bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name or email…',
                prefixIcon: Icon(LucideIcons.search, size: 18, color: colors.sage),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(LucideIcons.x, size: 16, color: colors.sage),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          const SizedBox(height: AppTheme.spacingSm),

          // ── Filter chips ─────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filterStatus == null,
                  onTap: () => setState(() => _filterStatus = null),
                  colors: colors,
                  theme: theme,
                ),
                const SizedBox(width: AppTheme.spacingSm),
                _FilterChip(
                  label: 'Invited',
                  selected: _filterStatus == ScreeningStatus.invited,
                  onTap: () => setState(() => _filterStatus = ScreeningStatus.invited),
                  colors: colors,
                  theme: theme,
                ),
                const SizedBox(width: AppTheme.spacingSm),
                _FilterChip(
                  label: 'Complete',
                  selected: _filterStatus == ScreeningStatus.complete,
                  onTap: () => setState(() => _filterStatus = ScreeningStatus.complete),
                  colors: colors,
                  theme: theme,
                ),
                const SizedBox(width: AppTheme.spacingSm),
                _FilterChip(
                  label: 'Approved',
                  selected: _filterStatus == ScreeningStatus.approved,
                  onTap: () => setState(() => _filterStatus = ScreeningStatus.approved),
                  colors: colors,
                  theme: theme,
                ),
                const SizedBox(width: AppTheme.spacingSm),
                _FilterChip(
                  label: 'Declined',
                  selected: _filterStatus == ScreeningStatus.declined,
                  onTap: () => setState(() => _filterStatus = ScreeningStatus.declined),
                  colors: colors,
                  theme: theme,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingMd),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? _EmptyState(colors: colors, theme: theme, hasFilter: _query.isNotEmpty || _filterStatus != null)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacingMd, 0,
                            AppTheme.spacingMd, AppTheme.spacingXxl),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppTheme.spacingSm),
                        itemBuilder: (ctx, i) => ScreeningApplicantCard(
                          screening: items[i],
                          colors: colors,
                          theme: theme,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChangeNotifierProvider.value(
                                value: context.read<ScreeningProvider>(),
                                child: ScreeningDetailScreen(
                                    screeningId: items[i].id),
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Screening record card ─────────────────────────────────────────────────────

class ScreeningApplicantCard extends StatelessWidget {
  final TenantScreening screening;
  final VoidCallback onTap;
  final ElevoColors colors;
  final ThemeData theme;

  const ScreeningApplicantCard({
    required this.screening,
    required this.onTap,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: colors.stone.withAlpha(120)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      screening.applicantFullName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      screening.propertyAndUnit,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    Wrap(
                      spacing: AppTheme.spacingSm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _TypeBadge(screening: screening, colors: colors, theme: theme),
                        _StatusBadge(status: screening.status, colors: colors, theme: theme),
                        Text(
                          _formatDate(screening.invitedAt),
                          style: theme.textTheme.labelSmall?.copyWith(color: colors.sage),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingSm),
              Icon(LucideIcons.chevronRight, size: 16, color: colors.sage),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ── Type badge ────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final TenantScreening screening;
  final ElevoColors colors;
  final ThemeData theme;

  const _TypeBadge({required this.screening, required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: colors.gold),
      ),
      child: Text(
        screening.feeLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.goldInk,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final ScreeningStatus status;
  final ElevoColors colors;
  final ThemeData theme;

  const _StatusBadge({required this.status, required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    switch (status) {
      case ScreeningStatus.invited:
        bg = colors.warningAmber;
        label = 'Invited';
      case ScreeningStatus.complete:
        bg = colors.successGreen;
        label = 'Complete';
      case ScreeningStatus.approved:
        bg = colors.gold;
        label = 'Approved';
      case ScreeningStatus.declined:
        bg = colors.urgentRed;
        label = 'Declined';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withAlpha(25),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: bg.withAlpha(80)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: bg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ElevoColors colors;
  final ThemeData theme;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.olive : colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: selected ? colors.olive : colors.stone,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected ? colors.onOlive : colors.ink,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ElevoColors colors;
  final ThemeData theme;
  final bool hasFilter;

  const _EmptyState({required this.colors, required this.theme, required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.userCheck, size: 48, color: colors.stone),
            const SizedBox(height: AppTheme.spacingMd),
            Text(
              hasFilter ? 'No results match your search.' : 'No screenings yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              hasFilter
                  ? 'Try adjusting your search or filter.'
                  : 'Tap "Request New Screening" to send your first invitation.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
