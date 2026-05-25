import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/category.dart';
import 'day_cell.dart';

class CalendarGrid extends StatelessWidget {
  final DateTime currentMonth;
  final Map<String, Map<String, double>> dayRecords;
  final Map<String, String> dayStatuses;
  final Map<String, String> dayComments;
  final List<Category> categories;
  final String? highlightedCategoryId;
  final Function(DateTime, Map<String, double>, String) onDayDataChanged;
  final Function(DateTime) onSubmitWeek;

  const CalendarGrid({
    super.key,
    required this.currentMonth,
    required this.dayRecords,
    required this.dayStatuses,
    required this.dayComments,
    required this.categories,
    this.highlightedCategoryId,
    required this.onDayDataChanged,
    required this.onSubmitWeek,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(
      currentMonth.year,
      currentMonth.month,
    );
    final firstDayOfMonth = DateTime(currentMonth.year, currentMonth.month, 1);
    final firstWeekday = firstDayOfMonth.weekday; // 1 = Monday, 7 = Sunday

    // Calculate how many empty cells to show before the 1st of the month
    final offset = firstWeekday - 1;

    final List<Widget> cells = [];

    // Previous month's trailing days
    final prevMonth = DateTime(currentMonth.year, currentMonth.month - 1, 1);
    final daysInPrevMonth = DateUtils.getDaysInMonth(
      prevMonth.year,
      prevMonth.month,
    );

    for (int i = offset - 1; i >= 0; i--) {
      final date = DateTime(
        prevMonth.year,
        prevMonth.month,
        daysInPrevMonth - i,
      );
      cells.add(_buildCell(date, false));
    }

    // Current month days
    for (int i = 1; i <= daysInMonth; i++) {
      final date = DateTime(currentMonth.year, currentMonth.month, i);
      cells.add(_buildCell(date, true));
    }

    // Next month's leading days
    final totalCells = cells.length;
    final remainingCells = (7 - (totalCells % 7)) % 7;
    for (int i = 1; i <= remainingCells; i++) {
      final date = DateTime(currentMonth.year, currentMonth.month + 1, i);
      cells.add(_buildCell(date, false));
    }

    // Split cells into weeks (rows of 7)
    final weeks = <List<Widget>>[];
    final weekDates = <DateTime>[]; // Start date of each week
    for (int i = 0; i < cells.length; i += 7) {
      weeks.add(cells.sublist(i, i + 7));
      // Extract the date of the first day of the week
      final firstDayIdx = i - offset;
      final weekStartDate = firstDayOfMonth.add(Duration(days: firstDayIdx));
      weekDates.add(weekStartDate);
    }

    return Column(
      children: [
        // Header Row
        Row(
          children: [
            ...['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'].map(
              (day) => Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      day,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 48), // Space for the action column
          ],
        ),
        // Grid Rows
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(right: 8),
            itemCount: weeks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return Row(
                children: [
                  ...weeks[index].map(
                    (cell) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: cell,
                        ),
                      ),
                    ),
                  ),
                  // Submit Week Action
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: _buildSubmitButton(weekDates[index]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isWeekSubmitted(DateTime weekStart) {
    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      // Ignore weekends
      if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
        continue;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final status = dayStatuses[dateStr];
      if (status != 'approval_pending' && status != 'validated') {
        return false;
      }
    }
    return true;
  }

  Widget _buildSubmitButton(DateTime weekStart) {
    final isSubmitted = _isWeekSubmitted(weekStart);

    if (isSubmitted) {
      return const Tooltip(
        message: 'Semaine soumise',
        child: Icon(
          Icons.check_circle_rounded,
          color: Colors.greenAccent,
          size: 20,
        ),
      );
    }

    return Tooltip(
      message: 'Soumettre cette semaine',
      child: IconButton(
        icon: const Icon(
          Icons.send_rounded,
          color: Colors.white70,
          size: 20,
        ),
        onPressed: () => onSubmitWeek(weekStart),
      ),
    );
  }

  Widget _buildCell(DateTime date, bool isCurrentMonth) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final records = dayRecords[dateStr] ?? {};

    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    return DayCell(
      date: date,
      isCurrentMonth: isCurrentMonth,
      isToday: isToday,
      dayRecords: records,
      dayComment: dayComments[dateStr],
      status: dayStatuses[dateStr],
      categories: categories,
      highlightedCategoryId: highlightedCategoryId,
      onChanged: (newRecords, newComment) {
        onDayDataChanged(date, newRecords, newComment);
      },
    );
  }
}
