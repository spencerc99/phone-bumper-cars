import { useEffect, useRef, useState } from "react";
import { fetchTrails } from "./api";
import type { Trail } from "./api";
import { SHOW_ID, REFRESH_INTERVAL_MS } from "./config";
import TrailCanvas from "./TrailCanvas";

function App() {
  const [trails, setTrails] = useState<Trail[]>([]);
  const [loading, setLoading] = useState(true);
  const hasLoadedOnce = useRef(false);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const data = await fetchTrails(SHOW_ID);
        if (!cancelled) {
          setTrails(data);
          if (!hasLoadedOnce.current) {
            hasLoadedOnce.current = true;
            setLoading(false);
          }
        }
      } catch (err) {
        console.error("Failed to fetch trails:", err);
        if (!hasLoadedOnce.current && !cancelled) {
          setLoading(false);
        }
      }
    }

    load();
    const interval = setInterval(load, REFRESH_INTERVAL_MS);

    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  return (
    <div style={{ width: "100%", height: "100%", position: "relative" }}>
      {loading && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 10,
          }}
        >
          <div
            style={{
              width: 6,
              height: 6,
              borderRadius: "50%",
              background: "#333",
              animation: "pulse 1.5s ease-in-out infinite",
            }}
          />
          <style>{`
            @keyframes pulse {
              0%, 100% { opacity: 0.3; transform: scale(1); }
              50% { opacity: 1; transform: scale(1.8); }
            }
          `}</style>
        </div>
      )}
      <TrailCanvas trails={trails} />
    </div>
  );
}

export default App;
