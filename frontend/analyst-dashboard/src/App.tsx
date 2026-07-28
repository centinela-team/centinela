import { useEffect, useState } from "react";
import {
  CaseDetail,
  CaseSummary,
  fetchCase,
  fetchCases,
  updateStatus,
  uploadDocument,
} from "./api";

const NEXT: Record<string, string[]> = {
  OPEN: ["IN_REVIEW", "CONFIRMED_FRAUD", "DISMISSED"],
  IN_REVIEW: ["CONFIRMED_FRAUD", "DISMISSED"],
  CONFIRMED_FRAUD: [],
  DISMISSED: [],
};

export default function App() {
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
    void reload();
  }, []);

  useEffect(() => {
    if (!selectedId) {
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
  }, [selectedId]);

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

  return (
    <div className="shell">
      <header className="top">
        <div>
          <p className="brand">Centinela</p>
          <h1>Cola de casos</h1>
        </div>
        <button type="button" className="ghost" onClick={() => void reload()} disabled={busy}>
          Actualizar
        </button>
      </header>

      {error ? <p className="banner">{error}</p> : null}

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
    </div>
  );
}
