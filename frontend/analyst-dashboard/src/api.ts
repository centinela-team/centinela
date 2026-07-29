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

export type LoginResponse = {
  accessToken: string;
  role: string;
  expiresIn: number;
};

export type AdminConfig = {
  threshold: number;
  riskyCategories: string[];
  source: string;
};

const base = "";

const TOKEN_KEY = "centinela_token";
const ROLE_KEY = "centinela_role";
const USERNAME_KEY = "centinela_username";

export function getStoredAuth(): { token: string; role: string; username: string } | null {
  const token = localStorage.getItem(TOKEN_KEY);
  const role = localStorage.getItem(ROLE_KEY);
  const username = localStorage.getItem(USERNAME_KEY);
  if (!token || !role || !username) return null;
  return { token, role, username };
}

export function storeAuth(token: string, role: string, username: string): void {
  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(ROLE_KEY, role);
  localStorage.setItem(USERNAME_KEY, username);
}

export function clearAuth(): void {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(ROLE_KEY);
  localStorage.removeItem(USERNAME_KEY);
}

function authHeaders(): HeadersInit {
  const stored = getStoredAuth();
  return stored ? { Authorization: `Bearer ${stored.token}` } : {};
}

export async function login(username: string, password: string): Promise<LoginResponse> {
  const res = await fetch(`${base}/v1/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error("Credenciales inválidas");
  return res.json();
}

export async function fetchCases(): Promise<CaseSummary[]> {
  const res = await fetch(`${base}/v1/cases`, { headers: authHeaders() });
  if (!res.ok) throw new Error(`No se pudieron cargar casos (${res.status})`);
  return res.json();
}

export async function fetchCase(caseId: string): Promise<CaseDetail> {
  const res = await fetch(`${base}/v1/cases/${caseId}`, { headers: authHeaders() });
  if (!res.ok) throw new Error(`Caso no encontrado`);
  return res.json();
}

export async function updateStatus(caseId: string, status: string): Promise<CaseDetail> {
  const res = await fetch(`${base}/v1/cases/${caseId}/status`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify({ status, detail: "Cambio desde dashboard" }),
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
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify({
      fileName: file.name,
      contentType: file.type || "text/plain",
    }),
  });
  if (!prep.ok) throw new Error("No se pudo registrar el documento");
  const meta = await prep.json();
  const form = new FormData();
  form.append("file", file);
  const up = await fetch(
    `${base}/v1/cases/${caseId}/documents/${meta.documentId}/upload`,
    { method: "POST", headers: authHeaders(), body: form },
  );
  if (!up.ok) throw new Error("Fallo al subir / analizar documento");
  return up.json();
}

export async function getAdminConfig(): Promise<AdminConfig> {
  const res = await fetch(`${base}/v1/admin/config`, { headers: authHeaders() });
  if (!res.ok) throw new Error(`No se pudo cargar la configuración (${res.status})`);
  return res.json();
}

export async function putAdminConfig(
  threshold: number,
  riskyCategories: string[],
): Promise<AdminConfig> {
  const res = await fetch(`${base}/v1/admin/config`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify({ threshold, riskyCategories }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(body || `Error ${res.status}`);
  }
  return res.json();
}
