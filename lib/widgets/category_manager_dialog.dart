import 'package:flutter/material.dart';
import '../models/category.dart';
import '../services/napta_service.dart';
import 'glass_container.dart';
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

  final List<Color> _availableColors = [
    Colors.greenAccent,
    Colors.blueAccent,
    Colors.purpleAccent,
    Colors.orangeAccent,
    Colors.redAccent,
    Colors.pinkAccent,
    Colors.cyanAccent,
    Colors.yellowAccent,
  ];

  @override
  void initState() {
    super.initState();
    _localCategories = widget.categories
        .map((c) => Category(id: c.id, name: c.name, color: c.color))
        .toList();
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
      });
    }
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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          width: 500,
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
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _localCategories.length,
                  separatorBuilder: (c, i) => const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final cat = _localCategories[index];
                    return Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            _showColorPicker(index);
                          },
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
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            initialValue: cat.name,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Nom de la catégorie',
                              hintStyle: TextStyle(color: Colors.white54),
                            ),
                            onChanged: (val) {
                              cat.name = val;
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.white54),
                          onPressed: () => _removeCategory(index),
                        ),
                      ],
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
