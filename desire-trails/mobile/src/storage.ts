import AsyncStorage from "@react-native-async-storage/async-storage";

const USER_KEY = "@desire_trails_user";
const POINTS_PREFIX = "@desire_trails_points_";
const DEBUG_LOCATION_KEY = "@desire_trails_debug_location";

export interface StoredUser {
  id: string;
  display_name: string;
}

export interface StoredPoint {
  lat: number;
  lng: number;
  recorded_at: string;
}

export interface DebugLocation {
  lat: number;
  lng: number;
  enabled: boolean;
}

// User persistence

export async function saveUser(user: StoredUser): Promise<void> {
  await AsyncStorage.setItem(USER_KEY, JSON.stringify(user));
}

export async function getUser(): Promise<StoredUser | null> {
  const raw = await AsyncStorage.getItem(USER_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

// Points persistence

export async function savePoints(
  trailId: string,
  points: StoredPoint[]
): Promise<void> {
  await AsyncStorage.setItem(
    POINTS_PREFIX + trailId,
    JSON.stringify(points)
  );
}

export async function getPoints(trailId: string): Promise<StoredPoint[]> {
  const raw = await AsyncStorage.getItem(POINTS_PREFIX + trailId);
  if (!raw) return [];
  try {
    return JSON.parse(raw);
  } catch {
    return [];
  }
}

export async function clearPoints(trailId: string): Promise<void> {
  await AsyncStorage.removeItem(POINTS_PREFIX + trailId);
}

// Debug location override

export async function saveDebugLocation(
  location: DebugLocation
): Promise<void> {
  await AsyncStorage.setItem(DEBUG_LOCATION_KEY, JSON.stringify(location));
}

export async function getDebugLocation(): Promise<DebugLocation | null> {
  const raw = await AsyncStorage.getItem(DEBUG_LOCATION_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}
