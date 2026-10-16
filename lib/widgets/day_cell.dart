import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/category.dart';
import 'glass_container.dart';

class DayCell extends StatefulWidget {
  final DateTime date;
  final bool isCurrentMonth;
  final bool isToday;
  final Map<String, double> dayRecords; // Category ID -> Value
  final List<Category> categories;
  final String? dayComment;
  final Function(Map<String, double>, String) onChanged;
  final String? status;
  final ValueListenable<String?>? highlightedCategory;

  const DayCell({
    super.key,
    required this.date,
    required this.isCurrentMonth,
    required this.isToday,
    required this.dayRecords,
    required this.categories,
    required this.onChanged,
    this.dayComment,
    this.status,
    this.highlightedCategory,
  });

  @override
  State<DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<DayCell> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _isWeekend =>
      widget.date.weekday == DateTime.saturday ||
      widget.date.weekday == DateTime.sunday;

  void _open() => showDayDialog(
    context,
    date: widget.date,
    dayRecords: widget.dayRecords,
    categories: widget.categories,
    dayComment: widget.dayComment,
    status: widget.status,
    onChanged: widget.onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final total = widget.dayRecords.values.fold(0.0, (sum, val) => sum + val);
    final isWeekend = _isWeekend;
    final today = DateUtils.dateOnly(DateTime.now());
    // A past working day of the current month left empty: worth flagging.
    final isMissing =
        !isWeekend &&
        widget.isCurrentMonth &&
        total == 0 &&
        widget.date.isBefore(today);
    final isPartial = !isWeekend && total > 0 && total < 0.999;
    final isOver = total > 1.001;

    final cell = GlassContainer(
      blur: 10,
      opacity: isWeekend
          ? 0.03
          : widget.isToday
          ? 0.3
          : (_hovered ? 0.16 : 0.1),
      isHighlighted: widget.isToday,
      borderColor: isPartial || isOver
          ? (isOver ? Colors.redAccent : Colors.amberAccent).withValues(
              alpha: 0.8,
            )
          : null,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          if (isWeekend)
            Positioned.fill(child: CustomPaint(painter: WeekendPainter())),
          if (isMissing)
            Positioned.fill(
              child: CustomPaint(painter: _DashedBorderPainter()),
            ),
          if (isWeekend)
            _buildWeekendContent()
          else
            _buildContent(total, isPartial, isOver),
        ],
      ),
    );

    if (isWeekend) {
      return Opacity(opacity: widget.isCurrentMonth ? 1 : 0.4, child: cell);
    }
    return Opacity(
      opacity: widget.isCurrentMonth ? 1 : 0.4,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: _open,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: cell,
          ),
        ),
      ),
    );
  }

  Widget _buildWeekendContent() {
    final hasValues = widget.dayRecords.values.any((v) => v > 0);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.date.day}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
            ),
          ),
          const Spacer(),
          if (hasValues) _buildStrip(),
        ],
      ),
    );
  }

  Widget _buildContent(double total, bool isPartial, bool isOver) {
    final hasStatus = widget.status != null && widget.status != 'prefilled';
    final filled =
        widget.categories
            .where((c) => (widget.dayRecords[c.id] ?? 0) > 0)
            .toList()
          ..sort(
            (a, b) => (widget.dayRecords[b.id] ?? 0).compareTo(
              widget.dayRecords[a.id] ?? 0,
            ),
          );
    // Short label: distinct clients (or project when there's no client).
    final labels = <String>[];
    for (final c in filled) {
      final l = c.client ?? c.project;
      if (!labels.contains(l)) labels.add(l);
    }
    final showLabel = labels.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${widget.date.day}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: widget.isToday
                      ? FontWeight.bold
                      : FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (hasStatus)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _buildStatusIcon(widget.status!),
                ),
              if (widget.dayComment != null && widget.dayComment!.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Un commentaire est disponible',
                    child: Icon(
                      Icons.sticky_note_2_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              if (widget.isToday)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white,
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // Label lives in the flexible gap so a short cell clips it
          // instead of overflowing.
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: isPartial || isOver
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        isOver
                            ? '${total.toStringAsFixed(2)} JH'
                            : 'reste ${(1 - total).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isOver ? Colors.redAccent : Colors.amberAccent,
                        ),
                      ),
                    )
                  : showLabel
                  ? Tooltip(
                      message: filled
                          .map(
                            (c) =>
                                '${c.name} : ${widget.dayRecords[c.id]!.toStringAsFixed(2)} JH',
                          )
                          .join('\n'),
                      waitDuration: const Duration(milliseconds: 500),
                      child: Text(
                        labels.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (filled.isNotEmpty) ...[const SizedBox(height: 5), _buildStrip()],
        ],
      ),
    );
  }

  /// Thin horizontal strip split by category share of the day.
  Widget _buildStrip() {
    Widget strip(String? highlightedId) {
      final hasHighlight = highlightedId != null;
      final segments = <Widget>[];
      double used = 0;
      for (final cat in widget.categories) {
        final val = widget.dayRecords[cat.id] ?? 0.0;
        if (val <= 0) continue;
        used += val;
        final alpha = hasHighlight
            ? (cat.id == highlightedId ? 1.0 : 0.15)
            : 0.9;
        if (segments.isNotEmpty) segments.add(const SizedBox(width: 1));
        segments.add(
          Expanded(
            flex: (val * 1000).round(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              color: cat.color.withValues(alpha: alpha),
            ),
          ),
        );
      }
      if (used < 1) {
        segments.add(
          Expanded(flex: ((1 - used) * 1000).round(), child: const SizedBox()),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 6,
          color: Colors.white.withValues(alpha: 0.12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: segments,
          ),
        ),
      );
    }

    final highlighted = widget.highlightedCategory;
    if (highlighted == null) return strip(null);
    return ValueListenableBuilder<String?>(
      valueListenable: highlighted,
      builder: (context, hovered, _) => strip(hovered),
    );
  }

  Widget _buildStatusIcon(String status) {
    IconData icon;
    Color color;
    String label;

    switch (status) {
      case 'validated':
        icon = Icons.verified_rounded;
        color = Colors.greenAccent;
        label = 'Validé';
        break;
      case 'approval_pending':
        icon = Icons.schedule_rounded;
        color = Colors.white;
        label = 'En attente d\'approbation';
        break;
      case 'refused':
        icon = Icons.error_outline_rounded;
        color = Colors.redAccent;
        label = 'Refusé';
        break;
      case 'saved':
        icon = Icons.cloud_done_outlined;
        color = Colors.white;
        label = 'Enregistré (Brouillon)';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Tooltip(
      message: label,
      child: Icon(icon, color: color, size: 15),
    );
  }
}

/// Dashed rounded outline marking an empty past working day.
class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(3),
          const Radius.circular(13),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Opens the appropriate dialog for [date]: the editable value picker, or a
/// read-only view when the day is validated or only holds locked entries.
/// Shared by [DayCell] taps and external navigation (e.g. comment search).
/// Does nothing for weekend days, which are not editable.
void showDayDialog(
  BuildContext context, {
  required DateTime date,
  required Map<String, double> dayRecords,
  required List<Category> categories,
  required String? dayComment,
  required String? status,
  required void Function(Map<String, double>, String) onChanged,
}) {
  final isWeekend =
      date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  if (isWeekend) return;

  if (status == 'validated') {
    _showValidatedDayDialog(
      context,
      date: date,
      dayRecords: dayRecords,
      categories: categories,
      dayComment: dayComment,
    );
  } else {
    _showValuePicker(
      context,
      date: date,
      dayRecords: dayRecords,
      categories: categories,
      dayComment: dayComment,
      onChanged: onChanged,
    );
  }
}

/// Formats [date] as a capitalized French day label, e.g. "Lundi 16 juin 2025".
String _formatDayDate(DateTime date) {
  final formatted = DateFormat('EEEE d MMMM yyyy', 'fr').format(date);
  if (formatted.isEmpty) return formatted;
  return formatted[0].toUpperCase() + formatted.substring(1);
}

void _showValuePicker(
  BuildContext context, {
  required DateTime date,
  required Map<String, double> dayRecords,
  required List<Category> categories,
  required String? dayComment,
  required void Function(Map<String, double>, String) onChanged,
}) {
  // Separate editable from locked categories that have a value today
  final editableCats = categories.where((c) => !c.isLocked).toList();
  final lockedCats = categories.where((c) => c.isLocked).toList();
  final hasLockedValues = lockedCats.any((c) => (dayRecords[c.id] ?? 0) > 0);
  final hasEditableSlots = editableCats.isNotEmpty;

  // If there are no editable categories and the day only has locked entries,
  // show a simple read-only info dialog.
  if (!hasEditableSlots || (!hasEditableSlots && hasLockedValues)) {
    if (hasLockedValues) {
      _showLockedInfoDialog(
        context,
        date: date,
        dayRecords: dayRecords,
        locked: lockedCats,
      );
      return;
    }
  }

  showDialog(
    context: context,
    builder: (context) {
      return _ValuePickerDialog(
        date: date,
        initialRecords: dayRecords,
        initialComment: dayComment ?? '',
        categories: categories,
        onSelected: (newRecords, newComment) {
          onChanged(newRecords, newComment);
          Navigator.of(context).pop();
        },
      );
    },
  );
}

void _showValidatedDayDialog(
  BuildContext context, {
  required DateTime date,
  required Map<String, double> dayRecords,
  required List<Category> categories,
  required String? dayComment,
}) {
  final filledCats = categories
      .where((c) => (dayRecords[c.id] ?? 0) > 0)
      .toList();
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: Colors.greenAccent.withValues(alpha: 0.85),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Journée validée',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatDayDate(date),
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ...filledCats.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                            width: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          c.name,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      Text(
                        '${(dayRecords[c.id] ?? 0).toStringAsFixed(2)} JH',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (dayComment != null && dayComment.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Divider(color: Colors.white24),
                const SizedBox(height: 8),
                const Text(
                  'Commentaire',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    dayComment,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Fermer',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showLockedInfoDialog(
  BuildContext context, {
  required DateTime date,
  required Map<String, double> dayRecords,
  required List<Category> locked,
}) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, color: Colors.white54, size: 28),
              const SizedBox(height: 12),
              const Text(
                'Journée non travaillée',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDayDate(date),
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ...locked
                  .where((c) => (dayRecords[c.id] ?? 0) > 0)
                  .map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: c.color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c.name,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          Text(
                            '${(dayRecords[c.id] ?? 0).toStringAsFixed(2)} JH',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Fermer',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ValuePickerDialog extends StatefulWidget {
  final DateTime date;
  final Map<String, double> initialRecords;
  final String initialComment;
  final List<Category> categories;
  final Function(Map<String, double>, String) onSelected;

  const _ValuePickerDialog({
    required this.date,
    required this.initialRecords,
    required this.initialComment,
    required this.categories,
    required this.onSelected,
  });

  @override
  State<_ValuePickerDialog> createState() => _ValuePickerDialogState();
}

class _ValuePickerDialogState extends State<_ValuePickerDialog> {
  late Map<String, double> _currentRecords;
  late TextEditingController _commentController;
  late Map<String, TextEditingController> _valueControllers;

  @override
  void initState() {
    super.initState();
    _currentRecords = Map.from(widget.initialRecords);
    _commentController = TextEditingController(text: widget.initialComment);

    _valueControllers = {};
    for (var cat in widget.categories) {
      if (!cat.isLocked) {
        final val = _currentRecords[cat.id] ?? 0.0;
        _valueControllers[cat.id] = TextEditingController(
          text: val == 0 ? '' : val.toStringAsFixed(2),
        );
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    for (var controller in _valueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _total => _currentRecords.values.fold(0, (sum, val) => sum + val);

  void _setValue(Category cat, double value) {
    setState(() {
      _currentRecords[cat.id] = value;
      _valueControllers[cat.id]!.text = value == 0
          ? ''
          : value.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.categories
        .where((c) => c.isLocked && (_currentRecords[c.id] ?? 0) > 0)
        .toList();
    final visible = widget.categories.where(
      (c) => !c.isLocked && (!c.isHidden || (_currentRecords[c.id] ?? 0) > 0),
    );
    // Favorites first, keeping the user-defined order (List.sort isn't stable).
    final editable = [
      ...visible.where((c) => c.isFavorite),
      ...visible.where((c) => !c.isFavorite),
    ];
    final total = _total;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SizedBox(
            width: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        _formatDayDate(widget.date),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: total.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(
                            text: ' / 1 JH',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildGauge(total, [...locked, ...editable]),
                const SizedBox(height: 16),
                // Only the category list scrolls: total and note stay in view.
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(right: 12),
                    children: [
                      ...locked.map(_buildLockedRow),
                      if (locked.isNotEmpty && editable.isNotEmpty)
                        const Divider(color: Colors.white24, height: 16),
                      ...editable.map((cat) => _buildEditableRow(cat, total)),
                    ],
                  ),
                ),
                const Divider(color: Colors.white24, height: 32),
                const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Note personnelle',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      TextSpan(
                        text: ' · non envoyée à Napta',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  minLines: 3,
                  maxLines: 6,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ajouter une note…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => widget.onSelected(
                        _currentRecords,
                        _commentController.text,
                      ),
                      child: const Text('Enregistrer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Day gauge split by category, with what's left to place (or the excess).
  Widget _buildGauge(double total, List<Category> cats) {
    final segments = <Widget>[];
    for (final cat in cats) {
      final val = _currentRecords[cat.id] ?? 0;
      if (val <= 0) continue;
      if (segments.isNotEmpty) segments.add(const SizedBox(width: 1));
      segments.add(
        Expanded(
          flex: (val * 1000).round(),
          child: ColoredBox(color: cat.color),
        ),
      );
    }
    if (total < 1) {
      segments.add(
        Expanded(flex: ((1 - total) * 1000).round(), child: const SizedBox()),
      );
    }

    final String status;
    final Color statusColor;
    if (total > 1.001) {
      status = 'dépassement +${(total - 1).toStringAsFixed(2)}';
      statusColor = Colors.redAccent;
    } else if (total < 0.999) {
      status = 'reste ${(1 - total).toStringAsFixed(2)}';
      statusColor = Colors.amberAccent;
    } else {
      status = 'complet';
      statusColor = Colors.greenAccent;
    }

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              color: Colors.white.withValues(alpha: 0.12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: segments,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          status,
          style: TextStyle(
            color: statusColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Client on a small line above the project name.
  Widget _buildName(Category cat, {required bool dimmed}) {
    return Tooltip(
      message: cat.name,
      waitDuration: const Duration(milliseconds: 500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cat.client != null)
            Text(
              cat.client!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          Row(
            children: [
              if (cat.isLocked) ...[
                const Icon(Icons.lock_rounded, size: 12, color: Colors.white38),
                const SizedBox(width: 4),
              ],
              if (cat.isFavorite) ...[
                const Icon(Icons.star, size: 12, color: Colors.amberAccent),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  cat.project,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: dimmed ? Colors.white54 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontStyle: dimmed ? FontStyle.italic : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _buildLockedRow(Category cat) {
    final val = _currentRecords[cat.id] ?? 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _dot(cat.color),
          const SizedBox(width: 10),
          Expanded(child: _buildName(cat, dimmed: true)),
          Text(
            '${val.toStringAsFixed(2)} JH',
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableRow(Category cat, double total) {
    final val = _currentRecords[cat.id] ?? 0.0;
    final controller = _valueControllers[cat.id]!;
    // Once other categories hold part of the day, "1" becomes "reste":
    // one click completes the day to exactly 1 JH.
    final others = total - val;
    final rest = 1 - others;
    final showRest = others > 0.001 && rest > 0.001;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: val > 0
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _dot(cat.color),
          const SizedBox(width: 10),
          SizedBox(width: 210, child: _buildName(cat, dimmed: false)),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: cat.color,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: Colors.transparent,
                valueIndicatorTextStyle: const TextStyle(color: Colors.black),
              ),
              child: Slider(
                value: val.clamp(0.0, 1.0),
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: val.toStringAsFixed(2),
                onChanged: (newVal) => _setValue(cat, newVal),
              ),
            ),
          ),
          _buildPreset(cat, '¼', 0.25, val),
          _buildPreset(cat, '½', 0.5, val),
          // Fixed width so "1" and "reste" rows keep aligned sliders.
          _buildPreset(
            cat,
            showRest ? 'reste' : '1',
            showRest ? rest : 1,
            val,
            minWidth: 46,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                isDense: true,
                hintText: '—',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.15),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cat.color),
                ),
              ),
              onChanged: (text) {
                final newVal =
                    double.tryParse(text.replaceAll(',', '.')) ?? 0.0;
                setState(() {
                  _currentRecords[cat.id] = newVal;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Quick value button; clicking the active one clears the category.
  Widget _buildPreset(
    Category cat,
    String label,
    double value,
    double current, {
    double minWidth = 28,
  }) {
    final selected = current > 0 && (current - value).abs() < 0.001;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => _setValue(cat, selected ? 0 : value),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? const Color(0xFF4A1C30) : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WeekendPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    const step = 8.0;
    for (double i = -size.height; i < size.width; i += step) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
