import { API_URL } from "./config";

export interface Point {
  lat: number;
  lng: number;
  recorded_at: string;
}

export interface Trail {
  id: string;
  user_display_name: string;
  user_color: string;
  started_at: string;
  ended_at: string | null;
  points: Point[];
}

export async function fetchTrails(showId: string): Promise<Trail[]> {
  const res = await fetch(`${API_URL}/trails?show_id=${encodeURIComponent(showId)}`);
  if (!res.ok) {
    throw new Error(`Failed to fetch trails: ${res.status}`);
  }
  const data = await res.json();
  return data.trails as Trail[];
}
