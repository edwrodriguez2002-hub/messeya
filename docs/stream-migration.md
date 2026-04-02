# Stream Chat migration

## Configuracion minima

Ejecuta la app con estas variables:

```bash
flutter run \
  --dart-define=MESSEYA_STREAM_API_KEY=tu_stream_api_key \
  --dart-define=MESSEYA_STREAM_DEV_TOKEN=true
```

Notas:

- `MESSEYA_STREAM_DEV_TOKEN=true` sirve solo para desarrollo inicial.
- En produccion se debe usar `MESSEYA_STREAM_TOKEN_PROVIDER_URL` con un backend propio que emita tokens seguros de Stream.

## Lo que ya quedo listo

- Cliente base de Stream Chat conectado al arranque de la app.
- Sincronizacion automatica con la sesion de Firebase.
- `StreamChatCore` disponible en todo el arbol de widgets.

## Siguiente migracion recomendada

1. Crear un `StreamChatsRepository` para listar canales del usuario.
2. Migrar la pantalla principal de chats para leer canales de Stream.
3. Migrar la pantalla de chat para enviar y recibir mensajes con Stream.
4. Mover push notifications al dashboard/backend de Stream.
5. Retirar la escritura directa de mensajes en Firestore.
