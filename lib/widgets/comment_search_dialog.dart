import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'glass_container.dart';

/// Searches local day comments.
///
/// The query is split into terms on spaces. Any text wrapped in double quotes
/// (e.g. "fix front") is kept together and searched as a single phrase. A day
/// matches when its comment contains at least one of the terms (OR search).
/// Results are listed from most recent to oldest. Tapping a result pops the
/// dialog with the selected [DateTime] so the caller can navigate to it.
class CommentSearchDialog extends StatefulWidget {
  final Map<String, String> dayComments;

  const CommentSearchDialog({super.key, required this.dayComments});

  @override
  State<CommentSearchDialog> createState() => _CommentSearchDialogState();
}

class _CommentSearchDialogState extends State<CommentSearchDialog> {
  final TextEditingController _searchController = TextEditingController();

  /// Lowercased search terms (quoted phrases kept whole).
  List<String> _terms = [];

  /// Matching `dateStr -> comment` entries, most recent first.
  List<MapEntry<String, String>> _results = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Splits [query] into search terms. Text inside double quotes is kept as a
  /// single term; everything else is split on whitespace. The closing quote is
  /// optional so an in-progress phrase still searches as a whole while typing.
  List<String> _parseTerms(String query) {
    final terms = <String>[];
    final regex = RegExp(r'"([^"]*)"?|(\S+)');
    for (final match in regex.allMatches(query)) {
      final phrase = match.group(1); // quoted content
      final word = match.group(2); // bare word
      final term = (phrase ?? word ?? '').trim().toLowerCase();
      if (term.isNotEmpty) terms.add(term);
    }
    return terms;
  }

  void _onSearchChanged(String query) {
    final terms = _parseTerms(query);
    final results = <MapEntry<String, String>>[];

    if (terms.isNotEmpty) {
      widget.dayComments.forEach((dateStr, comment) {
        final lower = comment.toLowerCase();
        if (terms.any((t) => lower.contains(t))) {
          results.add(MapEntry(dateStr, comment));
        }
      });
      // Most recent first — yyyy-MM-dd sorts lexicographically by date.
      results.sort((a, b) => b.key.compareTo(a.key));
    }

    setState(() {
      _terms = terms;
      _results = results;
    });
  }

  /// Builds spans for [text], highlighting any portion that matches a term.
  List<TextSpan> _highlightSpans(String text) {
    if (_terms.isEmpty) return [TextSpan(text: text)];
    final lower = text.toLowerCase();

    // Collect every match range for every term.
    final ranges = <List<int>>[];
    for (final term in _terms) {
      var start = 0;
      while (true) {
        final idx = lower.indexOf(term, start);
        if (idx < 0) break;
        ranges.add([idx, idx + term.length]);
        start = idx + term.length;
      }
    }
    if (ranges.isEmpty) return [TextSpan(text: text)];

    // Sort by start, then merge overlapping/adjacent ranges.
    ranges.sort((a, b) => a[0].compareTo(b[0]));
    final merged = <List<int>>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r[0] <= merged.last[1]) {
        if (r[1] > merged.last[1]) merged.last[1] = r[1];
      } else {
        merged.add([r[0], r[1]]);
      }
    }

    // Emit normal spans for gaps and highlighted spans for matches.
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final r in merged) {
      if (r[0] > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, r[0])));
      }
      spans.add(
        TextSpan(
          text: text.substring(r[0], r[1]),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0x55FFD54F),
          ),
        ),
      );
      cursor = r[1];
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final formatted = DateFormat('EEEE d MMMM yyyy', 'fr').format(date);
    if (formatted.isEmpty) return formatted;
    return formatted[0].toUpperCase() + formatted.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          width: 500,
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Rechercher dans les commentaires',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Mots séparés par des espaces · "phrase exacte" entre guillemets',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ex : fix front "revue de code"',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: 12),
              if (hasQuery)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _results.isEmpty
                        ? 'Aucun jour trouvé'
                        : '${_results.length} jour${_results.length > 1 ? 's' : ''} trouvé${_results.length > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              Expanded(
                child: !hasQuery
                    ? const Center(
                        child: Text(
                          'Saisissez un mot-clé pour rechercher\ndans vos commentaires',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : _results.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun commentaire ne correspond',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(right: 12),
                        itemCount: _results.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: Colors.white10),
                        itemBuilder: (context, index) {
                          final entry = _results[index];
                          return Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              title: Text(
                                _formatDate(entry.key),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                    children: _highlightSpans(entry.value),
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Colors.white38,
                              ),
                              onTap: () => Navigator.of(
                                context,
                              ).pop(DateTime.parse(entry.key)),
                            ),
                          );
                        },
                      ),
              ),
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
    );
  }
}
