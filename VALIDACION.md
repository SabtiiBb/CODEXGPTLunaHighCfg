# Validación V4.1 — 1 de octubre de 2026

- Integración completa ejecutada con Windows PowerShell 5.1 y el ejecutable local
  de Codex, contra destinos temporales: aprobada.
- Vista previa con el catálogo real y PrimaryMode LunaMax: aprobada sin instalar.
- Familias detectadas: gpt-6-luna, gpt-6.1-sol, gpt-6-astra, gpt-5.6-terra.
- El catálogo de esta cuenta produce 76 agentes, incluidos roles semánticos y
  combinaciones exactas de versiones actuales y anteriores. Otra cuenta puede variar.
- Casos comprobados: conservación de principal, Luna 6 Alto/Máx, rechazo sin Luna 6,
  ambigüedad de rutas, Documentos redirigido simulado, migración V3, idempotencia,
  colisiones, rollback, restauración y pérdida de Astra.
- No se instaló esta actualización en la configuración activa durante estas pruebas.
- No se crearon tareas programadas reales ni se probó otra máquina física.

El ZIP contiene únicamente código, instrucciones y pruebas del paquete. No contiene
credenciales, sesiones, configuración personal ni una copia del catálogo de la cuenta.