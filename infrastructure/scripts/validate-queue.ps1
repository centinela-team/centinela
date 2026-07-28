#Requires -Version 5.1
<#
.SYNOPSIS
  Valida escritura y lectura en la cola de ingesta (Service Bus).
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "params.ps1")

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Azure CLI (az) no está instalado."
}

Write-Host "==> Obteniendo cadena de conexión del namespace (solo para validación operativa)" -ForegroundColor Cyan
$conn = az servicebus namespace authorization-rule keys list `
  --resource-group $ResourceGroup `
  --namespace-name $ServiceBusNamespace `
  --name RootManageSharedAccessKey `
  --query primaryConnectionString -o tsv

if (-not $conn) {
  throw "No se pudo obtener la connection string. Verifica permisos."
}

$tmpDir = Join-Path $env:TEMP "centinela-queue-validate"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

# Usa Python si está disponible para send/receive con azure-servicebus
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
  Write-Host "Python no encontrado. Verifica la cola en el Portal: Service Bus > q-ingestion > Service Bus Explorer." -ForegroundColor Yellow
  Write-Host "Namespace: $ServiceBusNamespace / Queue: $QueueIngestionName"
  exit 0
}

$script = @"
import os, json, uuid
from azure.servicebus import ServiceBusClient, ServiceBusMessage

conn = os.environ['SB_CONN']
queue = os.environ['SB_QUEUE']
payload = {'probe_id': str(uuid.uuid4()), 'source': 'validate-queue.ps1'}

with ServiceBusClient.from_connection_string(conn) as client:
    with client.get_queue_sender(queue) as sender:
        sender.send_messages(ServiceBusMessage(json.dumps(payload)))
        print(f'WRITE_OK {payload[\"probe_id\"]}')
    with client.get_queue_receiver(queue, max_wait_time=10) as receiver:
        for msg in receiver:
            body = str(msg)
            receiver.complete_message(msg)
            print(f'READ_OK {body}')
            break
        else:
            raise SystemExit('READ_FAIL: no message received')
"@

$pyFile = Join-Path $tmpDir "probe.py"
Set-Content -Path $pyFile -Value $script -Encoding UTF8
$env:SB_CONN = $conn
$env:SB_QUEUE = $QueueIngestionName

Write-Host "==> Enviando y recibiendo mensaje de prueba..." -ForegroundColor Cyan
python $pyFile
if ($LASTEXITCODE -ne 0) {
  throw "Validación de cola falló."
}
Write-Host "Cola validada correctamente." -ForegroundColor Green
