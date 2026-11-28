import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/theme.dart';

const _qaEmail = 'hello@getelevo.app';

// ── Data ──────────────────────────────────────────────────────────────────────

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});
}

class _FaqCategory {
  final String label;
  final IconData icon;
  final List<_FaqItem> items;

  const _FaqCategory({required this.label, required this.icon, required this.items});
}

const _landlordFaq = [
  _FaqCategory(
    label: 'Getting Started',
    icon: LucideIcons.rocket,
    items: [
      _FaqItem(
        question: 'How do I add my first property?',
        answer: 'Tap the Properties tab at the bottom of the screen, then tap the + button in the top-right corner or the gold FAB. Fill in your property name, address, and optional photo, then tap Save. Your property will appear immediately in your dashboard.',
      ),
      _FaqItem(
        question: 'How do I invite a tenant to their unit?',
        answer: 'Go to More → Invite Tenant (or tap the gold Invite Tenant tile). Select the vacant unit from the dropdown, enter your tenant\'s name, email address, and phone number, then tap Send Invitation. Your tenant will receive an email with a link to download Elevo and create their account.',
      ),
      _FaqItem(
        question: 'What is the Private Vault?',
        answer: 'The Private Vault (More → Private Vault) is a landlord-only storage area for sensitive notes, private documents, screening results, and photos related to your units. Tenants can never see vault contents — even documents you upload there are completely hidden from tenant accounts.',
      ),
    ],
  ),
  _FaqCategory(
    label: 'Subscriptions & Billing',
    icon: LucideIcons.creditCard,
    items: [
      _FaqItem(
        question: 'How does per-property pricing work on Essential?',
        answer: 'The Essential plan includes 1 property (\$39.99/month or \$299/year). Each additional property is \$12.99/month. The Unlimited plan at \$79/month covers unlimited properties.',
      ),
      _FaqItem(
        question: 'What is the Done-for-You setup add-on?',
        answer: 'For a one-time fee of \$249, the Elevo team will set up all your properties in the app, upload all your existing documents (leases, checklists, inspection reports), and configure your account settings. Ideal if you have multiple properties and want a clean start.',
      ),
      _FaqItem(
        question: 'How do I manage or cancel my subscription?',
        answer: 'Go to More → Subscription & Pricing → Manage Subscription. This opens the Stripe Customer Portal where you can upgrade, downgrade, update your payment method, or cancel at any time. Changes take effect at the next billing cycle.',
      ),
      _FaqItem(
        question: 'How does the 7-day trial work?',
        answer: 'Essential and Unlimited include a 7-day trial. A card is collected upfront and is charged when the trial ends unless you cancel first.',
      ),
    ],
  ),
  _FaqCategory(
    label: 'Rent & Payments',
    icon: LucideIcons.dollarSign,
    items: [
      _FaqItem(
        question: 'Does Elevo process rent payments?',
        answer: 'No. Elevo is an information and record-keeping tool — it does not handle money. Rent is paid directly between tenant and landlord using your preferred method (Zelle, Venmo, bank transfer, check, or cash). Elevo records and tracks payment confirmations only.',
      ),
      _FaqItem(
        question: 'How do I enter my preferred payment methods?',
        answer: 'Go to More → Payment Methods. Add each way you accept rent, such as Zelle, Venmo, check, or a bank transfer, with the handle and any instructions. Only your own tenants see them on their rent screen. You can edit, reorder, or remove a method later. Elevo does not collect the money.',
      ),
      _FaqItem(
        question: 'How does the tenant payment confirmation work?',
        answer: 'After a tenant pays you through their chosen method, they tap "I Have Paid" in the app. You receive a push notification and can review the payment record. Tap "Confirm Payment Received" to mark it as confirmed with a timestamp — this creates a permanent paper trail.',
      ),
    ],
  ),
  _FaqCategory(
    label: 'Maintenance & Vendors',
    icon: LucideIcons.wrench,
    items: [
      _FaqItem(
        question: 'How does emergency maintenance work?',
        answer: 'When a tenant submits a maintenance request with Emergency priority, Elevo immediately sends a push notification to your device — regardless of your notification preferences. Non-emergency requests also send a push notification and appear in your maintenance queue.',
      ),
      _FaqItem(
        question: 'What is vendor spend limit enforcement?',
        answer: 'Each vendor in your directory has a spend limit (the max you authorize per job). When you assign a vendor to a maintenance request and enter an estimated cost at or below their limit, the vendor is notified automatically. If the estimate exceeds their limit, you receive an approval request first — the vendor is only notified after you approve.',
      ),
      _FaqItem(
        question: 'Can I track multiple vendors?',
        answer: 'Yes — go to More → Vendors to manage your vendor directory. You can add unlimited vendors with contact info, trade category, and spend limits. Tap any vendor card to view their full profile, edit their information, or see their job history.',
      ),
    ],
  ),
  _FaqCategory(
    label: 'Documents & Reports',
    icon: LucideIcons.fileText,
    items: [
      _FaqItem(
        question: 'How long are documents stored?',
        answer: 'Documents and photos are stored indefinitely in Supabase Storage as long as your Elevo subscription is active. Files are stored in private buckets with daily automatic backups. All download links expire after 1 hour for security — a new signed URL is generated each time you open a document.',
      ),
      _FaqItem(
        question: 'How do I generate a Move-Out Inspection Report?',
        answer: 'Go to a unit\'s Photos tab (or More → Photo Log), select the Move-Out tab, and tap Generate Report. Elevo creates a PDF with side-by-side move-in and move-out photos, timestamps, and unit details that you can save or share directly.',
      ),
      _FaqItem(
        question: 'What does the P&L report include?',
        answer: 'Go to More → Reports. You can view monthly or annual profit & loss. Income is automatically populated from confirmed rent payments. You can manually add expenses (repairs, HOA fees, insurance, taxes, etc.) and assign them to specific properties. The report shows net profit/loss, margin percentage, and an expense category breakdown.',
      ),
    ],
  ),
  _FaqCategory(
    label: 'Arizona Law',
    icon: LucideIcons.scale,
    items: [
      _FaqItem(
        question: 'How much can I charge for a security deposit in Arizona?',
        answer: 'Under A.R.S. § 33-1321, a security deposit cannot exceed one and a half months\' rent. That cap applies to every residential unit, furnished or unfurnished. The deposit must be returned, minus lawful deductions, within 14 business days after the tenant moves out. Elevo does not give legal advice.',
      ),
      _FaqItem(
        question: 'Can I enter my tenant\'s unit without notice?',
        answer: 'Generally no. Under ARS §33-1343, you must provide at least 2 days notice before entering a tenant\'s unit — except in genuine emergencies. Entry must be at reasonable times. Failure to provide proper notice can constitute a landlord breach of the rental agreement.',
      ),
      _FaqItem(
        question: 'What is the eviction process in Arizona?',
        answer: 'Arizona\'s eviction (Special Detainer) process requires: (1) Written notice to tenant per ARS §33-1368; (2) Filing a complaint with Justice Court after notice period expires; (3) A hearing typically within 3–6 business days of filing; (4) Writ of Restitution if landlord prevails. Elevo does not give legal advice. Check the statute or a lawyer for your own case.',
      ),
    ],
  ),
];

const _tenantFaq = [
  _FaqCategory(
    label: 'My Rent',
    icon: LucideIcons.dollarSign,
    items: [
      _FaqItem(
        question: 'How do I pay my rent?',
        answer: 'Elevo does not collect rent. On your home screen, under Rent, you will see the payment instructions your own landlord entered (Zelle, Venmo, bank transfer, check, or cash). Pay them directly, then tap "I Have Paid" so your landlord can confirm it.',
      ),
      _FaqItem(
        question: 'Where can I see my payment history?',
        answer: 'Your confirmed payments appear in the payment history section on your home screen. Each entry shows the date, amount, and payment method. Your landlord confirms payments after receiving them — pending payments show until confirmed.',
      ),
      _FaqItem(
        question: 'What happens if I pay late?',
        answer: 'Late fees are between you and your landlord. Elevo does not add a late-fee line to the rent screen. Message your landlord if you have a question about a late payment.',
      ),
    ],
  ),
  _FaqCategory(
    label: 'Maintenance Requests',
    icon: LucideIcons.wrench,
    items: [
      _FaqItem(
        question: 'How do I submit a maintenance request?',
        answer: 'Tap the Maintenance tab at the bottom of the screen, then tap "Submit New Request." Describe the issue, select a category and priority level, and optionally add up to 5 photos. Tap Submit — your landlord will be notified immediately.',
      ),
      _FaqItem(
        question: 'What priority should I choose for my request?',
        answer: 'Low: cosmetic or non-urgent issues that can wait weeks. Medium: issues affecting comfort but not safety (e.g., appliance not working). High: issues significantly affecting habitability (e.g., major leak, AC failure in summer). Emergency: immediate safety threats (e.g., gas leak, flooding, no heat in winter). Elevo does not send text messages. Contact your landlord directly in an emergency.',
      ),
      _FaqItem(
        question: 'How do I track the status of my request?',
        answer: 'Each request shows a 4-stage progress bar: Submitted → Assigned → In Progress → Resolved. Tap any request to see full details including landlord notes and assigned vendor name. You\'ll receive a push notification whenever your landlord updates the status.',
      ),
    ],
  ),
  _FaqCategory(
    label: 'Documents & Lease',
    icon: LucideIcons.fileText,
    items: [
      _FaqItem(
        question: 'Where can I find my lease agreement?',
        answer: 'Go to More → Documents. Your lease agreement and other documents shared by your landlord appear here. Tap any document to preview or download it. You can filter by document type using the chips at the top.',
      ),
      _FaqItem(
        question: 'How do I know when my lease expires?',
        answer: 'Your home screen shows a lease countdown card with a circular progress indicator, your lease end date, and the exact number of days remaining. Your landlord will also send reminders at 90, 60, and 30 days before expiration (if enabled).',
      ),
    ],
  ),
  _FaqCategory(
    label: 'Messages',
    icon: LucideIcons.messageCircle,
    items: [
      _FaqItem(
        question: 'How do I message my landlord?',
        answer: 'Tap the Messages tab at the bottom of the screen to open a direct conversation with your landlord. You can send text messages and attach photos or files. You\'ll receive a push notification when your landlord replies.',
      ),
      _FaqItem(
        question: 'Can my landlord see all my messages?',
        answer: 'Messages between you and your landlord are private to your conversation. No other tenants can see your messages. Elevo stores messages securely in Supabase with row-level security policies ensuring only you and your landlord can access your conversation.',
      ),
    ],
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class QAndAScreen extends StatefulWidget {
  final bool isLandlord;

  const QAndAScreen({super.key, this.isLandlord = true});

  @override
  State<QAndAScreen> createState() => _QAndAScreenState();
}

class _QAndAScreenState extends State<QAndAScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_FaqCategory> get _categories =>
      widget.isLandlord ? _landlordFaq : _tenantFaq;

  List<_FaqCategory> get _filtered {
    if (_query.isEmpty) return _categories;
    final q = _query.toLowerCase();
    return _categories
        .map((cat) => _FaqCategory(
              label: cat.label,
              icon: cat.icon,
              items: cat.items.where((item) =>
                  item.question.toLowerCase().contains(q) ||
                  item.answer.toLowerCase().contains(q)).toList(),
            ))
        .where((cat) => cat.items.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Icon(LucideIcons.helpCircle, color: colors.gold, size: 18),
            const SizedBox(width: 8),
            const Text('Help & FAQ'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: TextFormField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search questions…',
                prefixIcon: Icon(LucideIcons.search, color: colors.taupe, size: 18),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(LucideIcons.x, color: colors.taupe, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Contact support banner — clickable email & phone
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: colors.gold.withAlpha(15),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: colors.gold.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.headphones, color: colors.gold, size: 18),
                      const SizedBox(width: AppTheme.spacingSm),
                      Text('Still need help?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.gold, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('Mon–Fri', style: theme.textTheme.labelSmall),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  // Email button
                  GestureDetector(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      final uri = Uri(scheme: 'mailto', path: _qaEmail,
                          queryParameters: {'subject': 'Elevo Support'});
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
                      decoration: BoxDecoration(
                        color: colors.charcoal,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        border: Border.all(color: colors.taupe.withAlpha(50)),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.mail, color: colors.gold, size: 15),
                          const SizedBox(width: AppTheme.spacingSm),
                          Expanded(
                            child: Text(_qaEmail,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: colors.gold)),
                          ),
                          Icon(LucideIcons.externalLink,
                              color: colors.taupe, size: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // FAQ categories
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.searchX, color: colors.taupe, size: 40),
                        const SizedBox(height: AppTheme.spacingMd),
                        Text('No results for "$_query"', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: AppTheme.spacingSm),
                        Text('Try a different search term or contact support.',
                            style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacingMd, 0, AppTheme.spacingMd, 100),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSm),
                    itemBuilder: (context, i) => _CategoryExpansion(
                      category: _filtered[i],
                      initiallyExpanded: _query.isNotEmpty || i == 0,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Category Expansion Panel ──────────────────────────────────────────────────

class _CategoryExpansion extends StatefulWidget {
  final _FaqCategory category;
  final bool initiallyExpanded;

  const _CategoryExpansion({required this.category, this.initiallyExpanded = false});

  @override
  State<_CategoryExpansion> createState() => _CategoryExpansionState();
}

class _CategoryExpansionState extends State<_CategoryExpansion>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _ctrl;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: widget.initiallyExpanded ? 1 : 0,
    );
    _rotation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.lightImpact();
    setState(() => _expanded = !_expanded);
    if (_expanded) _ctrl.forward(); else _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: colors.charcoal,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: colors.gold.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.category.icon, color: colors.gold, size: 18),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  Expanded(
                    child: Text(widget.category.label, style: theme.textTheme.titleSmall?.copyWith(color: colors.ivory)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.gold.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.category.items.length}',
                      style: TextStyle(color: colors.goldInk, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  RotationTransition(
                    turns: _rotation,
                    child: Icon(LucideIcons.chevronDown, color: colors.taupe, size: 18),
                  ),
                ],
              ),
            ),
          ),

          // Items
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: widget.category.items.asMap().entries.map((entry) {
                final idx  = entry.key;
                final item = entry.value;
                return _FaqTile(
                  item: item,
                  isLast: idx == widget.category.items.length - 1,
                );
              }).toList(),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }
}

// ── FAQ Tile (accordion item) ─────────────────────────────────────────────────

class _FaqTile extends StatefulWidget {
  final _FaqItem item;
  final bool isLast;

  const _FaqTile({required this.item, required this.isLast});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Column(
      children: [
        Divider(height: 1, color: colors.taupe.withAlpha(30)),
        GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); setState(() => _open = !_open); },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.spacingMd, AppTheme.spacingSm + 4,
              AppTheme.spacingMd,
              _open ? AppTheme.spacingXs : AppTheme.spacingSm + 4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.item.question,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _open ? colors.gold : colors.ivory,
                      fontWeight: _open ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSm),
                Icon(
                  _open ? LucideIcons.minus : LucideIcons.plus,
                  color: colors.gold, size: 16,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingMd, 0, AppTheme.spacingMd, AppTheme.spacingMd),
            child: Text(
              widget.item.answer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.ivory.withAlpha(200),
                height: 1.6,
              ),
            ),
          ),
        if (widget.isLast) const SizedBox(height: AppTheme.spacingXs),
      ],
    );
  }
}
