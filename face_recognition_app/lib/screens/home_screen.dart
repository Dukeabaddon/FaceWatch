import 'package:flutter/material.dart';
import 'register_screen.dart';
import 'recognition_screen.dart';
import 'manage_faces_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                'FACE ID',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 11,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Facial\nRecognition',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  height: 1.15,
                ),
              ),
              const Spacer(),
              _ActionCard(
                icon: Icons.face_retouching_natural,
                title: 'Recognize',
                subtitle: 'Identify faces in real-time',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecognitionScreen()),
                ),
              ),
              const SizedBox(height: 14),
              _ActionCard(
                icon: Icons.person_add_alt_1,
                title: 'Register Face',
                subtitle: 'Add a new person to the system',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
              ),
              const SizedBox(height: 14),
              _ActionCard(
                icon: Icons.people_outline,
                title: 'Manage Faces',
                subtitle: 'View and delete registered faces',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageFacesScreen()),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.cyanAccent, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.cyanAccent.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
