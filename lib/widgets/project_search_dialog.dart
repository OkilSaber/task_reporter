import 'dart:async';
import 'package:flutter/material.dart';
import '../services/napta_service.dart';
import 'glass_container.dart';

class ProjectSearchDialog extends StatefulWidget {
  final NaptaService naptaService;

  const ProjectSearchDialog({super.key, required this.naptaService});

  @override
  State<ProjectSearchDialog> createState() => _ProjectSearchDialogState();
}

class _ProjectSearchDialogState extends State<ProjectSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) {
        _performSearch(query.trim());
      } else {
        setState(() {
          _results = [];
          _error = null;
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await widget.naptaService.searchProjects(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
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
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Rechercher un projet Napta',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Nom du projet ou client...',
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
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white70),
                      )
                    : _error != null
                        ? Center(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.redAccent),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _results.isEmpty
                            ? Center(
                                child: Text(
                                  _searchController.text.isEmpty
                                      ? 'Commencez à taper pour rechercher'
                                      : 'Aucun résultat trouvé',
                                  style: const TextStyle(color: Colors.white38),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _results.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(color: Colors.white10),
                                itemBuilder: (context, index) {
                                  final project = _results[index];
                                  final name = project['name'] ?? '';
                                  final client = project['client_name'] ?? 'Sans client';
                                  
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      client,
                                      style: const TextStyle(color: Colors.white54),
                                    ),
                                    trailing: const Icon(Icons.add_circle_outline,
                                        color: Colors.white38),
                                    onTap: () {
                                      Navigator.of(context).pop(project);
                                    },
                                  );
                                },
                              ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fermer',
                      style: TextStyle(color: Colors.white70)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
