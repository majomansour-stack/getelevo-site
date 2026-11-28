import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/calendar_event_model.dart';
import '../../providers/dashboard_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/common/empty_state.dart';
import 'package:provider/provider.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay  = DateTime.now();
  DateTime? _selectedDay;
  bool _showList = false;
  String? _filterPropertyId; // null = all properties

  // Events loaded from provider — keyed by date (year-month-day).
  // Must NOT be final: _syncFromProvider reassigns _eventMap on every rebuild.
  late Map<DateTime, List<CalendarEvent>> _eventMap;
  late List<CalendarEvent> _allEvents;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    // Events will be loaded from DashboardProvider in build; initialize empty.
    _allEvents = [];
    _eventMap  = {};
  }

  void _syncFromProvider(List<CalendarEvent> events) {
    final sorted = List.of(events)
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
    _allEvents = sorted;
    _eventMap  = _buildEventMap(_allEvents);
  }

  Map<DateTime, List<CalendarEvent>> _buildEventMap(
      List<CalendarEvent> events) {
    final map = <DateTime, List<CalendarEvent>>{};
    for (final e in events) {
      final key = DateTime(
          e.eventDate.year, e.eventDate.month, e.eventDate.day);
      (map[key] ??= []).add(e);
    }
    return map;
  }

  List<CalendarEvent> _eventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _eventMap[key] ?? [];
  }

  List<CalendarEvent> get _selectedEvents {
    if (_selectedDay == null) return [];
    return _eventsForDay(_selectedDay!);
  }

  List<CalendarEvent> get _filteredAll {
    var list = _allEvents;
    if (_filterPropertyId != null) {
      list = list
          .where((e) => e.propertyId == _filterPropertyId)
          .toList();
    }
    return list;
  }

  Color _urgencyColor(CalendarEvent e, ElevoColors colors) {
    if (e.isCompleted) return colors.successGreen;
    final days = e.eventDate.difference(DateTime.now()).inDays;
    if (days < 0 || days <= 7) return colors.urgentRed;
    if (days <= 30) return colors.warningAmber;
    return colors.gold;
  }

  Future<void> _markComplete(CalendarEvent event) async {
    HapticFeedback.lightImpact();
    try {
      await Supabase.instance.client
          .from('calendar_events')
          .update({'is_completed': true})
          .eq('id', event.id);
      if (mounted) {
        await context.read<DashboardProvider>().loadData();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not mark that event complete.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = theme.extension<ElevoColors>()!;
    final fmt    = DateFormat('MMMM d, y');

    final dashboard  = context.watch<DashboardProvider>();
    final properties = dashboard.properties;
    _syncFromProvider(dashboard.events);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.midnight),
          onPressed: () => context.pop(),
        ),
        title: const Text('Calendar'),
        actions: [
          // List / Grid toggle
          IconButton(
            icon: Icon(
              _showList ? LucideIcons.calendarDays : LucideIcons.list,
              color: colors.midnight,
              size: 20,
            ),
            tooltip: _showList ? 'Calendar view' : 'List view',
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _showList = !_showList);
            },
          ),
          // Property filter
          PopupMenuButton<String?>(
            icon: Icon(
              LucideIcons.filter,
              color: _filterPropertyId != null
                  ? colors.gold
                  : colors.midnight,
              size: 20,
            ),
            color: colors.card,
            onSelected: (v) => setState(() => _filterPropertyId = v),
            itemBuilder: (_) => [
              PopupMenuItem<String?>(
                value: null,
                child: Text('All Properties',
                    style: theme.textTheme.bodyMedium),
              ),
              ...properties.map((p) => PopupMenuItem<String?>(
                    value: p.id,
                    child: Text(p.name,
                        style: theme.textTheme.bodyMedium),
                  )),
            ],
          ),
        ],
      ),
      body: _showList
          ? _buildListView(theme, colors, fmt)
          : _buildCalendarView(theme, colors, fmt),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          _showAddEventSheet(context, colors, theme);
        },
        child: const Icon(LucideIcons.plus),
      ),
    );
  }

  // ── Calendar grid view ─────────────────────────────────────────────────────

  Widget _buildCalendarView(
      ThemeData theme, ElevoColors colors, DateFormat fmt) {
    return Column(
      children: [
        // Filter indicator
        if (_filterPropertyId != null)
          _FilterBanner(
            label: context.read<DashboardProvider>().properties
                    .firstWhere((p) => p.id == _filterPropertyId,
                        orElse: () => context.read<DashboardProvider>().properties.first)
                    .name,
            onClear: () => setState(() => _filterPropertyId = null),
            colors: colors,
            theme: theme,
          ),

        Container(
          color: colors.card,
          child: TableCalendar<CalendarEvent>(
          firstDay: DateTime(2023),
          lastDay: DateTime(2030),
          focusedDay: _focusedDay,
          selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
          eventLoader: _eventsForDay,
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            defaultTextStyle:
                TextStyle(color: colors.ink, fontSize: 13, fontWeight: FontWeight.w500),
            weekendTextStyle:
                TextStyle(color: colors.sage, fontSize: 13, fontWeight: FontWeight.w500),
            disabledTextStyle:
                TextStyle(color: colors.sage, fontSize: 13, fontWeight: FontWeight.w400),
            selectedDecoration: BoxDecoration(
              color: colors.olive,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(
                color: colors.onOlive,
                fontWeight: FontWeight.w700,
                fontSize: 13),
            todayDecoration: BoxDecoration(
              color: colors.oliveTint,
              shape: BoxShape.circle,
            ),
            todayTextStyle:
                TextStyle(color: colors.linkOlive, fontWeight: FontWeight.w700),
            markerDecoration: BoxDecoration(
              color: colors.gold,
              shape: BoxShape.circle,
            ),
            markerSize: 5,
            markersMaxCount: 3,
            cellMargin: const EdgeInsets.all(3),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: theme.textTheme.titleMedium!.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
            leftChevronIcon:
                Icon(LucideIcons.chevronLeft, color: colors.ink, size: 18),
            rightChevronIcon:
                Icon(LucideIcons.chevronRight, color: colors.ink, size: 18),
            headerPadding:
                const EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
            decoration:
                BoxDecoration(color: colors.card),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle:
                TextStyle(color: colors.sage, fontSize: 11, fontWeight: FontWeight.w600),
            weekendStyle:
                TextStyle(color: colors.sage, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (ctx, day, events) {
              if (events.isEmpty) return const SizedBox.shrink();
              // Show up to 3 colored dots based on urgency
              final dots = events.take(3).map((e) {
                final ce = e;
                return Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: _urgencyColor(ce, AppTheme.elevoColors),
                    shape: BoxShape.circle,
                  ),
                );
              }).toList();
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: dots,
              );
            },
          ),
          onDaySelected: (selected, focused) {
            HapticFeedback.lightImpact();
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
          },
          onPageChanged: (focused) =>
              setState(() => _focusedDay = focused),
        ),
        ), // end midnight Container

        Divider(color: colors.stone.withAlpha(60), height: 1),

        // Selected day events
        Expanded(
          child: _selectedEvents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.calendarCheck,
                          color: colors.taupe, size: 36),
                      const SizedBox(height: AppTheme.spacingMd),
                      Text(
                        'No events on ${fmt.format(_selectedDay ?? DateTime.now())}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.taupe),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  itemCount: _selectedEvents.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppTheme.spacingSm),
                  itemBuilder: (ctx, i) => _EventTile(
                    event: _selectedEvents[i],
                    urgencyColor: _urgencyColor(
                        _selectedEvents[i], colors),
                    theme: theme,
                    colors: colors,
                    onMarkComplete: () =>
                        _markComplete(_selectedEvents[i]),
                  ),
                ),
        ),
      ],
    );
  }

  // ── List view grouped by property ──────────────────────────────────────────

  Widget _buildListView(
      ThemeData theme, ElevoColors colors, DateFormat fmt) {
    final events = _filteredAll;

    if (events.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.calendarCheck,
        message: 'No upcoming events — all clear!',
      );
    }

    // Group by property name
    final grouped = <String, List<CalendarEvent>>{};
    for (final e in events) {
      final key = e.propertyName ?? 'General';
      (grouped[key] ??= []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      children: [
        // Filter indicator
        if (_filterPropertyId != null)
          _FilterBanner(
            label: context.read<DashboardProvider>().properties
                    .firstWhere((p) => p.id == _filterPropertyId,
                        orElse: () => context.read<DashboardProvider>().properties.first)
                    .name,
            onClear: () => setState(() => _filterPropertyId = null),
            colors: colors,
            theme: theme,
          ),

        ...grouped.entries.expand((entry) => [
              // Property section header
              Padding(
                padding: const EdgeInsets.only(
                    top: AppTheme.spacingMd,
                    bottom: AppTheme.spacingSm),
                child: Row(
                  children: [
                    Icon(LucideIcons.building2,
                        color: colors.gold, size: 14),
                    const SizedBox(width: 6),
                    Text(entry.key,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: colors.goldInk)),
                    const SizedBox(width: AppTheme.spacingSm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.gold.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${entry.value.length}',
                          style: TextStyle(
                              color: colors.gold,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              ...entry.value.map((e) => Padding(
                    padding: const EdgeInsets.only(
                        bottom: AppTheme.spacingSm),
                    child: _EventTile(
                      event: e,
                      urgencyColor: _urgencyColor(e, colors),
                      theme: theme,
                      colors: colors,
                      onMarkComplete: () => _markComplete(e),
                      showDate: true,
                      fmt: fmt,
                    ),
                  )),
            ]),
        const SizedBox(height: 80),
      ],
    );
  }

  // ── Add event bottom sheet ─────────────────────────────────────────────────

  void _showAddEventSheet(
      BuildContext context, ElevoColors colors, ThemeData theme) {
    final titleCtrl = TextEditingController();
    DateTime selectedDate = _selectedDay ?? DateTime.now();
    bool isSaving = false;

    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: AppTheme.spacingMd,
                right: AppTheme.spacingMd,
                top: AppTheme.spacingLg,
                bottom: MediaQuery.of(ctx).viewInsets.bottom +
                    AppTheme.spacingLg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(
                            bottom: AppTheme.spacingLg),
                        decoration: BoxDecoration(
                          color: colors.stone.withAlpha(120),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text('Add Calendar Event',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppTheme.spacingMd),
                    TextFormField(
                      controller: titleCtrl,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                      decoration: const InputDecoration(
                          labelText: 'Event Title *'),
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                    // Date picker — OutlinedButton so it gets the proper tap treatment
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: colors.card,
                        foregroundColor: colors.ink,
                        minimumSize: const Size(double.infinity, 52),
                        side: BorderSide(color: colors.stone),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.calendar,
                              color: colors.midnight, size: 18),
                          const SizedBox(width: 12),
                          Text(
                            DateFormat('MMMM d, y').format(selectedDate),
                            style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingLg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final title = titleCtrl.text.trim();
                                if (title.isEmpty) return;
                                HapticFeedback.lightImpact();
                                setSheetState(() => isSaving = true);
                                try {
                                  final db = Supabase.instance.client;
                                  final uid = db.auth.currentUser?.id;
                                  if (uid == null) throw Exception('Not signed in');

                                  await db.from('calendar_events').insert({
                                    'landlord_id': uid,
                                    'title': title,
                                    'start_date': selectedDate.toIso8601String(),
                                    'type': 'other',
                                  }).select();

                                  if (ctx.mounted) Navigator.pop(ctx);
                                  await context.read<DashboardProvider>().loadData();
                                  if (mounted) {
                                    setState(() {
                                      _selectedDay = selectedDate;
                                      _focusedDay = selectedDate;
                                    });
                                  }
                                  messenger.showSnackBar(
                                    SnackBar(content: Text("'$title' added to calendar.")),
                                  );
                                } catch (e) {
                                  setSheetState(() => isSaving = false);
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Could not save event: ${e.toString()}')),
                                  );
                                }
                              },
                        icon: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(LucideIcons.calendarPlus,
                                size: 18, color: Colors.white),
                        label: Text(isSaving ? 'Saving…' : 'Add Event'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Event tile ────────────────────────────────────────────────────────────────

class _EventTile extends StatelessWidget {
  final CalendarEvent event;
  final Color urgencyColor;
  final ThemeData theme;
  final ElevoColors colors;
  final VoidCallback onMarkComplete;
  final bool showDate;
  final DateFormat? fmt;

  const _EventTile({
    required this.event,
    required this.urgencyColor,
    required this.theme,
    required this.colors,
    required this.onMarkComplete,
    this.showDate = false,
    this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: colors.stone),
      ),
      child: Row(
        children: [
          // Urgency dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: urgencyColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppTheme.spacingMd),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: event.isCompleted
                        ? colors.sage
                        : colors.ink,
                    decoration: event.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (event.subtitle != null)
                  Text(event.subtitle!,
                      style: theme.textTheme.labelSmall),
                if (showDate && fmt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(LucideIcons.calendar,
                            size: 11, color: colors.taupe),
                        const SizedBox(width: 4),
                        Text(fmt!.format(event.eventDate),
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Mark complete button
          if (!event.isCompleted)
            GestureDetector(
              onTap: onMarkComplete,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.successGreen.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: colors.successGreen.withAlpha(60)),
                ),
                child: Icon(LucideIcons.check,
                    color: colors.successGreen, size: 14),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.successGreen.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(LucideIcons.checkCheck,
                  color: colors.successGreen, size: 14),
            ),
        ],
      ),
    );
  }
}

// ── Filter banner ─────────────────────────────────────────────────────────────

class _FilterBanner extends StatelessWidget {
  final String label;
  final VoidCallback onClear;
  final ElevoColors colors;
  final ThemeData theme;

  const _FilterBanner({
    required this.label,
    required this.onClear,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd, vertical: AppTheme.spacingSm),
      decoration: BoxDecoration(
        color: colors.gold.withAlpha(15),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: colors.gold.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.filter, color: colors.gold, size: 14),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Text(
              'Showing: $label',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.goldInk),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(LucideIcons.x, color: colors.gold, size: 14),
          ),
        ],
      ),
    );
  }
}
