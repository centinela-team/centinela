import { useEffect, useRef, useState } from "react";
import {
  AppUser,
  AuditFeedEntry,
  CaseAuditEntry,
  CaseDetail,
  CaseSummary,
  clearAuth,
  createUser,
  fetchAuditFeed,
  fetchCase,
  fetchCaseAudit,
  fetchCases,
  fetchUsers,
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
  IconLock,
  IconLogout,
  IconRefresh,
  IconShield,
  IconSliders,
  IconUpload,
  IconUser,
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

const STATUS_ORDER = ["OPEN", "IN_REVIEW", "CONFIRMED_FRAUD", "DISMISSED"];

function scoreLevel(score: number, threshold: number): "high" | "medium" | "low" {
  if (score >= threshold * 1.3) return "high";
  if (score >= threshold) return "medium";
  return "low";
}

function initials(name: string): string {
  return name.slice(0, 2).toUpperCase();
}

function formatDateTime(iso: string): string {
  try {
    return new Date(iso).toLocaleString("es-CO", {
      dateStyle: "short",
      timeStyle: "short",
    });
  } catch {
    return iso;
  }
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
      <div className="login-scene" aria-hidden="true">
        <div className="login-scene-photo" />
        <div className="login-scene-overlay" />
      </div>
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
        <form className="login-form" onSubmit={(e) => void onSubmit(e)}>
          <label className="login-field">
            <span>Usuario</span>
            <div className="login-field-input">
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                autoFocus
              />
              <IconUser size={18} />
            </div>
          </label>
          <label className="login-field">
            <span>Contraseña</span>
            <div className="login-field-input">
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
              <IconLock size={18} />
            </div>
          </label>
          <button type="submit" className="btn btn-primary login-submit" disabled={busy}>
            {busy ? "Ingresando…" : "Ingresar"}
          </button>
        </form>
      </div>
    </div>
  );
}

function AdminPanel() {
  const [tab, setTab] = useState<"config" | "users">("config");
  return (
    <>
      <div className="admin-tabs">
        <button
          type="button"
          className={tab === "config" ? "admin-tab active" : "admin-tab"}
          onClick={() => setTab("config")}
        >
          <IconSliders size={16} />
          Configuración de scoring
        </button>
        <button
          type="button"
          className={tab === "users" ? "admin-tab active" : "admin-tab"}
          onClick={() => setTab("users")}
        >
          <IconUser size={16} />
          Usuarios
        </button>
      </div>
      {tab === "config" ? <ScoringConfigPanel /> : <UsersPanel />}
    </>
  );
}

function ScoringConfigPanel() {
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
    <div className="layout admin-layout">
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
          <form className="form-grid" onSubmit={(e) => void onSave(e)}>
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

      <aside className="panel rules-ref">
        <h3>
          <IconLayers size={18} />
          Reglas de scoring activas
        </h3>
        <p className="form-hint">Puntos que suman al score de una transacción; no editables aquí.</p>
        <ul className="rules-list">
          {SCORING_RULES.map((rule) => (
            <li key={rule.id}>
              <span className="rules-list-head">
                <code>{rule.id}</code>
                <span className="rules-list-points">+{rule.points}</span>
              </span>
              <p>{rule.description}</p>
            </li>
          ))}
        </ul>
        <p className="form-hint rules-list-note">
          Una transacción es caso de fraude cuando la suma de reglas activadas alcanza el umbral configurado a la
          izquierda.
        </p>
      </aside>
    </div>
  );
}

const ROLE_LABEL: Record<string, string> = {
  analista: "Analista",
  administrador: "Administrador",
  auditor: "Auditor",
};

function UsersPanel() {
  const [users, setUsers] = useState<AppUser[]>([]);
  const [newUsername, setNewUsername] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newRole, setNewRole] = useState("analista");
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);

  const reload = async () => {
    try {
      setUsers(await fetchUsers());
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al cargar usuarios");
    }
  };

  useEffect(() => {
    void reload();
  }, []);

  const onCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      await createUser(newUsername, newPassword, newRole);
      setNewUsername("");
      setNewPassword("");
      setNewRole("analista");
      setSaved(true);
      await reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al crear usuario");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="layout admin-layout">
      <div className="panel detail">
        <section>
          <h3>
            <IconUser size={18} />
            Nuevo usuario
          </h3>
          {error ? (
            <p className="banner">
              <IconAlert size={16} />
              {error}
            </p>
          ) : null}
          {saved ? <p className="form-success">Usuario creado correctamente.</p> : null}
          <form className="form-grid" onSubmit={(e) => void onCreate(e)}>
            <label>
              Usuario
              <input
                type="text"
                value={newUsername}
                onChange={(e) => setNewUsername(e.target.value)}
                minLength={3}
                required
              />
            </label>
            <label>
              Contraseña
              <input
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                minLength={8}
                required
              />
            </label>
            <label>
              Rol
              <select value={newRole} onChange={(e) => setNewRole(e.target.value)}>
                <option value="analista">Analista</option>
                <option value="administrador">Administrador</option>
                <option value="auditor">Auditor</option>
              </select>
            </label>
            <button type="submit" className="btn btn-primary" disabled={busy}>
              {busy ? "Creando…" : "Crear usuario"}
            </button>
          </form>
        </section>
      </div>

      <aside className="panel rules-ref">
        <h3>
          <IconLayers size={18} />
          Usuarios existentes
        </h3>
        <p className="form-hint">{users.length} en total.</p>
        <ul className="rules-list">
          {users.map((u) => (
            <li key={u.username}>
              <span className="rules-list-head">
                <code>{u.username}</code>
                <span className="status-tag" data-status={u.isActive ? "OPEN" : "DISMISSED"}>
                  {ROLE_LABEL[u.role] ?? u.role}
                </span>
              </span>
              <p>Creado {formatDateTime(u.createdAt)}</p>
            </li>
          ))}
        </ul>
      </aside>
    </div>
  );
}

function AuditFeedPanel({ onSelectCase }: { onSelectCase: (caseId: string) => void }) {
  const [entries, setEntries] = useState<AuditFeedEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);

  useEffect(() => {
    void (async () => {
      try {
        setEntries(await fetchAuditFeed(50));
      } catch (e) {
        setError(e instanceof Error ? e.message : "Error al cargar auditoría");
      } finally {
        setBusy(false);
      }
    })();
  }, []);

  return (
    <div className="panel detail audit-feed-panel">
      <section>
        <h3>
          <IconAlert size={18} />
          Actividad reciente
        </h3>
        <p className="form-hint">Últimos {entries.length} movimientos de todos los casos.</p>
        {error ? (
          <p className="banner">
            <IconAlert size={16} />
            {error}
          </p>
        ) : null}
        {!busy && entries.length === 0 ? (
          <p className="muted">Sin movimientos todavía.</p>
        ) : (
          <ul className="audit-trail">
            {entries.map((entry, i) => (
              <li key={i}>
                <button
                  type="button"
                  className="audit-feed-entry"
                  onClick={() => onSelectCase(entry.caseId)}
                >
                  <span className="audit-trail-status">
                    <strong>{entry.accountId}</strong> ·{" "}
                    {entry.fromStatus ? (
                      <>
                        {STATUS_LABEL[entry.fromStatus] ?? entry.fromStatus} →{" "}
                      </>
                    ) : null}
                    {STATUS_LABEL[entry.toStatus] ?? entry.toStatus}
                  </span>
                  <span className="audit-trail-meta">
                    {entry.actorId} · {formatDateTime(entry.occurredAt)}
                  </span>
                  {entry.detail ? <p>{entry.detail}</p> : null}
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

const SCORING_RULES = [
  {
    id: "VELOCITY",
    points: 35,
    description: "3 o más transacciones de la misma cuenta en una ventana de 5 minutos.",
  },
  {
    id: "ATYPICAL_AMOUNT",
    points: 30,
    description: "Monto mayor a 10 veces el promedio histórico de la cuenta.",
  },
  {
    id: "RISKY_MERCHANT",
    points: 20,
    description: "El comercio tiene un código de categoría (MCC) marcado como riesgoso.",
  },
  {
    id: "GEO_IMPOSSIBLE",
    points: 17,
    description: "Velocidad implícita entre ubicaciones consecutivas supera 900 km/h.",
  },
];

export default function App() {
  const stored = getStoredAuth();
  const [token, setToken] = useState<string | null>(stored?.token ?? null);
  const [role, setRole] = useState<string | null>(stored?.role ?? null);
  const [username, setUsername] = useState<string | null>(stored?.username ?? null);
  const [view, setView] = useState<"cases" | "admin" | "audit">("cases");

  const [cases, setCases] = useState<CaseSummary[]>([]);
  const [statusFilter, setStatusFilter] = useState<string>("ALL");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<CaseDetail | null>(null);
  const [auditTrail, setAuditTrail] = useState<CaseAuditEntry[]>([]);
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
      setAuditTrail([]);
      return;
    }
    let cancelled = false;
    setBusy(true);
    void (async () => {
      try {
        setError(null);
        const [data, audit] = await Promise.all([
          fetchCase(selectedId),
          fetchCaseAudit(selectedId),
        ]);
        if (!cancelled) {
          setDetail(data);
          setAuditTrail(audit);
        }
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
      const [data, audit] = await Promise.all([
        fetchCase(selectedId),
        fetchCaseAudit(selectedId),
      ]);
      setDetail(data);
      setAuditTrail(audit);
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

  const statusCounts = cases.reduce<Record<string, number>>((acc, c) => {
    acc[c.status] = (acc[c.status] ?? 0) + 1;
    return acc;
  }, {});
  const filteredCases =
    statusFilter === "ALL" ? cases : cases.filter((c) => c.status === statusFilter);

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
          <button
            type="button"
            className={view === "audit" ? "nav-item active" : "nav-item"}
            onClick={() => setView("audit")}
          >
            <IconAlert size={18} />
            Auditoría
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
          <h1>
            {view === "admin" ? "Panel de administración" : view === "audit" ? "Auditoría" : "Cola de casos"}
          </h1>
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
        ) : view === "audit" ? (
          <AuditFeedPanel
            onSelectCase={(caseId) => {
              setView("cases");
              setSelectedId(caseId);
            }}
          />
        ) : (
          <div className="layout">
            <aside className="panel list">
              {cases.length > 0 ? (
                <div className="status-filter">
                  <button
                    type="button"
                    className={statusFilter === "ALL" ? "status-filter-tab active" : "status-filter-tab"}
                    onClick={() => setStatusFilter("ALL")}
                  >
                    Todos <span>{cases.length}</span>
                  </button>
                  {STATUS_ORDER.filter((s) => statusCounts[s]).map((s) => (
                    <button
                      key={s}
                      type="button"
                      className={statusFilter === s ? "status-filter-tab active" : "status-filter-tab"}
                      onClick={() => setStatusFilter(s)}
                    >
                      {STATUS_LABEL[s] ?? s} <span>{statusCounts[s]}</span>
                    </button>
                  ))}
                </div>
              ) : null}
              {filteredCases.length === 0 ? (
                <div className="empty-state">
                  <IconInbox size={28} />
                  {cases.length === 0
                    ? "No hay casos abiertos en la cola."
                    : "Ningún caso coincide con este filtro."}
                </div>
              ) : (
                filteredCases.map((c) => (
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

            <main className={detail ? "panel detail" : "panel detail empty"}>
              {!detail ? (
                <div className="empty-state">
                  <IconLayers size={28} />
                  Selecciona un caso de la cola para ver el detalle.
                </div>
              ) : (
                <>
                  <section>
                    <div className="detail-head">
                      <h2>Caso {detail.caseId.slice(0, 8)}…</h2>
                      <span className="status-tag" data-status={detail.status}>
                        {STATUS_LABEL[detail.status] ?? detail.status}
                      </span>
                    </div>
                    <p className="meta">
                      Cuenta <strong>{detail.accountId}</strong> · Tx{" "}
                      <code>{detail.transactionId.slice(0, 8)}…</code>
                    </p>
                    <span
                      className="score-chip score-chip-lg"
                      data-level={scoreLevel(detail.score, detail.threshold)}
                    >
                      {detail.score} / {detail.threshold}
                    </span>
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
                      <IconAlert size={16} />
                      Reglas activadas
                    </h3>
                    {detail.triggeredRules && detail.triggeredRules.length > 0 ? (
                      <ul className="rules-list">
                        {detail.triggeredRules.map((r, i) => (
                          <li key={`${r.ruleId}-${i}`}>
                            <span className="rules-list-head">
                              <code>{r.ruleId}</code>
                              <span className="rules-list-points">+{r.points}</span>
                            </span>
                            {r.evidence && Object.keys(r.evidence).length > 0 ? (
                              <p className="rules-evidence">
                                {Object.entries(r.evidence).map(([k, v]) => (
                                  <span key={k}>
                                    {k}: <strong>{String(v)}</strong>
                                  </span>
                                ))}
                              </p>
                            ) : null}
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="muted">Sin reglas registradas para este caso.</p>
                    )}
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
                            {d.extractedFields && Object.keys(d.extractedFields).length > 0 ? (
                              <p className="rules-evidence">
                                {Object.entries(d.extractedFields).map(([k, v]) => (
                                  <span key={k}>
                                    {k}: <strong>{String(v)}</strong>
                                  </span>
                                ))}
                              </p>
                            ) : null}
                          </span>
                        </li>
                      ))}
                    </ul>
                  </section>

                  <section>
                    <h3>
                      <IconLayers size={16} />
                      Historial
                    </h3>
                    {auditTrail.length > 0 ? (
                      <ul className="audit-trail">
                        {auditTrail.map((entry, i) => (
                          <li key={i}>
                            <span className="audit-trail-status">
                              {entry.fromStatus ? (
                                <>
                                  {STATUS_LABEL[entry.fromStatus] ?? entry.fromStatus} →{" "}
                                </>
                              ) : null}
                              <strong>{STATUS_LABEL[entry.toStatus] ?? entry.toStatus}</strong>
                            </span>
                            <span className="audit-trail-meta">
                              {entry.actorId} · {formatDateTime(entry.occurredAt)}
                            </span>
                            {entry.detail ? <p>{entry.detail}</p> : null}
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="muted">Sin movimientos registrados.</p>
                    )}
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
