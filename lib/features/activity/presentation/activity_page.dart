import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Actividad')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            'Centro v1.1',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Desde aqui puedes publicar estados, lanzar llamadas y ajustar tu perfil y configuraciones clave.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                ),
          ),
          const SizedBox(height: 20),
          _FeatureCard(
            icon: Icons.auto_awesome_motion_rounded,
            title: 'Estados',
            subtitle: 'Publica un estado de texto o imagen por 24 horas.',
            onTap: () => context.push('/statuses'),
          ),
          const SizedBox(height: 14),
          _FeatureCard(
            icon: Icons.call_rounded,
            title: 'Llamadas',
            subtitle: 'Accede al historial y crea llamadas de audio o video.',
            onTap: () => context.push('/calls'),
          ),
          const SizedBox(height: 14),
          _FeatureCard(
            icon: Icons.settings_rounded,
            title: 'Perfil y ajustes',
            subtitle:
                'Edita perfil, privacidad, notificaciones y uso de datos.',
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(18),
        leading: CircleAvatar(
          radius: 24,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
