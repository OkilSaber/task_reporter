import 'package:flutter/material.dart';
import '../models/category.dart';
import '../services/napta_service.dart';
import 'glass_container.dart';
import 'marquee_text.dart';
import 'project_search_dialog.dart';

class CategoryManagerDialog extends StatefulWidget {
  final List<Category> categories;
  final NaptaService naptaService;
  final ValueChanged<List<Category>> onCategoriesChanged;

  const CategoryManagerDialog({
    super.key,
    required this.categories,
    required this.naptaService,
    required this.onCategoriesChanged,
  });

  @override
  State<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<CategoryManagerDialog> {
  late List<Category> _localCategories;

  final List<Color> _availableColors = const [
    Color(0xFF4FC3F7), // light blue
    Color(0xFF1976D2), // strong blue
    Color(0xFF26A69A), // teal
    Color(0xFF81C784), // light green
    Color(0xFF388E3C), // dark green
    Color(0xFFFFD54F), // amber
    Color(0xFFD32F2F), // deep red
    Color(0xFFAD1457), // dark pink
    Color(0xFFBA68C8), // purple
    Color(0xFF7E57C2), // deep purple
    Color(0xFF5D4037), // brown
    Color(0xFF263238), // near-black
  ];

  @override
  void initState() {
    super.initState();
    _localCategories = widget.categories
        .map((c) => Category(
              id: c.id,
              name: c.name,
              color: c.color,
              isLocked: c.isLocked,
              isHidden: c.isHidden,
              isFavorite: c.isFavorite,
            ))
        .toList();
    _sortCategories();
  }

  // Favorites first, keeping the user-defined order within each group
  // (List.sort isn't stable, so partition instead).
  void _sortCategories() {
    final sorted = [
      ..._localCategories.where((c) => c.isFavorite),
      ..._localCategories.where((c) => !c.isFavorite),
    ];
    _localCategories
      ..clear()
      ..addAll(sorted);
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final cat = _localCategories.removeAt(oldIndex);
      _localCategories.insert(newIndex, cat);
      // A category dropped across the favorites boundary snaps back to its group.
      _sortCategories();
    });
  }

  // Width needed to show the longest name without truncation, clamped between
  // a minimum and 60% of the window width.
  double _dialogWidth(BuildContext context, TextStyle nameStyle) {
    double longest = 0;
    for (final cat in _localCategories) {
      final painter = TextPainter(
        text: TextSpan(
          text: cat.name,
          style: cat.isLocked
              ? nameStyle.copyWith(fontStyle: FontStyle.italic)
              : nameStyle,
        ),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width > longest) longest = painter.width;
      painter.dispose();
    }
    // Drag handle + color dot + gaps + 3 icon buttons + list padding + slack.
    const rowChrome = 24 + 8 + 24 + 16 + 3 * 48 + 12 + 8;
    // The GlassContainer adds 24px padding on each side around this box.
    final maxWidth = MediaQuery.of(context).size.width * 0.6 - 48;
    const minWidth = 500.0;
    if (maxWidth <= minWidth) return maxWidth;
    return (longest + rowChrome).clamp(minWidth, maxWidth);
  }

  Future<void> _addCategory() async {
    final Map<String, dynamic>? selectedProject = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProjectSearchDialog(naptaService: widget.naptaService),
    );

    if (selectedProject != null && mounted) {
      final id = 'napta_${selectedProject['id']}';
      
      // Don't add if already exists
      if (_localCategories.any((c) => c.id == id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cette catégorie existe déjà.')),
        );
        return;
      }

      final prefix = selectedProject['client_name'] != null ? '${selectedProject['client_name']} – ' : '';
      setState(() {
        _localCategories.add(Category(
          id: id,
          name: '$prefix${selectedProject['name']}',
          color: _availableColors[_localCategories.length % _availableColors.length],
        ));
        _sortCategories();
      });
    }
  }

  void _toggleFavorite(int index) {
    setState(() {
      _localCategories[index].isFavorite = !_localCategories[index].isFavorite;
      _sortCategories();
    });
  }

  void _toggleHidden(int index) {
    setState(() {
      _localCategories[index].isHidden = !_localCategories[index].isHidden;
    });
  }

  void _removeCategory(int index) {
    if (_localCategories.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous devez avoir au moins une catégorie.')),
      );
      return;
    }
    setState(() {
      _localCategories.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nameStyle = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          width: _dialogWidth(context, nameStyle),
          // Cap at 85% of the available screen height
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gérer les catégories',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              // Flexible lets the list shrink/grow within the available space
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.only(right: 12),
                  itemCount: _localCategories.length,
                  onReorderItem: _reorder,
                  proxyDecorator: (child, index, animation) => Material(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    child: child,
                  ),
                  itemBuilder: (context, index) {
                    final cat = _localCategories[index];
                    final nameColor = cat.isHidden ? Colors.white38 : Colors.white;
                    return Container(
                      key: ValueKey(cat.id),
                      decoration: index < _localCategories.length - 1
                          ? const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.white24),
                              ),
                            )
                          : null,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Icon(
                                Icons.drag_indicator,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: cat.isLocked ? null : () => _showColorPicker(index),
                            child: Opacity(
                              opacity: cat.isHidden ? 0.4 : 1.0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: cat.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _CategoryNameField(
                              name: cat.name,
                              style: nameStyle.copyWith(
                                color: nameColor,
                                fontStyle: cat.isLocked ? FontStyle.italic : null,
                              ),
                              editable: !cat.isLocked,
                              onChanged: (val) => setState(() => cat.name = val),
                            ),
                          ),
                          IconButton(
                            tooltip: cat.isFavorite
                                ? 'Retirer des favoris'
                                : 'Ajouter aux favoris',
                            icon: Icon(
                              cat.isFavorite ? Icons.star : Icons.star_border,
                              color: cat.isFavorite
                                  ? Colors.amberAccent
                                  : Colors.white54,
                            ),
                            onPressed: () => _toggleFavorite(index),
                          ),
                          IconButton(
                            tooltip: cat.isHidden ? 'Afficher' : 'Masquer',
                            icon: Icon(
                              cat.isHidden
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: cat.isHidden
                                  ? Colors.white38
                                  : Colors.white54,
                            ),
                            onPressed: () => _toggleHidden(index),
                          ),
                          if (cat.isLocked)
                            const SizedBox(width: 48)
                          else
                            IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.delete, color: Colors.white54),
                              onPressed: () => _removeCategory(index),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _addCategory,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Ajouter une catégorie', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler', style: TextStyle(color: Colors.white70)),
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
                    onPressed: () {
                      widget.onCategoriesChanged(_localCategories);
                      Navigator.of(context).pop();
                    },
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

  void _showColorPicker(int categoryIndex) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: GlassContainer(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: 300,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _availableColors.map((color) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _localCategories[categoryIndex].color = color;
                      });
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Category name shown as sliding text with a full-name tooltip; clicking it
/// switches to an inline text field when the category is editable.
class _CategoryNameField extends StatefulWidget {
  final String name;
  final TextStyle style;
  final bool editable;
  final ValueChanged<String> onChanged;

  const _CategoryNameField({
    required this.name,
    required this.style,
    required this.editable,
    required this.onChanged,
  });

  @override
  State<_CategoryNameField> createState() => _CategoryNameFieldState();
}

class _CategoryNameFieldState extends State<_CategoryNameField> {
  final FocusNode _focusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _editing) setState(() => _editing = false);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return TextFormField(
        initialValue: widget.name,
        focusNode: _focusNode,
        autofocus: true,
        style: widget.style,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Nom de la catégorie',
          hintStyle: TextStyle(color: Colors.white54),
        ),
        onChanged: widget.onChanged,
        onFieldSubmitted: (_) => setState(() => _editing = false),
        onTapOutside: (_) => _focusNode.unfocus(),
      );
    }

    final text = Tooltip(
      message: widget.name,
      waitDuration: const Duration(milliseconds: 500),
      child: Padding(
        // Matches the dense TextFormField's vertical padding so the row
        // height doesn't jump when switching to edit mode.
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: MarqueeText(widget.name, style: widget.style),
      ),
    );
    if (!widget.editable) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _editing = true),
        child: text,
      ),
    );
  }
}
