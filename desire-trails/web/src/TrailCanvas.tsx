import { useEffect, useRef, useCallback } from "react";
import simplify from "simplify-js";
import type { Trail } from "./api";

interface Props {
  trails: Trail[];
}

const SIMPLIFY_TOLERANCE = 0.00005;
const BG_COLOR = "#0a0a0a";
const FADE_DURATION_MS = 1000;

/**
 * Hex color string to an {r, g, b} object.
 * Falls back to white if parsing fails.
 */
function hexToRgb(hex: string): { r: number; g: number; b: number } {
  const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (!m) return { r: 255, g: 255, b: 255 };
  return { r: parseInt(m[1], 16), g: parseInt(m[2], 16), b: parseInt(m[3], 16) };
}

function rgba(hex: string, alpha: number): string {
  const { r, g, b } = hexToRgb(hex);
  return `rgba(${r},${g},${b},${alpha})`;
}

export default function TrailCanvas({ trails }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sizeRef = useRef({ w: 0, h: 0 });
  const knownIdsRef = useRef<Set<string>>(new Set());
  const fadeMapRef = useRef<Map<string, number>>(new Map());
  const rafRef = useRef<number>(0);
  const trailsRef = useRef<Trail[]>(trails);

  trailsRef.current = trails;

  // Track which trail IDs are new and assign them a fade-in start time
  useEffect(() => {
    const now = performance.now();
    for (const trail of trails) {
      if (!knownIdsRef.current.has(trail.id)) {
        fadeMapRef.current.set(trail.id, now);
        knownIdsRef.current.add(trail.id);
      }
    }
  }, [trails]);

  const draw = useCallback((timestamp: number) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const { w, h } = sizeRef.current;
    const currentTrails = trailsRef.current;

    // Clear
    ctx.fillStyle = BG_COLOR;
    ctx.fillRect(0, 0, w, h);

    if (currentTrails.length === 0) {
      rafRef.current = requestAnimationFrame(draw);
      return;
    }

    // Compute bounding box across all points
    let minLat = Infinity,
      maxLat = -Infinity,
      minLng = Infinity,
      maxLng = -Infinity;

    for (const trail of currentTrails) {
      for (const p of trail.points) {
        if (p.lat < minLat) minLat = p.lat;
        if (p.lat > maxLat) maxLat = p.lat;
        if (p.lng < minLng) minLng = p.lng;
        if (p.lng > maxLng) maxLng = p.lng;
      }
    }

    // Add 10% padding
    const latRange = maxLat - minLat || 0.001;
    const lngRange = maxLng - minLng || 0.001;
    const padLat = latRange * 0.1;
    const padLng = lngRange * 0.1;
    minLat -= padLat;
    maxLat += padLat;
    minLng -= padLng;
    maxLng += padLng;

    const geoW = maxLng - minLng;
    const geoH = maxLat - minLat;

    // Maintain aspect ratio and center
    const scaleX = w / geoW;
    const scaleY = h / geoH;
    const scale = Math.min(scaleX, scaleY);

    const renderedW = geoW * scale;
    const renderedH = geoH * scale;
    const offsetX = (w - renderedW) / 2;
    const offsetY = (h - renderedH) / 2;

    // Map geo coords to canvas coords
    // lng -> x, lat -> y (inverted so north is up)
    const toCanvas = (lat: number, lng: number): [number, number] => {
      const x = (lng - minLng) * scale + offsetX;
      const y = (maxLat - lat) * scale + offsetY;
      return [x, y];
    };

    // Draw each trail
    for (const trail of currentTrails) {
      if (trail.points.length < 2) continue;

      // Simplify points
      const simplified = simplify(
        trail.points.map((p) => ({ x: p.lng, y: p.lat })),
        SIMPLIFY_TOLERANCE,
        true
      );

      if (simplified.length < 2) continue;

      // Compute fade-in alpha multiplier
      const fadeStart = fadeMapRef.current.get(trail.id);
      let fadeFactor = 1;
      if (fadeStart !== undefined) {
        const elapsed = timestamp - fadeStart;
        fadeFactor = Math.min(1, elapsed / FADE_DURATION_MS);
        if (fadeFactor >= 1) {
          fadeMapRef.current.delete(trail.id);
        }
      }

      const color = trail.user_color || "#ffffff";

      // Build path once
      const path = new Path2D();
      const [sx, sy] = toCanvas(simplified[0].y, simplified[0].x);
      path.moveTo(sx, sy);
      for (let i = 1; i < simplified.length; i++) {
        const [px, py] = toCanvas(simplified[i].y, simplified[i].x);
        path.lineTo(px, py);
      }

      // Glow layer
      ctx.save();
      ctx.strokeStyle = rgba(color, 0.2 * fadeFactor);
      ctx.lineWidth = 4;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.stroke(path);
      ctx.restore();

      // Sharp layer
      ctx.save();
      ctx.strokeStyle = rgba(color, 0.7 * fadeFactor);
      ctx.lineWidth = 2;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.stroke(path);
      ctx.restore();
    }

    // Keep animating if any fades are still in progress
    if (fadeMapRef.current.size > 0) {
      rafRef.current = requestAnimationFrame(draw);
    }
  }, []);

  // Trigger a redraw whenever trails change
  useEffect(() => {
    cancelAnimationFrame(rafRef.current);
    rafRef.current = requestAnimationFrame(draw);
  }, [trails, draw]);

  // ResizeObserver to keep canvas sized to fill viewport
  useEffect(() => {
    const container = containerRef.current;
    const canvas = canvasRef.current;
    if (!container || !canvas) return;

    const ro = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        const dpr = window.devicePixelRatio || 1;
        canvas.width = width * dpr;
        canvas.height = height * dpr;
        canvas.style.width = `${width}px`;
        canvas.style.height = `${height}px`;
        const ctx = canvas.getContext("2d");
        if (ctx) ctx.scale(dpr, dpr);
        sizeRef.current = { w: width, h: height };
        cancelAnimationFrame(rafRef.current);
        rafRef.current = requestAnimationFrame(draw);
      }
    });

    ro.observe(container);
    return () => ro.disconnect();
  }, [draw]);

  return (
    <div
      ref={containerRef}
      style={{ width: "100%", height: "100%", position: "absolute", inset: 0 }}
    >
      <canvas ref={canvasRef} style={{ display: "block" }} />
    </div>
  );
}
