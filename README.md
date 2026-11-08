# Annette Campuzano Online Fitness — conexión inicial con Supabase

## Qué incluye esta versión
- Inicio de sesión y registro con Supabase Auth.
- Consulta de perfil, vigencia y vencimiento de acceso.
- Vista de rutinas, alimentación y registro de progreso.
- Panel administrativo básico para listar clientas, activar/renovar 30 días y asignar rutinas y planes de alimentación.
- Conexión con el proyecto Supabase indicado por la propietaria usando únicamente Project URL y Publishable key.

## Importante: aún no publicar para clientas reales
Esta es una primera integración técnica. Antes de producción hay que:
1. Crear la primera cuenta de Annette y convertirla en administradora mediante SQL controlado.
2. Verificar en Supabase que las políticas RLS coinciden con las tablas.
3. Probar con dos cuentas distintas que una clienta no puede ver datos de otra.
4. Añadir gestión segura de altas de clientas, vídeos privados, recuperación de contraseña, consentimiento para fotos y pagos.
5. Publicar por HTTPS y configurar dominio.

## Configuración
La URL y la clave publicable están colocadas en `index.html`. Son valores públicos para cliente; nunca colocar aquí una clave `sb_secret` o `service_role`.

## Crear la primera cuenta administradora
1. Publica/abre la app y crea una cuenta con el correo de Annette.
2. En Supabase > Authentication > Users, confirma que aparece el usuario.
3. Copia el UUID de ese usuario.
4. En SQL Editor ejecuta, sustituyendo el UUID:
   `update public.profiles set role = 'admin', full_name = 'Annette Campuzano' where user_id = 'UUID-AQUI';`
5. Cierra sesión y vuelve a entrar.

No uses el botón de registro para clientas reales hasta que el flujo de altas esté definido. Para la primera prueba, crea solo cuentas de prueba.

## Estructura
- `index.html`: aplicación web conectada.
- `logo-annette-campuzano.png`: logotipo.
- `annette_supabase_setup.sql`: esquema y políticas RLS que se ejecutaron en el proyecto.
- `manifest.webmanifest` y `sw.js`: base PWA instalable.
