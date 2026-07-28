export type CaseSummary = {
  caseId: string;
  transactionId: string;
  accountId: string;
  score: number;
  threshold: number;
  status: string;
  openedAt: string;
  hasExplanation: boolean;
};

export type CaseDocument = {
  documentId: string;
  originalName: string;
  status: string;
  extractedFields?: Record<string, unknown> | null;
  message?: string | null;
};

export type CaseDetail = CaseSummary & {
  explanation?: string | null;
  triggeredRules?: unknown[];
  documents?: CaseDocument[];
};

const base = "";

export async function fetchCases(): Promise<CaseSummary[]> {
  const res = await fetch(`${base}/v1/cases`);
  if (!res.ok) throw new Error(`No se pudieron cargar casos (${res.status})`);
  return res.json();
}

export async function fetchCase(caseId: string): Promise<CaseDetail> {
  const res = await fetch(`${base}/v1/cases/${caseId}`);
  if (!res.ok) throw new Error(`Caso no encontrado`);
  return res.json();
}

export async function updateStatus(caseId: string, status: string): Promise<CaseDetail> {
  const res = await fetch(`${base}/v1/cases/${caseId}/status`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ status, actorId: "analyst-ui", detail: "Cambio desde dashboard" }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(body || `Error ${res.status}`);
  }
  return res.json();
}

export async function uploadDocument(caseId: string, file: File): Promise<unknown> {
  const prep = await fetch(`${base}/v1/cases/${caseId}/documents`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      fileName: file.name,
      contentType: file.type || "text/plain",
      uploadedBy: "analyst-ui",
    }),
  });
  if (!prep.ok) throw new Error("No se pudo registrar el documento");
  const meta = await prep.json();
  const form = new FormData();
  form.append("file", file);
  const up = await fetch(
    `${base}/v1/cases/${caseId}/documents/${meta.documentId}/upload`,
    { method: "POST", body: form },
  );
  if (!up.ok) throw new Error("Fallo al subir / analizar documento");
  return up.json();
}
