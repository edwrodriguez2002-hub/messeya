import 'package:flutter/material.dart';

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({
    super.key,
    required this.documentType,
  });

  final String documentType;

  @override
  Widget build(BuildContext context) {
    final content = _contentFor(documentType);

    return Scaffold(
      appBar: AppBar(title: Text(content.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            content.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            content.updatedAt,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 20),
          for (final section in content.sections) ...[
            Text(
              section.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              section.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  _LegalContent _contentFor(String type) {
    switch (type) {
      case 'terms':
        return const _LegalContent(
          title: 'Terminos y condiciones',
          updatedAt: 'Ultima actualizacion: 13 de marzo de 2026',
          sections: [
            _LegalSection(
              title: 'Uso aceptable',
              body:
                  'Messeya es una plataforma de mensajeria para comunicaciones personales y profesionales. No se permite enviar contenido ilegal, fraudulento, violento, acosador o que vulnere derechos de terceros.',
            ),
            _LegalSection(
              title: 'Cuenta y seguridad',
              body:
                  'Cada usuario es responsable de mantener el control de su cuenta, la confidencialidad de sus credenciales y la actividad realizada desde su sesion.',
            ),
            _LegalSection(
              title: 'Suspension de cuentas',
              body:
                  'La aplicacion puede limitar funciones, bloquear contactos o suspender cuentas que infrinjan estas condiciones o generen riesgo para la comunidad.',
            ),
          ],
        );
      case 'community':
        return const _LegalContent(
          title: 'Normas de comunidad',
          updatedAt: 'Ultima actualizacion: 13 de marzo de 2026',
          sections: [
            _LegalSection(
              title: 'Respeto',
              body:
                  'No se tolera el acoso, la intimidacion, la suplantacion de identidad ni el contenido sexual no solicitado.',
            ),
            _LegalSection(
              title: 'Privacidad',
              body:
                  'Comparte solo informacion que tengas derecho a enviar. No publiques datos privados de otras personas sin su consentimiento.',
            ),
            _LegalSection(
              title: 'Reportes y bloqueos',
              body:
                  'Los usuarios pueden bloquear contactos y limitar interacciones no deseadas. Las denuncias reiteradas pueden derivar en restricciones de cuenta.',
            ),
          ],
        );
      default:
        return const _LegalContent(
          title: 'Politica de privacidad',
          updatedAt: 'Ultima actualizacion: 13 de marzo de 2026',
          sections: [
            _LegalSection(
              title: 'Datos que recopilamos',
              body:
                  'Messeya almacena datos de perfil, identificadores de cuenta, mensajes, estados, registros de llamadas y archivos compartidos necesarios para operar la app.',
            ),
            _LegalSection(
              title: 'Uso de la informacion',
              body:
                  'La informacion se utiliza para autenticar usuarios, sincronizar conversaciones, mostrar perfiles, permitir funciones de seguridad y mejorar la experiencia del servicio.',
            ),
            _LegalSection(
              title: 'Control del usuario',
              body:
                  'Puedes editar tu perfil, bloquear contactos, cambiar ajustes de notificaciones y controlar la visibilidad de ciertas funciones desde configuracion.',
            ),
            _LegalSection(
              title: 'Seguridad y retencion',
              body:
                  'Aplicamos reglas de acceso en Firebase y conservamos la informacion operativa mientras la cuenta siga activa o sea necesaria para la prestacion del servicio.',
            ),
          ],
        );
    }
  }
}

class _LegalContent {
  const _LegalContent({
    required this.title,
    required this.updatedAt,
    required this.sections,
  });

  final String title;
  final String updatedAt;
  final List<_LegalSection> sections;
}

class _LegalSection {
  const _LegalSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}
