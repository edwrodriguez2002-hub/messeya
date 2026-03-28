# Himnario Adventista

Base Flutter para una app de himnario adventista con:

- busqueda por numero, titulo o tema
- filtros por categoria
- favoritos persistentes en el dispositivo
- vista de detalle tipo lectura
- contenido local de demostracion para arrancar sin backend

## Ejecutar

```bash
flutter pub get
flutter run
```

## Estructura principal

- [lib/main.dart](C:/dev/codex1.0/lib/main.dart)
- [lib/hymnal/presentation/pages/hymnal_home_page.dart](C:/dev/codex1.0/lib/hymnal/presentation/pages/hymnal_home_page.dart)
- [lib/hymnal/presentation/pages/hymnal_detail_page.dart](C:/dev/codex1.0/lib/hymnal/presentation/pages/hymnal_detail_page.dart)
- [lib/hymnal/data/hymn_repository.dart](C:/dev/codex1.0/lib/hymnal/data/hymn_repository.dart)
- [assets/hymns/sample_hymns.json](C:/dev/codex1.0/assets/hymns/sample_hymns.json)

## Siguiente paso recomendado

Reemplazar el archivo [assets/hymns/sample_hymns.json](C:/dev/codex1.0/assets/hymns/sample_hymns.json) por un catalogo autorizado del himnario completo o conectarlo a Firebase/SQLite para agregar descargas, playlists, audio y modo sin conexion mas robusto.
