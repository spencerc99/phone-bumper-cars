import * as Location from "expo-location";
import * as TaskManager from "expo-task-manager";
import { getPoints, savePoints, StoredPoint } from "./storage";

export const LOCATION_TRACKING = "DESIRE_TRAILS_LOCATION_TRACKING";

// Current trail ID, set when tracking starts.
// This is module-level state so the background task can access it.
let activeTrailId: string | null = null;

// Define the background task at the module level (required by expo-task-manager).
TaskManager.defineTask(LOCATION_TRACKING, async ({ data, error }) => {
  if (error) {
    console.error("Background location task error:", error.message);
    return;
  }

  if (!data || !activeTrailId) return;

  const { locations } = data as { locations: Location.LocationObject[] };
  if (!locations || locations.length === 0) return;

  const trailId = activeTrailId;

  try {
    const existing = await getPoints(trailId);

    const newPoints: StoredPoint[] = locations.map((loc) => ({
      lat: loc.coords.latitude,
      lng: loc.coords.longitude,
      recorded_at: new Date(loc.timestamp).toISOString(),
    }));

    await savePoints(trailId, [...existing, ...newPoints]);
  } catch (err) {
    console.error("Failed to save points in background task:", err);
  }
});

export async function startTracking(trailId: string): Promise<boolean> {
  // Request foreground permission first
  const { status: fgStatus } =
    await Location.requestForegroundPermissionsAsync();
  if (fgStatus !== "granted") {
    console.error("Foreground location permission denied");
    return false;
  }

  // Then request background permission
  const { status: bgStatus } =
    await Location.requestBackgroundPermissionsAsync();
  if (bgStatus !== "granted") {
    console.error("Background location permission denied");
    return false;
  }

  activeTrailId = trailId;

  await Location.startLocationUpdatesAsync(LOCATION_TRACKING, {
    accuracy: Location.Accuracy.High,
    timeInterval: 10000,
    distanceInterval: 5,
    showsBackgroundLocationIndicator: true,
    foregroundService: {
      notificationTitle: "Desire Trails",
      notificationBody: "Recording your trail...",
      notificationColor: "#ffffff",
    },
  });

  return true;
}

export async function stopTracking(): Promise<void> {
  const isTracking = await TaskManager.isTaskRegisteredAsync(LOCATION_TRACKING);
  if (isTracking) {
    await Location.stopLocationUpdatesAsync(LOCATION_TRACKING);
  }
  activeTrailId = null;
}
