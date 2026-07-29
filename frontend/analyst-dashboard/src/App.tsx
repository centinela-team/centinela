import { useEffect, useState } from "react";
import {
  CaseDetail,
  CaseSummary,
  clearAuth,
  fetchCase,
  fetchCases,
  getAdminConfig,
  getStoredAuth,
  login,
  putAdminConfig,
  storeAuth,
  updateStatus,
  uploadDocument,
} from "./api";

const NEXT: Record<string, string[]> = {
  OPEN: ["IN_REVIEW", "CONFIRMED_FRAUD", "DISMISSED"],
  IN_REVIEW: ["CONFIRMED_FRAUD", "DISMISSED"],
  CONFIRMED_FRAUD: [],
  DISMISSED: [],
};

function LoginForm({ onSuccess }: { onSuccess: (token: string, role: string) => void }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const resp = await login(username, password);
      storeAuth(resp.accessToken, resp.role);
      onSuccess(resp.accessToken, resp.role);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error de login");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="shell">
      <header className="top">
        <div>
          <p className="brand">Centinela</p>
          <h1>Acceso analistas</h1>
        </div>
      </header>
      {error ? <p className="banner">{error}</p> : null}
      <form className="detail login-form" onSubmit={(e) => void onSubmit(e)}>
        <label>
          Usuario
          <input
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoFocus
          />
        </label>
        <label>
          Contraseña
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </label>
        <button type="submit" disabled={busy}>
          {busy ? "Ingresando…" : "Ingresar"}
        </button>
      </form>
    </div>
  );
}

function AdminPanel() {
  const [threshold, setThreshold] = useState<number>(60);
  const [categories, setCategories] = useState("");
  const [source, setSource] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    void (async () => {
      setBusy(true);
      try {
        const cfg = await getAdminConfig();
        setThreshold(cfg.threshold);
        setCategories(cfg.riskyCategories.join(", "));
        setSource(cfg.source);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Error al cargar config");
      } finally {
        setBusy(false);
      }
    })();
  }, []);

  const onSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      const list = categories
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      const cfg = await putAdminConfig(threshold, list);
      setThreshold(cfg.threshold);
      setCategories(cfg.riskyCategories.join(", "));
      setSaved(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al guardar config");
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="detail">
      <section>
        <h2>Configuración de scoring</h2>
        {source ? <p className="meta">Fuente actual: {source}</p> : null}
        {error ? <p className="banner">{error}</p> : null}
        {saved ? <p className="meta">Guardado.</p> : null}
        <form className="login-form" onSubmit={(e) => void onSave(e)}>
          <label>
            Umbral (1-102)
            <input
              type="number"
              min={1}
              max={102}
              value={threshold}
              onChange={(e) => setThreshold(Number(e.target.value))}
            />
          </label>
          <label>
            Comercios de riesgo (códigos MCC separados por coma)
            <input
              type="text"
              value={categories}
              onChange={(e) => setCategories(e.target.value)}
              placeholder="7995, 6051, 7801"
            />
          </label>
          <button type="submit" disabled={busy}>
            {busy ? "Guardando…" : "Guardar"}
          </button>
        </form>
      </section>
    </main>
  );
}

export default function App() {
  const stored = getStoredAuth();
  const [token, setToken] = useState<string | null>(stored?.token ?? null);
  const [role, setRole] = useState<string | null>(stored?.role ?? null);
  const [view, setView] = useState<"cases" | "admin">("cases");

  const [cases, setCases] = useState<CaseSummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<CaseDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const reload = async () => {
    setBusy(true);
    try {
      setError(null);
      const list = await fetchCases();
      setCases(list);
      setSelectedId((prev) => prev ?? (list[0]?.caseId ?? null));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error de carga");
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    if (token) void reload();
  }, [token]);

  useEffect(() => {
    if (!selectedId || !token) {
      setDetail(null);
      return;
    }
    let cancelled = false;
    setBusy(true);
    void (async () => {
      try {
        setError(null);
        const data = await fetchCase(selectedId);
        if (!cancelled) setDetail(data);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : "Error");
      } finally {
        if (!cancelled) setBusy(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedId, token]);

  const onStatus = async (status: string) => {
    if (!selectedId) return;
    setBusy(true);
    try {
      const updated = await updateStatus(selectedId, status);
      setDetail(await fetchCase(selectedId));
      setCases((prev) =>
        prev.map((c) => (c.caseId === selectedId ? { ...c, status: updated.status } : c)),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error de estado");
    } finally {
      setBusy(false);
    }
  };

  const onFile = async (file: File | null) => {
    if (!file || !selectedId) return;
    setBusy(true);
    try {
      await uploadDocument(selectedId, file);
      setDetail(await fetchCase(selectedId));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error de documento");
    } finally {
      setBusy(false);
    }
  };

  const onLogout = () => {
    clearAuth();
    setToken(null);
    setRole(null);
    setView("cases");
    setCases([]);
    setDetail(null);
    setSelectedId(null);
  };

  if (!token) {
    return (
      <LoginForm
        onSuccess={(t, r) => {
          setToken(t);
          setRole(r);
        }}
      />
    );
  }

  return (
    <div className="shell">
      <header className="top">
        <div>
          <p className="brand">Centinela</p>
          <h1>{view === "admin" ? "Panel de administración" : "Cola de casos"}</h1>
        </div>
        <div className="actions">
          {role === "administrador" ? (
            <button
              type="button"
              className="ghost"
              onClick={() => setView((v) => (v === "cases" ? "admin" : "cases"))}
            >
              {view === "cases" ? "Panel admin" : "Volver a casos"}
            </button>
          ) : null}
          <button type="button" className="ghost" onClick={() => void reload()} disabled={busy}>
            Actualizar
          </button>
          <button type="button" className="ghost" onClick={onLogout}>
            Salir
          </button>
        </div>
      </header>

      {error ? <p className="banner">{error}</p> : null}

      {view === "admin" ? (
        <AdminPanel />
      ) : (
        <div className="layout">
          <aside className="list">
            {cases.length === 0 ? (
              <p className="muted">No hay casos abiertos en SQLite.</p>
            ) : (
              cases.map((c) => (
                <button
                  key={c.caseId}
                  type="button"
                  className={c.caseId === selectedId ? "row active" : "row"}
                  onClick={() => setSelectedId(c.caseId)}
                >
                  <span className="score">{c.score}</span>
                  <span>
                    <strong>{c.accountId}</strong>
                    <small>{c.status}</small>
                  </span>
                </button>
              ))
            )}
          </aside>

          <main className="detail">
            {!detail ? (
              <p className="muted">Selecciona un caso.</p>
            ) : (
              <>
                <section>
                  <h2>Caso {detail.caseId.slice(0, 8)}…</h2>
                  <p className="meta">
                    Cuenta <strong>{detail.accountId}</strong> · Tx {detail.transactionId} · Score{" "}
                    <strong>{detail.score}</strong> / {detail.threshold}
                  </p>
                  <div className="actions">
                    {(NEXT[detail.status] || []).map((s) => (
                      <button key={s} type="button" onClick={() => void onStatus(s)} disabled={busy}>
                        {s}
                      </button>
                    ))}
                  </div>
                </section>

                <section>
                  <h3>Explicación</h3>
                  {detail.explanation ? (
                    <pre className="explanation">{detail.explanation}</pre>
                  ) : (
                    <p className="muted">Sin explicación todavía (explicador best-effort).</p>
                  )}
                </section>

                <section>
                  <h3>Documentos de verificación</h3>
                  <label className="upload">
                    <input
                      type="file"
                      accept=".txt,.pdf,.png,.jpg,.jpeg"
                      onChange={(e) => void onFile(e.target.files?.[0] ?? null)}
                    />
                    Adjuntar documento
                  </label>
                  <ul className="docs">
                    {(detail.documents || []).map((d) => (
                      <li key={d.documentId}>
                        <strong>{d.originalName}</strong> — {d.status}
                        {d.message ? <em> · {d.message}</em> : null}
                        {d.extractedFields ? (
                          <pre>{JSON.stringify(d.extractedFields, null, 2)}</pre>
                        ) : null}
                      </li>
                    ))}
                  </ul>
                </section>
              </>
            )}
          </main>
        </div>
      )}
    </div>
  );
}
