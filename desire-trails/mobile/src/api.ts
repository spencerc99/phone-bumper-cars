import { API_URL } from "./config";

interface Show {
  id: string;
  name: string;
  lat: number;
  lng: number;
}

interface User {
  id: string;
  display_name: string;
}

interface Trail {
  id: string;
  show_id: string;
  user_id: string;
  status: string;
}

interface PointInput {
  lat: number;
  lng: number;
  recorded_at: string;
}

export async function fetchShows(): Promise<Show[]> {
  try {
    const res = await fetch(`${API_URL}/shows`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    console.error("fetchShows failed:", err);
    return [];
  }
}

export async function createUser(displayName: string): Promise<User | null> {
  try {
    const res = await fetch(`${API_URL}/users`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ display_name: displayName }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    console.error("createUser failed:", err);
    return null;
  }
}

export async function createTrail(
  showId: string,
  userId: string
): Promise<Trail | null> {
  try {
    const res = await fetch(`${API_URL}/trails`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ show_id: showId, user_id: userId }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    console.error("createTrail failed:", err);
    return null;
  }
}

export async function uploadPoints(
  trailId: string,
  points: PointInput[]
): Promise<boolean> {
  try {
    const res = await fetch(`${API_URL}/trails/${trailId}/points`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ points }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return true;
  } catch (err) {
    console.error("uploadPoints failed:", err);
    return false;
  }
}

export async function finishTrail(trailId: string): Promise<boolean> {
  try {
    const res = await fetch(`${API_URL}/trails/${trailId}/finish`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return true;
  } catch (err) {
    console.error("finishTrail failed:", err);
    return false;
  }
}
