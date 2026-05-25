import 'package:flutter/material.dart';
import '../models/category.dart';
import 'glass_container.dart';

class DayCell extends StatelessWidget {
  final DateTime date;
  final bool isCurrentMonth;
  final bool isToday;
  final Map<String, double> dayRecords; // Category ID -> Value
  final List<Category> categories;
  final String? dayComment;
  final Function(Map<String, double>, String) onChanged;
  final String? status;
  final String? highlightedCategoryId;

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
    this.highlightedCategoryId,
  });

  @override
  Widget build(BuildContext context) {
    double totalValue = dayRecords.values.fold(0, (sum, val) => sum + val);
    final isLocked = status == 'validated';
    final hasStatus = status != null && status != 'prefilled';
    final isWeekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    final isClickable = !isWeekend;

    return MouseRegion(
      cursor: isClickable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: !isClickable
            ? null
            : () {
                if (isLocked) {
                  _showValidatedDayDialog(context);
                } else {
                  _showValuePicker(context);
                }
              },
        child: GlassContainer(
          blur: 10,
          opacity: isWeekend ? 0.03 : (isToday ? 0.3 : 0.1),
          isHighlighted: isToday,
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              if (isWeekend)
                Positioned.fill(
                  child: CustomPaint(
                    painter: WeekendPainter(),
                  ),
                ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: _buildStackedBars(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.w500,
                            color: isCurrentMonth
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        Row(
                          children: [
                            if (hasStatus)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _buildStatusIcon(status!),
                              ),
                            if (dayComment != null && dayComment!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: const Tooltip(
                                  message: 'Un commentaire est disponible',
                                  child: Icon(
                                    Icons.sticky_note_2_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            if (isToday)
                              Container(
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
                      ],
                    ),
                    const Spacer(),
                    if (totalValue > 0)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(
                          '${totalValue.toStringAsFixed(2)} JH',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStackedBars() {
    List<Widget> bars = [];
    double totalFlex = 1.0;
    double currentUsed = 0.0;

    for (var cat in categories) {
      final val = dayRecords[cat.id] ?? 0.0;
      if (val > 0) {
        currentUsed += val;
      }
    }

    double remaining = totalFlex - currentUsed;
    if (remaining > 0) {
      bars.add(Flexible(
        flex: (remaining * 100).toInt(),
        child: Container(color: Colors.transparent),
      ));
    }

    final hasHighlight = highlightedCategoryId != null;
    for (var cat in categories) {
      final val = dayRecords[cat.id] ?? 0.0;
      if (val > 0) {
        final isHighlighted = cat.id == highlightedCategoryId;
        final alpha = hasHighlight ? (isHighlighted ? 1.0 : 0.15) : 0.7;
        bars.add(Flexible(
          flex: (val * 100).toInt(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            color: cat.color.withValues(alpha: alpha),
          ),
        ));
      }
    }

    if (bars.isEmpty) {
      bars.add(const Spacer());
    }

    return bars;
  }

  Widget _buildStatusIcon(String status) {
    IconData icon;
    Color color;
    String label;

    switch (status) {
      case 'validated':
        icon = Icons.verified_rounded;
        color = Colors.greenAccent.withValues(alpha: 0.8);
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
        color = Colors.white70;
        label = 'Enregistré (Brouillon)';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Tooltip(
      message: label,
      child: Icon(icon, color: color, size: 16),
    );
  }

  void _showValuePicker(BuildContext context) {
    // Separate editable from locked categories that have a value today
    final editableCats = categories.where((c) => !c.isLocked).toList();
    final lockedCats = categories.where((c) => c.isLocked).toList();
    final hasLockedValues = lockedCats.any(
      (c) => (dayRecords[c.id] ?? 0) > 0,
    );
    final hasEditableSlots = editableCats.isNotEmpty;

    // If there are no editable categories and the day only has locked entries,
    // show a simple read-only info dialog.
    if (!hasEditableSlots || (!hasEditableSlots && hasLockedValues)) {
      if (hasLockedValues) {
        _showLockedInfoDialog(context, lockedCats);
        return;
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return _ValuePickerDialog(
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

  void _showValidatedDayDialog(BuildContext context) {
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
                const SizedBox(height: 16),
                ...filledCats.map((c) => Padding(
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
                    )),
                if (dayComment != null && dayComment!.isNotEmpty) ...[
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
                      dayComment!,
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

  void _showLockedInfoDialog(BuildContext context, List<Category> locked) {
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
                const SizedBox(height: 16),
                ...locked
                    .where((c) => (dayRecords[c.id] ?? 0) > 0)
                    .map((c) => Padding(
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
                        )),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fermer',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ValuePickerDialog extends StatefulWidget {
  final Map<String, double> initialRecords;
  final String initialComment;
  final List<Category> categories;
  final Function(Map<String, double>, String) onSelected;

  const _ValuePickerDialog({
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

  @override
  Widget build(BuildContext context) {
    final locked = widget.categories.where((c) => c.isLocked).toList();
    final editable = widget.categories
        .where((c) =>
            !c.isLocked &&
            (!c.isHidden || (_currentRecords[c.id] ?? 0) > 0))
        .toList()
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return 0;
      });

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          width: 650,
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Définir les valeurs (Jours-Homme)',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Total : ${_total.toStringAsFixed(2)} JH',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _total > 1.0 ? Colors.redAccent : Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(right: 12),
                  children: [
                    // ── Locked (read-only) entries ──────────────────────
                    ...locked
                        .where((c) => (_currentRecords[c.id] ?? 0) > 0)
                        .map((cat) => _buildLockedRow(cat)),

                    // Separator if there are both locked and editable entries
                    if (locked.any((c) => (_currentRecords[c.id] ?? 0) > 0) &&
                        editable.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(color: Colors.white24),
                      ),

                    // ── Editable entries (sliders) ──────────────────────
                    ...editable.map((cat) => _buildEditableRow(cat)),

                    const SizedBox(height: 24),
                    const Text(
                      'Commentaire (Local)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _commentController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ajouter une note...',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler',
                        style: TextStyle(color: Colors.white70)),
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
    );
  }

  Widget _buildLockedRow(Category cat) {
    final val = _currentRecords[cat.id] ?? 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: cat.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.lock_rounded, size: 12, color: Colors.white38),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              cat.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(width: 8),
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

  Widget _buildEditableRow(Category cat) {
    final val = _currentRecords[cat.id] ?? 0.0;
    final controller = _valueControllers[cat.id]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: cat.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            if (cat.isFavorite) ...[
              const Icon(Icons.star, size: 14, color: Colors.amberAccent),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                cat.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.end,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  suffixText: ' JH',
                  suffixStyle:
                      const TextStyle(color: Colors.white38, fontSize: 10),
                  enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: UnderlineInputBorder(
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
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: cat.color,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            thumbColor: Colors.white,
            valueIndicatorTextStyle: const TextStyle(color: Colors.black),
          ),
          child: Slider(
            value: val.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: val.toStringAsFixed(2),
            onChanged: (newVal) {
              setState(() {
                _currentRecords[cat.id] = newVal;
                controller.text = newVal.toStringAsFixed(2);
              });
            },
          ),
        ),
      ],
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
