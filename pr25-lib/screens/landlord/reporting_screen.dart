import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/elevo_logic.dart';
import '../../providers/dashboard_provider.dart';
import '../../theme/theme.dart';
import '../../utils/pdf_saver.dart';

// ── Local models ──────────────────────────────────────────────────────────────

enum ExpenseCategory {
  repair, maintenance, hoaFee, insurance, taxes,
  management, advertising, utilities, landscaping, appliances, other
}

extension ExpenseCategoryLabel on ExpenseCategory {
  String get label {
    switch (this) {
      case ExpenseCategory.repair:      return 'Repair';
      case ExpenseCategory.maintenance: return 'Maintenance';
      case ExpenseCategory.hoaFee:      return 'HOA Fee';
      case ExpenseCategory.insurance:   return 'Insurance';
      case ExpenseCategory.taxes:       return 'Taxes';
      case ExpenseCategory.management:  return 'Management';
      case ExpenseCategory.advertising: return 'Advertising';
      case ExpenseCategory.utilities:   return 'Utilities';
      case ExpenseCategory.landscaping: return 'Landscaping';
      case ExpenseCategory.appliances:  return 'Appliances';
      case ExpenseCategory.other:       return 'Other';
    }
  }
}

class Expense {
  final String id;
  final String description;
  final double amount;
  final ExpenseCategory category;
  final String? propertyId;
  final DateTime date;

  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    this.propertyId,
    required this.date,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen> {
  bool _isAnnual      = false;
  int _selectedMonth  = DateTime.now().month;
  int _selectedYear   = DateTime.now().year;
  bool _isGenerating  = false;
  String? _selectedPropertyId; // null = All Properties

  final List<Expense> _expenses = [];
  List<_RentRecord> _confirmedRent = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFinancials());
  }

  Future<void> _loadFinancials() async {
    if (!mounted) return;
    final dash = context.read<DashboardProvider>();
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return;

    final unitMeta = <String, ({String label, String propertyId, String tenant})>{};
    for (final property in dash.properties) {
      for (final unit in property.units) {
        unitMeta[unit.id] = (
          label: '${property.name} #${unit.unitNumber}',
          propertyId: property.id,
          tenant: unit.tenantName ?? '',
        );
      }
    }

    final records = <_RentRecord>[];
    if (unitMeta.isNotEmpty) {
      try {
        final dueByUnit = {
          for (final property in dash.properties)
            for (final unit in property.units) unit.id: unit.rentDueDay,
        };
        final rows = await _confirmedPaymentRows(db, unitMeta.keys.toList());
        for (final row in rows) {
          final unitId = row['unit_id']?.toString();
          final meta = unitId == null ? null : unitMeta[unitId];
          if (meta == null) continue;
          final when = confirmedRentMonth(
            period: DateTime.tryParse((row['rent_period'] ?? '').toString()),
            submittedAt: DateTime.tryParse((row['submitted_at'] ?? '').toString()),
            dueDay: dueByUnit[unitId],
          );
          if (when == null) continue;
          records.add(_RentRecord(
            unitLabel: meta.label,
            amount: ((row['amount'] as num?) ?? 0).toDouble(),
            month: when.month,
            year: when.year,
            tenantName: meta.tenant,
            propertyId: meta.propertyId,
          ));
        }
      } catch (_) {}
    }

    final expenses = <Expense>[];
    try {
      final rows = await db.from('expenses').select().eq('landlord_id', uid);
      for (final row in rows) {
        final categoryName = row['category']?.toString() ?? '';
        expenses.add(Expense(
          id: row['id'].toString(),
          description: row['description']?.toString() ?? '',
          amount: ((row['amount'] as num?) ?? 0).toDouble(),
          category: ExpenseCategory.values.firstWhere(
            (category) => category.name == categoryName,
            orElse: () => ExpenseCategory.other,
          ),
          propertyId: row['property_id'] as String?,
          date: DateTime.tryParse(row['expense_date'].toString()) ?? DateTime.now(),
        ));
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _confirmedRent = records;
      _expenses
        ..clear()
        ..addAll(expenses);
    });
  }

  Future<List<Map<String, dynamic>>> _confirmedPaymentRows(
    SupabaseClient db,
    List<String> unitIds,
  ) async {
    try {
      final rows = await db
          .from('payments')
          .select('amount, status, unit_id, submitted_at, rent_period')
          .inFilter('unit_id', unitIds)
          .eq('status', 'confirmed');
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      final rows = await db
          .from('payments')
          .select('amount, status, unit_id, submitted_at')
          .inFilter('unit_id', unitIds)
          .eq('status', 'confirmed');
      return List<Map<String, dynamic>>.from(rows as List);
    }
  }

  Future<void> _persistExpense(Expense expense) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client.from('expenses').insert({
        'landlord_id': uid,
        'property_id': expense.propertyId,
        'description': expense.description,
        'amount': expense.amount,
        'category': expense.category.name,
        'expense_date': expense.date.toIso8601String(),
      }).select().single();
      if (!mounted) return;
      setState(() {
        _expenses.add(Expense(
          id: row['id'].toString(),
          description: expense.description,
          amount: expense.amount,
          category: expense.category,
          propertyId: expense.propertyId,
          date: expense.date,
        ));
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save that expense. The expenses table still needs to be added.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    try {
      await Supabase.instance.client.from('expenses').delete().eq('id', expense.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _expenses.remove(expense));
  }

  List<_RentRecord> _rentRecords(BuildContext _) {
    return _confirmedRent
        .where((record) =>
            _selectedPropertyId == null || record.propertyId == _selectedPropertyId)
        .toList();
  }

  List<Expense> get _monthExpenses => _expenses.where((e) =>
      e.date.month == _selectedMonth &&
      e.date.year == _selectedYear &&
      (_selectedPropertyId == null || e.propertyId == _selectedPropertyId ||
          e.propertyId == null)).toList();

  List<Expense> get _yearExpenses => _expenses.where((e) =>
      e.date.year == _selectedYear &&
      (_selectedPropertyId == null || e.propertyId == _selectedPropertyId ||
          e.propertyId == null)).toList();

  List<_RentRecord> _monthRent(BuildContext context) =>
      _rentRecords(context).where((r) => r.month == _selectedMonth && r.year == _selectedYear).toList();

  List<_RentRecord> _yearRent(BuildContext context) =>
      _rentRecords(context).where((r) => r.year == _selectedYear).toList();

  double _monthIncome(BuildContext context)   => _monthRent(context).fold(0.0, (s, r) => s + r.amount);
  double _monthExpTotal() => _monthExpenses.fold(0.0, (s, e) => s + e.amount);
  double _monthNet(BuildContext context)      => _monthIncome(context) - _monthExpTotal();

  double _yearIncome(BuildContext context)    => _yearRent(context).fold(0.0, (s, r) => s + r.amount);
  double _yearExpTotal()  => _yearExpenses.fold(0.0, (s, e) => s + e.amount);
  double _yearNet(BuildContext context)       => _yearIncome(context) - _yearExpTotal();

  // ── PDF generation ─────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdf() async {
    final ctx     = context;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final income  = _isAnnual ? _yearIncome(ctx) : _monthIncome(ctx);
    final expenses= _isAnnual ? _yearExpTotal() : _monthExpTotal();
    final net     = _isAnnual ? _yearNet(ctx) : _monthNet(ctx);
    final expList = _isAnnual ? _yearExpenses : _monthExpenses;
    final incList = _isAnnual ? _yearRent(ctx) : _monthRent(ctx);

    final properties = ctx.read<DashboardProvider>().properties;
    final propertyLabel = _selectedPropertyId == null
        ? 'All Properties'
        : properties
            .firstWhere((p) => p.id == _selectedPropertyId,
                orElse: () => properties.first)
            .name;
    final periodLabel = _isAnnual
        ? 'Annual Report - $_selectedYear | $propertyLabel'
        : '${_monthName(_selectedMonth)} $_selectedYear - Monthly Report | $propertyLabel';

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('1A1A1D'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ELEVO',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('C9A227'),
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('Property management, elevated.',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('8E8578'),
                        fontSize: 11)),
                pw.SizedBox(height: 12),
                pw.Text('Profit and Loss - $periodLabel',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Generated on ${DateFormat('MMMM d, y').format(DateTime.now())}',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('8E8578'),
                        fontSize: 10)),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // Summary table
          pw.Text('SUMMARY',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('8E8578'),
                  letterSpacing: 1.5)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(
                color: PdfColor.fromHex('E6D8C0'), width: 0.5),
            children: [
              _pdfRow('Total Rent Income',   fmt.format(income),   PdfColor.fromHex('7AAB5E')),
              _pdfRow('Total Expenses',      fmt.format(expenses), PdfColor.fromHex('D4756B')),
              _pdfRow(net >= 0 ? 'Net Profit' : 'Net Loss',
                  fmt.format(net.abs()),
                  net >= 0 ? PdfColor.fromHex('7A5E28') : PdfColor.fromHex('D4756B'),
                  bold: true),
              if (income > 0)
                _pdfRow('Profit Margin',
                    '${(((income - expenses) / income) * 100).toStringAsFixed(1)}%',
                    PdfColor.fromHex('7A5E28')),
            ],
          ),

          pw.SizedBox(height: 20),

          // Income section
          pw.Text('RENT INCOME',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('8E8578'),
                  letterSpacing: 1.5)),
          pw.SizedBox(height: 8),
          if (incList.isEmpty)
            pw.Text('No confirmed rent payments for this period.',
                style: pw.TextStyle(color: PdfColor.fromHex('8E8578')))
          else
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColor.fromHex('E6D8C0'), width: 0.5),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('1A1A1D')),
                  children: [
                    _pdfCell('Unit', bold: true, color: PdfColors.white),
                    _pdfCell('Tenant', bold: true, color: PdfColors.white),
                    _pdfCell('Amount', bold: true, color: PdfColors.white, align: pw.TextAlign.right),
                  ],
                ),
                ...incList.map((r) => pw.TableRow(children: [
                  _pdfCell(r.unitLabel),
                  _pdfCell(r.tenantName),
                  _pdfCell(fmt.format(r.amount), align: pw.TextAlign.right,
                      color: PdfColor.fromHex('7AAB5E')),
                ])),
              ],
            ),

          pw.SizedBox(height: 20),

          // Expenses section
          pw.Text('EXPENSES',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('8E8578'),
                  letterSpacing: 1.5)),
          pw.SizedBox(height: 8),
          if (expList.isEmpty)
            pw.Text('No expenses recorded for this period.',
                style: pw.TextStyle(color: PdfColor.fromHex('8E8578')))
          else
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColor.fromHex('E6D8C0'), width: 0.5),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('1A1A1D')),
                  children: [
                    _pdfCell('Description', bold: true, color: PdfColors.white),
                    _pdfCell('Category', bold: true, color: PdfColors.white),
                    _pdfCell('Date', bold: true, color: PdfColors.white),
                    _pdfCell('Amount', bold: true, color: PdfColors.white, align: pw.TextAlign.right),
                  ],
                ),
                ...expList.map((e) => pw.TableRow(children: [
                  _pdfCell(e.description),
                  _pdfCell(e.category.label),
                  _pdfCell(DateFormat('MMM d, y').format(e.date)),
                  _pdfCell(fmt.format(e.amount), align: pw.TextAlign.right,
                      color: PdfColor.fromHex('D4756B')),
                ])),
              ],
            ),

          pw.SizedBox(height: 32),

          // Footer disclaimer
          pw.Text(
            'This report is generated by Elevo for informational purposes only. '
            'Consult a licensed accountant or CPA for tax filing and financial advice.',
            style: pw.TextStyle(
                color: PdfColor.fromHex('8E8578'), fontSize: 9, fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.TableRow _pdfRow(String label, String value, PdfColor valueColor,
      {bool bold = false}) {
    return pw.TableRow(children: [
      _pdfCell(label, bold: bold),
      _pdfCell(value,
          color: valueColor,
          bold: bold,
          align: pw.TextAlign.right),
    ]);
  }

  pw.Widget _pdfCell(String text,
      {bool bold = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
        ),
      ),
    );
  }

  Future<void> _downloadPdf() async {
    HapticFeedback.lightImpact();
    setState(() => _isGenerating = true);
    try {
      final periodLabel = _isAnnual
          ? 'Elevo_Annual_${_selectedYear}_PL'
          : 'Elevo_${_monthName(_selectedMonth)}_${_selectedYear}_PL';

      final bytes = await _buildPdf();

      // savePdfFile: on web triggers a native browser blob download (no plugin needed);
      // on mobile uses the native share/save sheet via printing package.
      await savePdfFile(bytes, '$periodLabel.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final colors   = theme.extension<ElevoColors>()!;
    final fmt      = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final fmtK     = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final income   = _isAnnual ? _yearIncome(context)   : _monthIncome(context);
    final expenses = _isAnnual ? _yearExpTotal() : _monthExpTotal();
    final net      = _isAnnual ? _yearNet(context)       : _monthNet(context);
    final isProfit = net >= 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Financial Reports'),
        ),
        actions: [
          // PDF download button
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacingSm),
            child: _isGenerating
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.gold,
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(LucideIcons.download, color: colors.gold, size: 20),
                    tooltip: 'Download PDF',
                    onPressed: _downloadPdf,
                  ),
          ),
          // Monthly / Annual toggle
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacingMd),
            child: _PeriodToggle(
              isAnnual: _isAnnual,
              onChanged: (v) => setState(() => _isAnnual = v),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_expense',
        onPressed: () {
          HapticFeedback.lightImpact();
          _showAddExpenseSheet();
        },
        tooltip: 'Add Expense',
        child: const Icon(LucideIcons.plus),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // Period selector
          if (!_isAnnual) ...[
            _MonthSelector(
              selectedMonth: _selectedMonth,
              selectedYear: _selectedYear,
              onChanged: (m, y) =>
                  setState(() { _selectedMonth = m; _selectedYear = y; }),
            ),
            const SizedBox(height: AppTheme.spacingMd),
          ] else ...[
            _YearSelector(
              selectedYear: _selectedYear,
              onChanged: (y) => setState(() => _selectedYear = y),
            ),
            const SizedBox(height: AppTheme.spacingMd),
          ],

          // Property filter pills
          _PropertyFilter(
            selectedId: _selectedPropertyId,
            onChanged: (id) => setState(() => _selectedPropertyId = id),
            properties: context.watch<DashboardProvider>().properties,
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // P&L Summary Card
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: AppTheme.surfaceCard(colors),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.barChart2, color: colors.linkOlive, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _isAnnual
                          ? 'Annual Summary · $_selectedYear'
                          : '${_monthName(_selectedMonth)} P&L',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    // Inline download button
                    GestureDetector(
                      onTap: _isGenerating ? null : _downloadPdf,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colors.gold.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: colors.gold.withAlpha(60)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.download,
                                color: colors.linkOlive, size: 12),
                            const SizedBox(width: 4),
                            Text('PDF',
                                style: TextStyle(
                                    color: colors.linkOlive,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMd),
                Row(
                  children: [
                    Expanded(
                        child: _SummaryTile(
                            label: 'Income',
                            value: fmtK.format(income),
                            color: colors.successGreen)),
                    Container(
                        width: 1,
                        height: 40,
                        color: colors.taupe.withAlpha(40)),
                    Expanded(
                        child: _SummaryTile(
                            label: 'Expenses',
                            value: fmtK.format(expenses),
                            color: colors.urgentRed)),
                    Container(
                        width: 1,
                        height: 40,
                        color: colors.taupe.withAlpha(40)),
                    Expanded(
                        child: _SummaryTile(
                          label: isProfit ? 'Net Profit' : 'Net Loss',
                          value: fmt.format(net.abs()),
                          color: isProfit ? colors.goldInk : colors.urgentRed,
                          prefix: isProfit ? '+' : '-',
                        )),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMd),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: LinearProgressIndicator(
                      value: income > 0
                          ? (expenses / income).clamp(0.0, 1.0)
                          : 0,
                      backgroundColor: colors.successGreen.withAlpha(60),
                      valueColor: AlwaysStoppedAnimation(
                        expenses > income ? colors.urgentRed : colors.gold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  income > 0
                      ? '${(((income - expenses) / income) * 100).toStringAsFixed(1)}% profit margin'
                      : 'No income recorded',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacingLg),

          // Income section
          _SectionHeader(icon: LucideIcons.trendingUp, label: 'Rent Income', color: colors.successGreen),
          const SizedBox(height: AppTheme.spacingSm),
          ...(_isAnnual
              ? _buildAnnualIncomeRows(context, theme, colors, fmt)
              : _buildMonthlyIncomeRows(context, theme, colors, fmt)),

          const SizedBox(height: AppTheme.spacingLg),

          // Expenses section
          _SectionHeader(icon: LucideIcons.trendingDown, label: 'Expenses', color: colors.urgentRed),
          const SizedBox(height: AppTheme.spacingSm),
          if ((_isAnnual ? _yearExpenses : _monthExpenses).isEmpty)
            _EmptyLineItem(message: 'No expenses recorded.', colors: colors, theme: theme)
          else
            ...(_isAnnual ? _yearExpenses : _monthExpenses).map((e) => _ExpenseRow(
              expense: e,
              fmt: fmt,
              theme: theme,
              colors: colors,
              onDelete: () => _deleteExpense(e),
            )),

          const SizedBox(height: AppTheme.spacingLg),

          // Category breakdown
          _SectionHeader(icon: LucideIcons.pieChart, label: 'Expense Breakdown', color: colors.gold),
          const SizedBox(height: AppTheme.spacingSm),
          _CategoryBreakdown(
            expenses: _isAnnual ? _yearExpenses : _monthExpenses,
            total: expenses,
            theme: theme,
            colors: colors,
            fmt: fmtK,
          ),

          const SizedBox(height: 120),
        ],
      ),
    );
  }

  List<Widget> _buildMonthlyIncomeRows(
      BuildContext context, ThemeData theme, ElevoColors colors, NumberFormat fmt) {
    final records = _monthRent(context);
    if (records.isEmpty) {
      return [_EmptyLineItem(message: 'No confirmed rent payments for this month.', colors: colors, theme: theme)];
    }
    return records.map((r) => _IncomeRow(record: r, fmt: fmt, theme: theme, colors: colors)).toList();
  }

  List<Widget> _buildAnnualIncomeRows(
      BuildContext context, ThemeData theme, ElevoColors colors, NumberFormat fmt) {
    final map = <String, double>{};
    for (final r in _yearRent(context)) {
      map[r.unitLabel] = (map[r.unitLabel] ?? 0) + r.amount;
    }
    if (map.isEmpty) {
      return [_EmptyLineItem(message: 'No confirmed rent payments for this year.', colors: colors, theme: theme)];
    }
    return map.entries
        .map((e) => _IncomeAnnualRow(
              unitLabel: e.key,
              total: e.value,
              fmt: fmt,
              theme: theme,
              colors: colors,
            ))
        .toList();
  }

  void _showAddExpenseSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddExpenseSheet(
        initialMonth: _selectedMonth,
        initialYear: _selectedYear,
        onSave: (expense) { _persistExpense(expense); },
      ),
    );
  }

  String _monthName(int m) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[m - 1];
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  final bool isAnnual;
  final ValueChanged<bool> onChanged;

  const _PeriodToggle({required this.isAnnual, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.taupe.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleChip(label: 'Monthly', selected: !isAnnual, onTap: () => onChanged(false)),
          _ToggleChip(label: 'Annual',  selected: isAnnual,  onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ElevoColors>()!;
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.shade : colors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  final int selectedMonth;
  final int selectedYear;
  final void Function(int month, int year) onChanged;

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];

  const _MonthSelector({
    required this.selectedMonth,
    required this.selectedYear,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: selectedMonth,
            decoration: InputDecoration(
              labelText: 'Month',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefixIcon: Icon(LucideIcons.calendar, color: colors.sage, size: 16),
            ),
            dropdownColor: colors.card,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
            items: List.generate(12, (i) => DropdownMenuItem(
              value: i + 1,
              child: Text(_months[i], style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink)),
            )),
            onChanged: (v) { if (v != null) onChanged(v, selectedYear); },
          ),
        ),
        const SizedBox(width: AppTheme.spacingSm),
        SizedBox(
          width: 100,
          child: DropdownButtonFormField<int>(
            value: selectedYear,
            decoration: const InputDecoration(labelText: 'Year', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            dropdownColor: colors.card,
            style: TextStyle(color: AppTheme.elevoColors.charcoal, fontSize: 14),
            items: [2023, 2024, 2025, 2026].map((y) => DropdownMenuItem(
              value: y,
              child: Text('$y', style: TextStyle(color: AppTheme.elevoColors.charcoal)),
            )).toList(),
            onChanged: (v) { if (v != null) onChanged(selectedMonth, v); },
          ),
        ),
      ],
    );
  }
}

class _YearSelector extends StatelessWidget {
  final int selectedYear;
  final ValueChanged<int> onChanged;

  const _YearSelector({required this.selectedYear, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<int>(
        value: selectedYear,
        decoration: InputDecoration(labelText: 'Year', prefixIcon: Icon(LucideIcons.calendar, color: colors.sage, size: 16)),
        dropdownColor: colors.card,
        style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
        items: [2023, 2024, 2025, 2026].map((y) => DropdownMenuItem(
          value: y,
          child: Text('$y', style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink)),
        )).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String prefix;

  const _SummaryTile({required this.label, required this.value, required this.color, this.prefix = ''});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('$prefix$value', style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionHeader({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      Text(label, style: theme.textTheme.titleSmall?.copyWith(color: color)),
    ]);
  }
}

class _EmptyLineItem extends StatelessWidget {
  final String message;
  final ElevoColors colors;
  final ThemeData theme;

  const _EmptyLineItem({required this.message, required this.colors, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: AppTheme.surfaceCard(colors, shadow: false),
      child: Text(message, style: theme.textTheme.bodySmall),
    );
  }
}

class _IncomeRow extends StatelessWidget {
  final _RentRecord record;
  final NumberFormat fmt;
  final ThemeData theme;
  final ElevoColors colors;

  const _IncomeRow({required this.record, required this.fmt, required this.theme, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingXs),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm + 4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border(left: BorderSide(color: colors.successGreen, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(LucideIcons.home, color: colors.successGreen, size: 14),
          const SizedBox(width: 10),
          // Unit label column — fixed width so it never crowds the amount
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.unitLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  record.tenantName,
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.sage),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Spacer(),
          // Amount pinned to the right, always aligned
          Text(
            fmt.format(record.amount),
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.successGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeAnnualRow extends StatelessWidget {
  final String unitLabel;
  final double total;
  final NumberFormat fmt;
  final ThemeData theme;
  final ElevoColors colors;

  const _IncomeAnnualRow({required this.unitLabel, required this.total, required this.fmt, required this.theme, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingXs),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm + 2),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border(left: BorderSide(color: colors.successGreen, width: 2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.home, color: colors.successGreen, size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(unitLabel, style: theme.textTheme.bodyMedium)),
          Text(fmt.format(total), style: theme.textTheme.titleSmall?.copyWith(color: colors.successGreen)),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final NumberFormat fmt;
  final ThemeData theme;
  final ElevoColors colors;
  final VoidCallback onDelete;

  const _ExpenseRow({required this.expense, required this.fmt, required this.theme, required this.colors, required this.onDelete});

  Color _catColor(ExpenseCategory c) {
    switch (c) {
      case ExpenseCategory.hoaFee:      return colors.warningAmber;
      case ExpenseCategory.repair:      return colors.urgentRed;
      case ExpenseCategory.insurance:   return colors.taupe;
      case ExpenseCategory.taxes:       return colors.gold;
      case ExpenseCategory.maintenance: return colors.warningAmber;
      case ExpenseCategory.appliances:  return colors.midnight;
      default:                          return colors.taupe;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingXs),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm + 2),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border(left: BorderSide(color: _catColor(expense.category), width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(expense.description, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              Row(children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _catColor(expense.category).withAlpha(20), borderRadius: BorderRadius.circular(4)),
                  child: Text(expense.category.label, style: TextStyle(color: _catColor(expense.category), fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text(DateFormat('MMM d').format(expense.date), style: theme.textTheme.labelSmall),
              ]),
            ]),
          ),
          Text(fmt.format(expense.amount), style: theme.textTheme.titleSmall?.copyWith(color: colors.urgentRed)),
          IconButton(
            icon: Icon(LucideIcons.trash2, color: colors.taupe, size: 16),
            onPressed: () {
              HapticFeedback.lightImpact();
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Expense'),
                  content: Text('Delete "${expense.description}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () { Navigator.pop(ctx); onDelete(); },
                      child: Text('Delete', style: TextStyle(color: colors.urgentRed)),
                    ),
                  ],
                ),
              );
            },
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  final List<Expense> expenses;
  final double total;
  final ThemeData theme;
  final ElevoColors colors;
  final NumberFormat fmt;

  const _CategoryBreakdown({required this.expenses, required this.total, required this.theme, required this.colors, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final map = <ExpenseCategory, double>{};
    for (final e in expenses) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: AppTheme.surfaceCard(colors, shadow: false),
        child: Text('No expenses to break down.', style: theme.textTheme.bodySmall),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: AppTheme.surfaceCard(colors, shadow: false),
      child: Column(
        children: sorted.map((entry) {
          final pct = total > 0 ? entry.value / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
            child: Row(
              children: [
                SizedBox(width: 110, child: Text(entry.key.label, style: theme.textTheme.bodySmall)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: colors.stone,
                      valueColor: AlwaysStoppedAnimation(colors.gold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: Text(fmt.format(entry.value), style: theme.textTheme.labelSmall, textAlign: TextAlign.right),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AddExpenseSheet extends StatefulWidget {
  final int initialMonth;
  final int initialYear;
  final ValueChanged<Expense> onSave;

  const _AddExpenseSheet({required this.initialMonth, required this.initialYear, required this.onSave});

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _descCtrl   = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _otherCtrl  = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.repair;
  String? _propertyId;
  late DateTime _date;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime(widget.initialYear, widget.initialMonth, 1);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spacingMd, right: AppTheme.spacingMd,
          top: AppTheme.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: AppTheme.spacingLg),
                  decoration: BoxDecoration(color: colors.taupe.withAlpha(80), borderRadius: BorderRadius.circular(2)))),
              Text('Add Expense', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppTheme.spacingMd),
              TextFormField(controller: _descCtrl, decoration: InputDecoration(labelText: 'Description *', prefixIcon: Icon(LucideIcons.pencil, color: colors.taupe, size: 18))),
              const SizedBox(height: AppTheme.spacingMd),
              TextFormField(controller: _amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Amount *', prefixText: '\$', prefixIcon: Icon(LucideIcons.dollarSign, color: colors.taupe, size: 18))),
              const SizedBox(height: AppTheme.spacingMd),
              DropdownButtonFormField<ExpenseCategory>(
                value: _category,
                decoration: InputDecoration(labelText: 'Category', prefixIcon: Icon(LucideIcons.tag, color: colors.sage, size: 18)),
                // Light ivory dropdown so charcoal/navy text is readable
                dropdownColor: colors.card,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                items: ExpenseCategory.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.label, style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _category = v ?? ExpenseCategory.repair;
                  if (_category != ExpenseCategory.other) _otherCtrl.clear();
                }),
              ),
              // Show a "Please specify" text box when Other is selected
              if (_category == ExpenseCategory.other) ...[
                const SizedBox(height: AppTheme.spacingMd),
                TextFormField(
                  controller: _otherCtrl,
                  decoration: InputDecoration(
                    labelText: 'Please specify *',
                    hintText: 'e.g. Pest control, cleaning fee…',
                    prefixIcon: Icon(LucideIcons.pencil, color: colors.sage, size: 18),
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.spacingMd),
              DropdownButtonFormField<String?>(
                value: _propertyId,
                decoration: InputDecoration(labelText: 'Property (optional)', prefixIcon: Icon(LucideIcons.building2, color: colors.sage, size: 18)),
                // Light ivory dropdown so charcoal/navy text is readable
                dropdownColor: colors.card,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                items: [
                  DropdownMenuItem(value: null, child: Text('All Properties', style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink))),
                  ...context.read<DashboardProvider>().properties.map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink)),
                      )),
                ],
                onChanged: (v) => setState(() => _propertyId = v),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (picked != null) setState(() => _date = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: colors.stone),
                  ),
                  child: Row(children: [
                    Icon(LucideIcons.calendar, color: colors.sage, size: 18),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('MMMM d, y').format(_date),
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: AppTheme.spacingLg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : () async {
                    final desc        = _descCtrl.text.trim();
                    final amount      = double.tryParse(_amountCtrl.text.trim());
                    final otherDetail = _otherCtrl.text.trim();
                    if (desc.isEmpty || amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description and valid amount.')));
                      return;
                    }
                    if (_category == ExpenseCategory.other && otherDetail.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify what this Other expense is.')));
                      return;
                    }
                    // Append the "Other" detail to the description so it appears in reports
                    final finalDesc = _category == ExpenseCategory.other
                        ? '$desc ($otherDetail)'
                        : desc;
                    HapticFeedback.lightImpact();
                    setState(() => _isSaving = true);
                    await Future.delayed(const Duration(milliseconds: 600));
                    final expense = Expense(id: 'e_${DateTime.now().millisecondsSinceEpoch}', description: finalDesc, amount: amount, category: _category, propertyId: _propertyId, date: _date);
                    if (mounted) { widget.onSave(expense); Navigator.of(context).pop(); }
                  },
                  // Icon and label intentionally unstyled — inherits white from
                  // ElevatedButtonTheme (navy bg / white fg) defined in theme.dart
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.check, size: 18),
                  label: Text(_isSaving ? 'Saving…' : 'Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RentRecord {
  final String unitLabel;
  final double amount;
  final int month;
  final int year;
  final String tenantName;
  final String propertyId;

  const _RentRecord({
    required this.unitLabel,
    required this.amount,
    required this.month,
    required this.year,
    required this.tenantName,
    required this.propertyId,
  });
}

// ── Property filter pills ─────────────────────────────────────────────────────

class _PropertyFilter extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final List<dynamic> properties;

  const _PropertyFilter({
    required this.selectedId,
    required this.onChanged,
    required this.properties,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final props  = properties;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _PropertyPill(
            label: 'All Properties',
            selected: selectedId == null,
            onTap: () => onChanged(null),
            colors: colors,
            theme: theme,
          ),
          ...props.map((p) => Padding(
                padding: const EdgeInsets.only(left: AppTheme.spacingSm),
                child: _PropertyPill(
                  label: p.name,
                  selected: selectedId == p.id,
                  onTap: () => onChanged(p.id),
                  colors: colors,
                  theme: theme,
                ),
              )),
        ],
      ),
    );
  }
}

class _PropertyPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ElevoColors colors;
  final ThemeData theme;

  const _PropertyPill({
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
        decoration: BoxDecoration(
          color: selected ? colors.olive : colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: selected ? colors.gold : colors.stone,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected ? colors.onOlive : colors.sage,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
