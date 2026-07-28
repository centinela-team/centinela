# Matriz de roles y permisos — Centinela

## Roles

| Rol | Función de negocio |
|---|---|
| Analista de fraude | Consultar casos, cargar evidencia, ver explicaciones |
| Administrador | Operar infraestructura y configuración |
| Servicio | Identidad gestionada de la API / workers |
| Auditor | Solo lectura de configuración y auditoría |

## Matriz (principio de menor privilegio)

| Rol | Plano | Permiso / rol Azure | Operación del sistema que lo justifica |
|---|---|---|---|
| Servicio (MI Web App) | Datos | Storage Blob Data Contributor | Persistir transacciones crudas y evidencia |
| Servicio (MI Web App) | Datos | Azure Service Bus Data Sender | Encolar / publicar eventos de ingesta |
| Servicio (MI Web App) | Datos | Key Vault Secrets User | Leer secretos en runtime (semana 2) |
| Analista | Datos | Storage Blob Data Reader + SAS delegado | Leer evidencia temporalmente |
| Analista | Control | **Ninguno** | No modifica infraestructura |
| Auditor | Control | Reader (RG) | Inspeccionar configuración |
| Auditor | Datos | Reader donde aplique | Sin escritura |
| Administrador | Control | Contributor / Owner acotado | Aprovisionar y operar |

El rol Servicio **no** recibe `Contributor` ni permisos de crear recursos.

## Autenticación vs autorización (Centinela)

- **Autenticación** (¿quién eres?): la Web App se autentica ante Storage/Service Bus/Key Vault mediante **Managed Identity** (token Entra ID). No hay claves en el código.
- **Autorización** (¿qué puedes hacer?): Azure RBAC en el scope del recurso decide si esa identidad puede escribir blobs o enviar a la cola.

Ejemplo autenticación: `DefaultAzureCredential` obtiene un token para `https://storage.azure.com`.
Ejemplo autorización: la asignación `Storage Blob Data Contributor` sobre `stcentineladev03` permite el `upload_blob`; sin ella, la misma identidad autenticada recibe 403.

## Pruebas negativas (registrar evidencia en bitácora)

| Rol | Acción intentada | Resultado esperado |
|---|---|---|
| Analista | Modificar App Settings de la Web App | Denegado |
| Auditor | Crear un recurso en el RG | Denegado |
| Servicio (MI) | `az group create` / crear storage nuevo | Denegado |
