import 'package:flutter/material.dart';
import '../services/face_storage_service.dart';
import '../models/registered_face.dart';

class ManageFacesScreen extends StatefulWidget {
  const ManageFacesScreen({super.key});

  @override
  State<ManageFacesScreen> createState() => _ManageFacesScreenState();
}

class _ManageFacesScreenState extends State<ManageFacesScreen> {
  final FaceStorageService _storageService = FaceStorageService();
  List<RegisteredFace> _faces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _storageService.init();
    setState(() {
      _faces = _storageService.getAllFaces();
      _loading = false;
    });
  }

  Future<void> _delete(int index) async {
    final name = _faces[index].name;
    await _storageService.deleteFace(index);
    setState(() => _faces = _storageService.getAllFaces());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name removed'),
          backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        title: const Text('Clear All', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Delete all registered faces?',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.clearAll();
      setState(() => _faces = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Registered Faces (${_faces.length})',
          style: const TextStyle(fontSize: 16, letterSpacing: 1),
        ),
        elevation: 0,
        actions: [
          if (_faces.isNotEmpty)
            IconButton(
              onPressed: _confirmDeleteAll,
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : _faces.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.face_outlined, color: Colors.white12, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'No faces registered',
                        style: TextStyle(color: Colors.white38, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _faces.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final face = _faces[i];
                    return Dismissible(
                      key: ValueKey('face_$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      ),
                      onDismissed: (_) => _delete(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.12)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.cyanAccent.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  face.name.isNotEmpty
                                      ? face.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    face.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Registered ${_formatDate(face.registeredAt)}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.35),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.swipe_left,
                              color: Colors.white12,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
