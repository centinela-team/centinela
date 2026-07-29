import { useEffect, useRef, useState } from "react";
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
import {
  IconAlert,
  IconFile,
  IconInbox,
  IconLayers,
  IconLogout,
  IconRefresh,
  IconShield,
  IconSliders,
  IconUpload,
} from "./icons";

const NEXT: Record<string, string[]> = {
  OPEN: ["IN_REVIEW", "CONFIRMED_FRAUD", "DISMISSED"],
  IN_REVIEW: ["CONFIRMED_FRAUD", "DISMISSED"],
  CONFIRMED_FRAUD: [],
  DISMISSED: [],
};

const STATUS_LABEL: Record<string, string> = {
  OPEN: "Abierto",
  IN_REVIEW: "En revisión",
  CONFIRMED_FRAUD: "Fraude confirmado",
  DISMISSED: "Descartado",
};

function scoreLevel(score: number, threshold: number): "high" | "medium" | "low" {
  if (score >= threshold * 1.3) return "high";
  if (score >= threshold) return "medium";
  return "low";
}

function initials(name: string): string {
  return name.slice(0, 2).toUpperCase();
}

function Brand() {
  return (
    <div className="sidebar-brand">
      <IconShield size={22} />
      <strong>Centinela</strong>
    </div>
  );
}

function LoginForm({
  onSuccess,
}: {
  onSuccess: (token: string, role: string, username: string) => void;
}) {
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
      storeAuth(resp.accessToken, resp.role, username);
      onSuccess(resp.accessToken, resp.role, username);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error de login");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="login-screen">
      <div className="login-card">
        <div className="login-mark">
          <IconShield size={26} />
          <strong>Centinela</strong>
        </div>
        <p className="muted">Acceso analistas</p>
        {error ? (
          <p className="banner">
            <IconAlert size={16} />
            {error}
          </p>
        ) : null}
        <form className="form-grid" onSubmit={(e) => void onSubmit(e)}>
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
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? "Ingresando…" : "Ingresar"}
          </button>
        </form>
      </div>
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
    <div className="panel detail">
      <section>
        <h3>
          <IconSliders size={18} />
          Configuración de scoring
        </h3>
        <p className="form-hint">
          Fuente actual: <strong>{source ?? "…"}</strong>
        </p>
        {error ? (
          <p className="banner">
            <IconAlert size={16} />
            {error}
          </p>
        ) : null}
        {saved ? <p className="form-success">Guardado correctamente.</p> : null}
        <form className="form-grid" onSubmit={(e) => void onSave(e)} style={{ maxWidth: 360 }}>
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
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? "Guardando…" : "Guardar"}
          </button>
        </form>
      </section>
    </div>
  );
}

export default function App() {
  const stored = getStoredAuth();
  const [token, setToken] = useState<string | null>(stored?.token ?? null);
  const [role, setRole] = useState<string | null>(stored?.role ?? null);
  const [username, setUsername] = useState<string | null>(stored?.username ?? null);
  const [view, setView] = useState<"cases" | "admin">("cases");

  const [cases, setCases] = useState<CaseSummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<CaseDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showUserMenu, setShowUserMenu] = useState(false);
  const userMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!showUserMenu) return;
    const onClickOutside = (e: MouseEvent) => {
      if (userMenuRef.current && !userMenuRef.current.contains(e.target as Node)) {
        setShowUserMenu(false);
      }
    };
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, [showUserMenu]);

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
    setUsername(null);
    setView("cases");
    setCases([]);
    setDetail(null);
    setSelectedId(null);
  };

  if (!token) {
    return (
      <LoginForm
        onSuccess={(t, r, u) => {
          setToken(t);
          setRole(r);
          setUsername(u);
        }}
      />
    );
  }

  return (
    <div className="app-shell">
      <nav className="sidebar">
        <Brand />
        <div className="sidebar-nav">
          <button
            type="button"
            className={view === "cases" ? "nav-item active" : "nav-item"}
            onClick={() => setView("cases")}
          >
            <IconLayers size={18} />
            Casos
          </button>
          {role === "administrador" ? (
            <button
              type="button"
              className={view === "admin" ? "nav-item active" : "nav-item"}
              onClick={() => setView("admin")}
            >
              <IconSliders size={18} />
              Panel admin
            </button>
          ) : null}
        </div>
        <div className="sidebar-spacer" />
        <div className="user-chip-wrap" ref={userMenuRef}>
          {showUserMenu ? (
            <div className="user-menu">
              <p className="user-menu-title">Sesión iniciada</p>
              <p className="user-menu-detail">
                <strong>{username}</strong>
                <span className="role-pill">{role}</span>
              </p>
              <button type="button" className="user-menu-logout" onClick={onLogout}>
                <IconLogout size={16} />
                Cerrar sesión
              </button>
            </div>
          ) : null}
          <button
            type="button"
            className="sidebar-footer"
            onClick={() => setShowUserMenu((v) => !v)}
            aria-expanded={showUserMenu}
          >
            <span className="avatar">{initials(username ?? "?")}</span>
            <span className="user-meta">
              <strong>{username}</strong>
              <span className="role-pill">{role}</span>
            </span>
          </button>
        </div>
      </nav>

      <div className="app-main">
        <header className="topbar">
          <h1>{view === "admin" ? "Panel de administración" : "Cola de casos"}</h1>
          <div className="topbar-actions">
            <button type="button" className="btn" onClick={() => void reload()} disabled={busy}>
              <IconRefresh size={16} />
              Actualizar
            </button>
          </div>
        </header>

        {error ? (
          <p className="banner">
            <IconAlert size={16} />
            {error}
          </p>
        ) : null}

        {view === "admin" ? (
          <AdminPanel />
        ) : (
          <div className="layout">
            <aside className="panel list">
              {cases.length === 0 ? (
                <div className="empty-state">
                  <IconInbox size={28} />
                  No hay casos abiertos en SQLite.
                </div>
              ) : (
                cases.map((c) => (
                  <button
                    key={c.caseId}
                    type="button"
                    className={c.caseId === selectedId ? "row active" : "row"}
                    onClick={() => setSelectedId(c.caseId)}
                  >
                    <span className="score-chip" data-level={scoreLevel(c.score, c.threshold)}>
                      {c.score}
                    </span>
                    <span className="row-meta">
                      <strong>{c.accountId}</strong>
                      <span className="status-tag" data-status={c.status}>
                        {STATUS_LABEL[c.status] ?? c.status}
                      </span>
                    </span>
                  </button>
                ))
              )}
            </aside>

            <main className="panel detail">
              {!detail ? (
                <p className="muted">Selecciona un caso.</p>
              ) : (
                <>
                  <section>
                    <h2>Caso {detail.caseId.slice(0, 8)}…</h2>
                    <p className="meta">
                      Cuenta <strong>{detail.accountId}</strong> · Tx{" "}
                      <code>{detail.transactionId.slice(0, 8)}…</code> · Score{" "}
                      <strong>{detail.score}</strong> / {detail.threshold}
                    </p>
                    <div className="action-row">
                      {(NEXT[detail.status] || []).map((s) => (
                        <button
                          key={s}
                          type="button"
                          className="btn status-btn"
                          data-status={s}
                          onClick={() => void onStatus(s)}
                          disabled={busy}
                        >
                          {STATUS_LABEL[s] ?? s}
                        </button>
                      ))}
                    </div>
                  </section>

                  <section>
                    <h3>
                      <IconFile size={16} />
                      Explicación
                    </h3>
                    {detail.explanation ? (
                      <pre className="explanation">{detail.explanation}</pre>
                    ) : (
                      <p className="muted">Sin explicación todavía (explicador best-effort).</p>
                    )}
                  </section>

                  <section>
                    <h3>
                      <IconUpload size={16} />
                      Documentos de verificación
                    </h3>
                    <label className="upload-zone">
                      <IconUpload size={16} />
                      <input
                        type="file"
                        accept=".txt,.pdf,.png,.jpg,.jpeg"
                        onChange={(e) => void onFile(e.target.files?.[0] ?? null)}
                      />
                      Adjuntar documento
                    </label>
                    <ul className="docs">
                      {(detail.documents || []).map((d) => (
                        <li key={d.documentId} className="doc-item">
                          <span className="doc-icon">
                            <IconFile size={18} />
                          </span>
                          <span className="doc-body">
                            <span className="doc-name">
                              <strong>{d.originalName}</strong>
                              <span className="doc-status" data-status={d.status}>
                                {d.status}
                              </span>
                            </span>
                            {d.message ? <div className="doc-message">{d.message}</div> : null}
                            {d.extractedFields ? (
                              <pre className="doc-fields">
                                {JSON.stringify(d.extractedFields, null, 2)}
                              </pre>
                            ) : null}
                          </span>
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
    </div>
  );
}
