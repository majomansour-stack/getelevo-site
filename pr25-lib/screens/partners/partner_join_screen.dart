import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/partner_model.dart';
import '../../providers/partner_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/partners/partner_tier_selection_card.dart';

class PartnerJoinScreen extends StatefulWidget {
  const PartnerJoinScreen({super.key});

  @override
  State<PartnerJoinScreen> createState() => _PartnerJoinScreenState();
}

class _PartnerJoinScreenState extends State<PartnerJoinScreen> {
  int _step = 0; // 0-indexed: 0..3

  // ── Step 1 controllers ─────────────────────────────────────────────────
  final _businessNameCtrl = TextEditingController();
  final _ownerNameCtrl    = TextEditingController();
  final _phoneCtrl        = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _websiteCtrl      = TextEditingController();
  final _serviceAreaCtrl  = TextEditingController();
  final _licenseCtrl      = TextEditingController();
  final _contractorCtrl   = TextEditingController();
  String? _selectedCategory;
  String? _selectedYears;
  bool _hasInsurance = false;

  // ── Step 2 ─────────────────────────────────────────────────────────────
  PartnerTier? _selectedTier;

  // ── Step 3 ─────────────────────────────────────────────────────────────
  PlatformFile? _licenseFile;
  PlatformFile? _insuranceFile;
  PlatformFile? _logoFile;
  final List<PlatformFile> _workPhotos = [];

  // ── Step 4 ─────────────────────────────────────────────────────────────
  bool _termsAccepted = false;
  bool _isSubmitting = false;

  // ── Errors ─────────────────────────────────────────────────────────────
  final Map<String, String?> _errors = {};

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _websiteCtrl.dispose();
    _serviceAreaCtrl.dispose();
    _licenseCtrl.dispose();
    _contractorCtrl.dispose();
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────────

  bool _validateStep1() {
    final errs = <String, String?>{};
    if (_businessNameCtrl.text.trim().isEmpty) errs['businessName'] = 'Business name is required';
    if (_ownerNameCtrl.text.trim().isEmpty)    errs['ownerName']    = 'Owner name is required';
    if (_selectedCategory == null)             errs['category']     = 'Please select a category';
    if (_phoneCtrl.text.trim().isEmpty)        errs['phone']        = 'Phone number is required';
    if (_emailCtrl.text.trim().isEmpty) {
      errs['email'] = 'Email is required';
    } else if (!RegExp(r'^[\w.+-]+@[\w-]+\.\w{2,}$').hasMatch(_emailCtrl.text.trim())) {
      errs['email'] = 'Enter a valid email address';
    }
    if (_serviceAreaCtrl.text.trim().isEmpty)  errs['serviceArea']  = 'Service area is required';
    if (_licenseCtrl.text.trim().isEmpty)      errs['license']      = 'Business license number is required';
    setState(() => _errors.addAll(errs));
    return errs.isEmpty;
  }

  bool _validateStep2() {
    if (_selectedTier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a partnership tier.')),
      );
      return false;
    }
    return true;
  }

  bool _validateStep3() {
    final errs = <String, String?>{};
    if (_licenseFile == null)   errs['licenseFile']   = 'Business license upload is required';
    if (_insuranceFile == null) errs['insuranceFile'] = 'Insurance certificate upload is required';
    if (_selectedTier != PartnerTier.basic && _logoFile == null) {
      errs['logoFile'] = 'Logo is required for Featured, Preferred, and Platinum tiers';
    }
    setState(() => _errors.addAll(errs));
    return errs.isEmpty;
  }

  // ── File pickers ───────────────────────────────────────────────────────

  Future<void> _pickLicense() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _licenseFile = result.files.first;
        _errors.remove('licenseFile');
      });
    }
  }

  Future<void> _pickInsurance() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _insuranceFile = result.files.first;
        _errors.remove('insuranceFile');
      });
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _logoFile = result.files.first;
        _errors.remove('logoFile');
      });
    }
  }

  Future<void> _pickWorkPhotos() async {
    if (_workPhotos.length >= 5) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        final remaining = 5 - _workPhotos.length;
        _workPhotos.addAll(result.files.take(remaining));
      });
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  void _next() {
    bool valid = switch (_step) {
      0 => _validateStep1(),
      1 => _validateStep2(),
      2 => _validateStep3(),
      _ => true,
    };
    if (valid && _step < 3) setState(() { _errors.clear(); _step++; });
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  // ── Submit ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms and conditions.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);

    final application = PartnerApplication(
      id: 'app_${DateTime.now().millisecondsSinceEpoch}',
      businessName: _businessNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      category: _selectedCategory!,
      yearsInBusiness: _selectedYears ?? 'Less than 1 year',
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      website: _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
      serviceArea: _serviceAreaCtrl.text.trim(),
      licenseNumber: _licenseCtrl.text.trim(),
      contractorLicense: _contractorCtrl.text.trim().isEmpty ? null : _contractorCtrl.text.trim(),
      hasInsurance: _hasInsurance,
      tier: _selectedTier!,
      status: PartnerStatus.pending,
      monthlyPrice: _selectedTier!.monthlyPrice,
      submittedAt: DateTime.now(),
    );

    try {
      await context.read<PartnerProvider>().submitApplication(application);
      if (!mounted) return;
      _showSuccessDialog();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit application. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog() {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.checkCircle, color: colors.gold, size: 22),
            const SizedBox(width: 8),
            const Text('Application Received'),
          ],
        ),
        content: const Text(
          'Thank you for applying to the ELEVO Preferred Partner Program. '
          'We have received your application and our team will review it within '
          '2 business days. We will contact you at your email address with next '
          'steps including payment setup.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join as a Partner'),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // ── Step progress indicator ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingMd),
            child: Row(
              children: List.generate(4, (i) {
                final done    = i < _step;
                final current = i == _step;
                return Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 4,
                          decoration: BoxDecoration(
                            color: done || current ? colors.gold : colors.stone,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (i < 3) const SizedBox(width: 4),
                    ],
                  ),
                );
              }),
            ),
          ),

          // ── Step label ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _stepLabel(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.midnight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Step ${_step + 1} of 4',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Step content ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
              child: _buildStep(context, theme, colors),
            ),
          ),

          // ── Bottom buttons ────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: _step < 3
                  ? Row(
                      children: [
                        if (_step > 0) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _back,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, AppTheme.buttonHeight),
                                foregroundColor: colors.midnight,
                                backgroundColor: Colors.transparent,
                                side: BorderSide(color: colors.midnight),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                              ),
                              child: const Text('Back'),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingMd),
                        ],
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _next,
                            child: const Text('Continue'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _back,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, AppTheme.buttonHeight),
                              foregroundColor: colors.midnight,
                              backgroundColor: Colors.transparent,
                              side: BorderSide(color: colors.midnight),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                            ),
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingMd),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.gold,
                              foregroundColor: colors.midnight,
                              minimumSize: const Size(0, AppTheme.buttonHeight),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Submit Application'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _stepLabel() {
    return switch (_step) {
      0 => 'Business Information',
      1 => 'Choose Your Tier',
      2 => 'Upload Documents',
      _ => 'Review & Submit',
    };
  }

  Widget _buildStep(BuildContext context, ThemeData theme, ElevoColors colors) {
    return switch (_step) {
      0 => _buildStep1(theme, colors),
      1 => _buildStep2(theme, colors),
      2 => _buildStep3(theme, colors),
      _ => _buildStep4(theme, colors),
    };
  }

  // ── Step 1 — Business Info ─────────────────────────────────────────────

  Widget _buildStep1(ThemeData theme, ElevoColors colors) {
    return Column(
      children: [
        _field(_businessNameCtrl, 'Business Name', LucideIcons.building2,
            error: _errors['businessName']),
        _field(_ownerNameCtrl, 'Owner Full Name', LucideIcons.user,
            error: _errors['ownerName']),
        _dropdown(
          label: 'Trade Category',
          value: _selectedCategory,
          items: kPartnerCategories.where((c) => c != 'All').toList(),
          onChanged: (v) => setState(() { _selectedCategory = v; _errors.remove('category'); }),
          error: _errors['category'],
        ),
        _dropdown(
          label: 'Years in Business',
          value: _selectedYears,
          items: kYearsInBusiness,
          onChanged: (v) => setState(() => _selectedYears = v),
        ),
        _field(_phoneCtrl, 'Phone Number', LucideIcons.phone,
            keyboard: TextInputType.phone, error: _errors['phone']),
        _field(_emailCtrl, 'Email Address', LucideIcons.mail,
            keyboard: TextInputType.emailAddress, error: _errors['email']),
        _field(_websiteCtrl, 'Website (optional)', LucideIcons.globe,
            keyboard: TextInputType.url),
        _field(_serviceAreaCtrl, 'Service Area', LucideIcons.mapPin,
            hint: 'e.g. Phoenix Metro, Scottsdale & Tempe',
            error: _errors['serviceArea']),
        _field(_licenseCtrl, 'Arizona Business License Number', LucideIcons.fileCheck,
            error: _errors['license']),
        _field(_contractorCtrl, 'AZ Contractor License (optional)', LucideIcons.award),
        // Insurance toggle
        Container(
          margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: colors.stone),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.shield, color: colors.sage, size: 20),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Text('General Liability Insurance',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink)),
              ),
              Switch(
                value: _hasInsurance,
                onChanged: (v) => setState(() => _hasInsurance = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingMd),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    String? hint,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, size: 18),
            errorText: error,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppTheme.spacingMd),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? error,
  }) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            labelText: label,
            errorText: error,
          ),
          dropdownColor: colors.card,
          style: TextStyle(color: colors.ink, fontSize: 15),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
        const SizedBox(height: AppTheme.spacingMd),
      ],
    );
  }

  // ── Step 2 — Tier selection ────────────────────────────────────────────

  Widget _buildStep2(ThemeData theme, ElevoColors colors) {
    return Column(
      children: [
        ...PartnerTier.values.map((tier) => PartnerTierSelectionCard(
          tier: tier,
          isSelected: _selectedTier == tier,
          mostPopular: tier == PartnerTier.preferred,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedTier = tier);
          },
        )),
        const SizedBox(height: AppTheme.spacingMd),
      ],
    );
  }

  // ── Step 3 — Documents ────────────────────────────────────────────────

  Widget _buildStep3(ThemeData theme, ElevoColors colors) {
    return Column(
      children: [
        _uploadField(
          label: 'Business License',
          sublabel: 'PDF or image — required',
          icon: LucideIcons.fileCheck,
          file: _licenseFile,
          error: _errors['licenseFile'],
          onPick: _pickLicense,
          colors: colors,
          theme: theme,
        ),
        _uploadField(
          label: 'Proof of Insurance',
          sublabel: 'General liability certificate — required',
          icon: LucideIcons.shield,
          file: _insuranceFile,
          error: _errors['insuranceFile'],
          onPick: _pickInsurance,
          colors: colors,
          theme: theme,
        ),
        _uploadField(
          label: 'Company Logo',
          sublabel: _selectedTier == PartnerTier.basic
              ? 'PNG or JPG — optional for Basic'
              : 'PNG or JPG — required for your tier',
          icon: LucideIcons.image,
          file: _logoFile,
          error: _errors['logoFile'],
          onPick: _pickLogo,
          colors: colors,
          theme: theme,
        ),
        // Work photos
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Work Photos (up to 5) — optional',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.sage),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            ElevatedButton.icon(
              onPressed: _workPhotos.length < 5 ? _pickWorkPhotos : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.olive,
                foregroundColor: colors.onOlive,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
              ),
              icon: const Icon(LucideIcons.camera, size: 16),
              label: Text('${_workPhotos.length}/5 Photos Selected'),
            ),
            const SizedBox(height: AppTheme.spacingLg),
          ],
        ),
      ],
    );
  }

  Widget _uploadField({
    required String label,
    required String sublabel,
    required IconData icon,
    required PlatformFile? file,
    required String? error,
    required VoidCallback onPick,
    required ElevoColors colors,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: onPick,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: colors.midnight,
            minimumSize: const Size(double.infinity, 80),
            elevation: 0,
            side: BorderSide(
              color: error != null ? colors.urgentRed : colors.gold,
              width: 1.5,
              style: BorderStyle.solid,
            ),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(file != null ? LucideIcons.checkCircle : icon,
                  color: file != null ? colors.successGreen : colors.gold, size: 24),
              const SizedBox(height: 6),
              Text(
                file != null ? file.name : label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: file != null ? colors.successGreen : colors.midnight,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                file != null ? 'Tap to replace' : sublabel,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(error, style: TextStyle(color: colors.urgentRed, fontSize: 12)),
          ),
        const SizedBox(height: AppTheme.spacingMd),
      ],
    );
  }

  // ── Step 4 — Review & Submit ───────────────────────────────────────────

  Widget _buildStep4(ThemeData theme, ElevoColors colors) {
    final tier = _selectedTier!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary card
        Container(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: colors.stone),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Application Summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.midnight, fontWeight: FontWeight.w700)),
              const SizedBox(height: AppTheme.spacingMd),
              _summaryRow('Business', _businessNameCtrl.text.trim(), colors, theme),
              _summaryRow('Owner', _ownerNameCtrl.text.trim(), colors, theme),
              _summaryRow('Category', _selectedCategory ?? '', colors, theme),
              _summaryRow('Phone', _phoneCtrl.text.trim(), colors, theme),
              _summaryRow('Email', _emailCtrl.text.trim(), colors, theme),
              _summaryRow('Service Area', _serviceAreaCtrl.text.trim(), colors, theme),
              _summaryRow('License', _licenseCtrl.text.trim(), colors, theme),
              if (_contractorCtrl.text.trim().isNotEmpty)
                _summaryRow('Contractor License', _contractorCtrl.text.trim(), colors, theme),
              _summaryRow('Insurance', _hasInsurance ? 'Yes' : 'No', colors, theme),
              Divider(height: AppTheme.spacingLg, color: colors.stone),
              _summaryRow('Tier', '${tier.label} Partner', colors, theme),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingMd),

        // Total
        Container(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(
            color: colors.charcoal,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monthly Investment',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.ivory)),
              Text(
                '\$${formatVendorPrice(tier.monthlyPrice)}/mo',
                style: TextStyle(
                  color: colors.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppTheme.spacingMd),

        // Terms checkbox
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _termsAccepted,
              onChanged: (v) => setState(() => _termsAccepted = v ?? false),
              activeColor: colors.gold,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _termsAccepted = !_termsAccepted),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'I confirm all information provided is accurate and I agree to the ELEVO '
                    'Preferred Partner Program terms and disclaimer.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.ink),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingLg),
      ],
    );
  }

  Widget _summaryRow(String label, String value, ElevoColors colors, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.sage)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.ink, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
