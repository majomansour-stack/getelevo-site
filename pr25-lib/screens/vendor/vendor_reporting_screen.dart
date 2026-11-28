import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../../core/elevo_logic.dart';
import '../../services/vendor_maintenance_query.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/maintenance_model.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../utils/pdf_saver.dart';

class VendorReportingScreen extends StatefulWidget {
  const VendorReportingScreen({super.key});

  @override
  State<VendorReportingScreen> createState() => _VendorReportingScreenState();
}

class _VendorReportingScreenState extends State<VendorReportingScreen> {
  final _db = Supabase.instance.client;
  bool _isGenerating = false;
  List<MaintenanceRequest> _allJobs = [];
  bool _loadingJobs = true;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) { setState(() => _loadingJobs = false); return; }
      final rows = await VendorMaintenanceQuery(_db).loadForCurrentUser();
      setState(() {
        _allJobs = rows.map<MaintenanceRequest>(_mapMR).toList();
        _loadingJobs = false;
      });
    } catch (_) {
      setState(() => _loadingJobs = false);
    }
  }

  MaintenanceRequest _mapMR(Map<String, dynamic> r) => MaintenanceRequest(
        id: r['id'] as String,
        unitId: r['unit_id'] as String,
        propertyId: '',
        landlordId: r['landlord_id'] as String,
        submittedBy: (r['tenant_id'] as String?) ?? '',
        description: r['description'] as String,
        category: (r['category'] as String?) ?? 'Other',
        priority: _cap((r['priority'] as String?) ?? 'medium'),
        status: _mapStatus((r['status'] as String?) ?? 'open'),
        assignedVendorName: r['vendor_name'] as String?,
        estimatedCost: r['estimated_cost'] != null ? (r['estimated_cost'] as num).toDouble() : null,
        unitAddress: r['unit_address'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        photos: repairPhotoPaths(r['photo_paths']),
      );

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  String _mapStatus(String s) => mapMaintenanceStatus(s);

  // ── PDF generation ───────────────────────────────────────────────────────────

  Future<void> _downloadReport(
    List<MaintenanceRequest> jobs,
    String vendorName,
    double totalEarned,
    double totalPending,
    double completionRate,
  ) async {
    setState(() => _isGenerating = true);
    try {
      final bytes = await _buildPdf(
          jobs, vendorName, totalEarned, totalPending, completionRate);
      final now = DateFormat('yyyy_MM_dd').format(DateTime.now());
      await savePdfFile(bytes, 'Elevo_Vendor_Report_$now.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Report downloaded successfully'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate report. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<Uint8List> _buildPdf(
    List<MaintenanceRequest> jobs,
    String vendorName,
    double totalEarned,
    double totalPending,
    double completionRate,
  ) async {
    final pdf = pw.Document();
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final dateFmt = DateFormat('MMM d, yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context ctx) => [
          // ── Header block ──────────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('1F3A5F'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ELEVO',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('C9A227'),
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('Property management, elevated.',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('7B8794'),
                        fontSize: 9)),
                pw.SizedBox(height: 10),
                pw.Text('Vendor Work Order Report',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    '$vendorName  ·  Generated ${dateFmt.format(DateTime.now())}',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('7B8794'), fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // ── Summary table ─────────────────────────────────────────────────
          pw.Text('SUMMARY',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('7B8794'),
                  letterSpacing: 1.2)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(
                color: PdfColor.fromHex('D8D2C8'), width: 0.5),
            children: [
              _pdfRow('Total Jobs', '${jobs.length}', PdfColors.black),
              _pdfRow('Completed', '${jobs.where((j) => j.status == 'Resolved').length}',
                  PdfColor.fromHex('4CAF50')),
              _pdfRow('Active', '${jobs.where((j) => j.status != 'Resolved').length}',
                  PdfColor.fromHex('7A5E28')),
              _pdfRow('Completion Rate',
                  '${(completionRate * 100).toStringAsFixed(0)}%',
                  PdfColor.fromHex('1F3A5F')),
              _pdfRow('Total Earned (Estimates)', fmt.format(totalEarned),
                  PdfColor.fromHex('4CAF50')),
              _pdfRow('Pending (Estimates)', fmt.format(totalPending),
                  PdfColor.fromHex('7A5E28')),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Job detail table ──────────────────────────────────────────────
          pw.Text('WORK ORDERS',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('7B8794'),
                  letterSpacing: 1.2)),
          pw.SizedBox(height: 6),
          if (jobs.isEmpty)
            pw.Text('No work orders found.',
                style: pw.TextStyle(color: PdfColor.fromHex('7B8794')))
          else
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColor.fromHex('D8D2C8'), width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.5),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration:
                      pw.BoxDecoration(color: PdfColor.fromHex('1F3A5F')),
                  children: [
                    _pdfCell('Description', bold: true, color: PdfColors.white),
                    _pdfCell('Category', bold: true, color: PdfColors.white),
                    _pdfCell('Priority', bold: true, color: PdfColors.white),
                    _pdfCell('Status', bold: true, color: PdfColors.white),
                    _pdfCell('Est. Cost', bold: true, color: PdfColors.white,
                        align: pw.TextAlign.right),
                  ],
                ),
                ...jobs.map((job) => pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 5),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              job.description,
                              style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black),
                            ),
                            if (job.unitAddress != null)
                              pw.Text(job.unitAddress!,
                                  style: pw.TextStyle(
                                      fontSize: 7,
                                      color: PdfColor.fromHex('7B8794'))),
                            pw.Text(
                                'Opened: ${dateFmt.format(job.createdAt.toLocal())}',
                                style: pw.TextStyle(
                                    fontSize: 7,
                                    color: PdfColor.fromHex('7B8794'))),
                          ],
                        ),
                      ),
                      _pdfCell(job.category, fontSize: 8),
                      _pdfCell(job.priority, fontSize: 8,
                          color: job.priority == 'Emergency'
                              ? PdfColor.fromHex('D32F2F')
                              : job.priority == 'High'
                                  ? PdfColor.fromHex('7A5E28')
                                  : PdfColors.black),
                      _pdfCell(job.status, fontSize: 8,
                          color: job.status == 'Resolved'
                              ? PdfColor.fromHex('4CAF50')
                              : PdfColors.black),
                      _pdfCell(
                          job.estimatedCost != null
                              ? fmt.format(job.estimatedCost!)
                              : '—',
                          fontSize: 8,
                          align: pw.TextAlign.right,
                          color: job.status == 'Resolved'
                              ? PdfColor.fromHex('4CAF50')
                              : PdfColors.black),
                    ])),
              ],
            ),
          pw.SizedBox(height: 28),

          // ── Legal footer ──────────────────────────────────────────────────
          pw.Text(
            'INDEPENDENT CONTRACTOR NOTICE: Elevo is a technology platform only. '
            'All payments are made directly between the property owner and the service provider. '
            'ELEVO does not collect, process, or receive any portion of payments for services performed '
            'and charges no commission or referral fee. Amounts shown are estimates based on work orders '
            'and do not represent funds collected by or owed to ELEVO. Service providers are independent '
            'contractors and are not employees or agents of ELEVO.',
            style: pw.TextStyle(
                fontSize: 7,
                color: PdfColor.fromHex('7B8794'),
                fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  pw.TableRow _pdfRow(String label, String value, PdfColor valueColor) {
    return pw.TableRow(children: [
      _pdfCell(label, bold: true),
      _pdfCell(value, color: valueColor, align: pw.TextAlign.right),
    ]);
  }

  pw.Widget _pdfCell(String text,
      {bool bold = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
      double fontSize = 9}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final user = context.watch<AuthProvider>().currentUser;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final dateFmt = DateFormat('MMM d, yyyy');

    if (_loadingJobs) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final allJobs = List<MaintenanceRequest>.from(_allJobs)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final completed =
        allJobs.where((r) => r.status == 'Resolved').toList();
    final active = allJobs.where((r) => r.status != 'Resolved').toList();

    final totalEarned =
        completed.fold<double>(0.0, (s, r) => s + (r.estimatedCost ?? 0.0));
    final totalPending =
        active.fold<double>(0.0, (s, r) => s + (r.estimatedCost ?? 0.0));
    final completionRate =
        allJobs.isEmpty ? 0.0 : completed.length / allJobs.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('My Reports',
            style: theme.textTheme.titleMedium?.copyWith(
                color: colors.midnight, fontWeight: FontWeight.w700)),
        actions: [
          _isGenerating
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMd, vertical: 14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: colors.midnight),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: () => _downloadReport(
                    allJobs,
                    user?.fullName ?? 'Vendor',
                    totalEarned,
                    totalPending,
                    completionRate,
                  ),
                  icon: Icon(LucideIcons.download, size: 15,
                      color: colors.onOlive),
                  label: Text('Download',
                      style: TextStyle(fontSize: 12, color: colors.onOlive, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.olive,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMd, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSmall)),
                    elevation: 0,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
          const SizedBox(width: AppTheme.spacingMd),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Earnings summary ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.charcoal,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.barChart2, color: colors.gold, size: 20),
                    const SizedBox(width: AppTheme.spacingSm),
                    Text('Earnings Summary',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.ivory,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMd),
                Row(
                  children: [
                    _EarningsCell(
                        label: 'Total Earned',
                        value: fmt.format(totalEarned),
                        valueColor: colors.gold,
                        theme: theme,
                        colors: colors),
                    const SizedBox(width: AppTheme.spacingMd),
                    _EarningsCell(
                        label: 'Pending',
                        value: fmt.format(totalPending),
                        valueColor: colors.ivory,
                        theme: theme,
                        colors: colors),
                    const SizedBox(width: AppTheme.spacingMd),
                    _EarningsCell(
                        label: 'Total Jobs',
                        value: '${allJobs.length}',
                        valueColor: colors.ivory,
                        theme: theme,
                        colors: colors),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // ── Completion rate ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: colors.stone),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Completion Rate',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w600)),
                    Text(
                      '${(completionRate * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: colors.midnight,
                          fontWeight: FontWeight.w800,
                          fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingSm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: completionRate,
                    minHeight: 8,
                    backgroundColor: colors.stone.withAlpha(80),
                    valueColor: AlwaysStoppedAnimation<Color>(colors.olive),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXs),
                Text(
                  '${completed.length} of ${allJobs.length} jobs completed',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.sage),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Work order cards ───────────────────────────────────────────────
          Text('Work Orders',
              style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.midnight, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppTheme.spacingXs),
          Text('${allJobs.length} total  ·  ${active.length} active  ·  ${completed.length} completed',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.sage)),
          const SizedBox(height: AppTheme.spacingMd),

          if (allJobs.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: colors.stone),
              ),
              child: Center(
                child: Text('No work orders assigned yet.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.sage)),
              ),
            )
          else
            ...allJobs.map((job) => _JobCard(
                  job: job,
                  fmt: fmt,
                  dateFmt: dateFmt,
                  theme: theme,
                  colors: colors,
                )),

          const SizedBox(height: AppTheme.spacingLg),

          // ── Legal disclaimer ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: colors.stone.withAlpha(40),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: colors.stone),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.shieldCheck,
                        size: 15, color: colors.sage),
                    const SizedBox(width: 6),
                    Text(
                      'INDEPENDENT CONTRACTOR NOTICE',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.sage,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingSm),
                Text(
                  'Elevo is a technology '
                  'platform that connects independent service providers with '
                  'property owners and managers. ELEVO does not collect, '
                  'process, or receive any portion of payments made for '
                  'services performed. All payments are made directly between '
                  'the property owner or manager and the service provider. '
                  'ELEVO does not charge a commission, referral fee, or any '
                  'other fee on services rendered by vendors listed on its '
                  'platform. Amounts shown in this report are estimates based '
                  'on work orders and do not represent funds collected by or '
                  'owed to ELEVO. Service providers are independent '
                  'contractors and are not employees, agents, or '
                  'representatives of ELEVO. ELEVO assumes no liability for '
                  'the quality, completion, or payment of any service '
                  'performed through its platform.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.sage, height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─── Job card ─────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final MaintenanceRequest job;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final ThemeData theme;
  final ElevoColors colors;

  const _JobCard({
    required this.job,
    required this.fmt,
    required this.dateFmt,
    required this.theme,
    required this.colors,
  });

  Color get _priorityColor {
    switch (job.priority) {
      case 'Emergency':
        return colors.urgentRed;
      case 'High':
        return colors.urgentRed;
      case 'Low':
        return colors.sage;
      default:
        return colors.goldInk;
    }
  }

  Color get _statusColor {
    switch (job.status) {
      case 'Resolved':
        return colors.successGreen;
      case 'In Progress':
        return colors.midnight;
      case 'Assigned':
        return colors.goldInk;
      default:
        return colors.sage;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: colors.stone),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar: category + priority + status ────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd, vertical: 10),
            decoration: BoxDecoration(
              color: colors.stone.withAlpha(30),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMedium),
                topRight: Radius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                // Category chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.midnight.withAlpha(12),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Text(job.category,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.midnight,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: AppTheme.spacingXs),
                // Priority badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _priorityColor.withAlpha(20),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSmall),
                    border:
                        Border.all(color: _priorityColor.withAlpha(60)),
                  ),
                  child: Text(job.priority,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: _priorityColor,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                // Status chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withAlpha(18),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSmall),
                    border:
                        Border.all(color: _statusColor.withAlpha(70)),
                  ),
                  child: Text(job.status,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: _statusColor,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description — full text
                Text(
                  job.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.4),
                ),

                if (job.landlordNotes != null &&
                    job.landlordNotes!.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spacingXs),
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingSm),
                    decoration: BoxDecoration(
                      color: colors.gold.withAlpha(12),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSmall),
                      border: Border.all(
                          color: colors.gold.withAlpha(50)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.messageSquare,
                            size: 13, color: colors.gold),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            job.landlordNotes!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.ink, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppTheme.spacingMd),

                // ── Meta row ─────────────────────────────────────────────
                Row(
                  children: [
                    if (job.unitAddress != null) ...[
                      Icon(LucideIcons.mapPin,
                          size: 12, color: colors.sage),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          job.unitAddress!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.sage),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      const Expanded(child: SizedBox()),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(LucideIcons.calendar, size: 12, color: colors.sage),
                    const SizedBox(width: 4),
                    Text(
                      'Opened ${dateFmt.format(job.createdAt.toLocal())}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.sage),
                    ),
                    if (job.resolvedAt != null) ...[
                      const SizedBox(width: AppTheme.spacingMd),
                      Icon(LucideIcons.checkCircle,
                          size: 12, color: colors.successGreen),
                      const SizedBox(width: 4),
                      Text(
                        'Resolved ${dateFmt.format(job.resolvedAt!.toLocal())}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.successGreen),
                      ),
                    ],
                    const Spacer(),
                    if (job.estimatedCost != null) ...[
                      Icon(LucideIcons.dollarSign,
                          size: 12, color: colors.midnight),
                      const SizedBox(width: 2),
                      Text(
                        fmt.format(job.estimatedCost!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.midnight,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),

                // ── Days open pill ────────────────────────────────────────
                const SizedBox(height: AppTheme.spacingSm),
                Row(
                  children: [
                    Icon(LucideIcons.clock, size: 12, color: colors.sage),
                    const SizedBox(width: 4),
                    Text(
                      job.status == 'Resolved'
                          ? '${job.daysOpen} day${job.daysOpen == 1 ? '' : 's'} open before resolution'
                          : '${job.daysOpen} day${job.daysOpen == 1 ? '' : 's'} open',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: job.daysOpen > 14 && job.status != 'Resolved'
                              ? colors.urgentRed
                              : colors.sage),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Earnings cell ────────────────────────────────────────────────────────────

class _EarningsCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final ThemeData theme;
  final ElevoColors colors;

  const _EarningsCell({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.theme,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.ivory.withAlpha(140))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
        ],
      ),
    );
  }
}
