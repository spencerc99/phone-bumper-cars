import React, { useState, useEffect, useRef } from "react";
import {
  StyleSheet,
  Text,
  View,
  TextInput,
  TouchableOpacity,
  Animated,
  Modal,
  Switch,
  Alert,
  SafeAreaView,
} from "react-native";
import { StatusBar } from "expo-status-bar";

// Import tracking module at top level so the TaskManager.defineTask runs
import "./src/tracking";

import { DEFAULT_SHOW } from "./src/config";
import { createUser, createTrail, uploadPoints, finishTrail } from "./src/api";
import {
  saveUser,
  getUser,
  getPoints,
  clearPoints,
  saveDebugLocation,
  getDebugLocation,
  StoredUser,
  DebugLocation,
} from "./src/storage";
import { startTracking, stopTracking } from "./src/tracking";

type AppState = "loading" | "onboarding" | "idle" | "recording" | "uploading";

export default function App() {
  const [appState, setAppState] = useState<AppState>("loading");
  const [user, setUser] = useState<StoredUser | null>(null);
  const [displayName, setDisplayName] = useState("");
  const [trailId, setTrailId] = useState<string | null>(null);
  const [pointCount, setPointCount] = useState(0);
  const [showDebug, setShowDebug] = useState(false);
  const [debugLat, setDebugLat] = useState("");
  const [debugLng, setDebugLng] = useState("");
  const [debugEnabled, setDebugEnabled] = useState(false);
  const [debugLocation, setDebugLocationState] = useState<DebugLocation | null>(
    null
  );
  const [uploadError, setUploadError] = useState(false);

  // Pulsing animation for recording indicator
  const pulseAnim = useRef(new Animated.Value(1)).current;

  // Load user on mount
  useEffect(() => {
    (async () => {
      const savedUser = await getUser();
      const savedDebug = await getDebugLocation();
      if (savedDebug) {
        setDebugLocationState(savedDebug);
        setDebugLat(String(savedDebug.lat));
        setDebugLng(String(savedDebug.lng));
        setDebugEnabled(savedDebug.enabled);
      }
      if (savedUser) {
        setUser(savedUser);
        setAppState("idle");
      } else {
        setAppState("onboarding");
      }
    })();
  }, []);

  // Pulsing animation loop when recording
  useEffect(() => {
    if (appState !== "recording") {
      pulseAnim.setValue(1);
      return;
    }

    const animation = Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, {
          toValue: 0.3,
          duration: 1000,
          useNativeDriver: true,
        }),
        Animated.timing(pulseAnim, {
          toValue: 1,
          duration: 1000,
          useNativeDriver: true,
        }),
      ])
    );
    animation.start();
    return () => animation.stop();
  }, [appState, pulseAnim]);

  // Poll point count while recording
  useEffect(() => {
    if (appState !== "recording" || !trailId) return;

    const interval = setInterval(async () => {
      const pts = await getPoints(trailId);
      setPointCount(pts.length);
    }, 2000);

    return () => clearInterval(interval);
  }, [appState, trailId]);

  // Load previous point count when idle
  useEffect(() => {
    if (appState === "idle" && trailId) {
      (async () => {
        const pts = await getPoints(trailId);
        setPointCount(pts.length);
      })();
    }
  }, [appState, trailId]);

  const handleGetStarted = async () => {
    const trimmed = displayName.trim();
    if (!trimmed) {
      Alert.alert("Name required", "Please enter a display name.");
      return;
    }

    const created = await createUser(trimmed);
    if (created) {
      await saveUser(created);
      setUser(created);
      setAppState("idle");
    } else {
      Alert.alert(
        "Connection Error",
        "Could not reach the server. Please try again."
      );
    }
  };

  const handleStartRecording = async () => {
    if (!user) return;

    const trail = await createTrail(DEFAULT_SHOW.id, user.id);
    if (!trail) {
      Alert.alert(
        "Connection Error",
        "Could not create trail. Please try again."
      );
      return;
    }

    setTrailId(trail.id);
    setPointCount(0);
    setUploadError(false);

    const started = await startTracking(trail.id);
    if (started) {
      setAppState("recording");
    } else {
      Alert.alert(
        "Permission Denied",
        "Location permissions are required to record trails."
      );
    }
  };

  const handleStopRecording = async () => {
    await stopTracking();

    if (!trailId) {
      setAppState("idle");
      return;
    }

    await doUpload(trailId);
  };

  const doUpload = async (id: string) => {
    setAppState("uploading");
    setUploadError(false);

    const pts = await getPoints(id);
    if (pts.length === 0) {
      await finishTrail(id);
      await clearPoints(id);
      setTrailId(null);
      setPointCount(0);
      setAppState("idle");
      return;
    }

    const uploaded = await uploadPoints(id, pts);
    if (!uploaded) {
      setUploadError(true);
      setAppState("idle");
      return;
    }

    const finished = await finishTrail(id);
    if (!finished) {
      // Points uploaded but finish failed -- still clear local data
      console.warn("finishTrail failed, but points were uploaded");
    }

    await clearPoints(id);
    setTrailId(null);
    setPointCount(0);
    setAppState("idle");
  };

  const handleRetryUpload = async () => {
    if (!trailId) return;
    await doUpload(trailId);
  };

  const handleSaveDebug = async () => {
    const lat = parseFloat(debugLat);
    const lng = parseFloat(debugLng);
    if (isNaN(lat) || isNaN(lng)) {
      Alert.alert("Invalid", "Please enter valid lat/lng numbers.");
      return;
    }
    const loc: DebugLocation = { lat, lng, enabled: debugEnabled };
    await saveDebugLocation(loc);
    setDebugLocationState(loc);
  };

  const handleToggleDebug = async (value: boolean) => {
    setDebugEnabled(value);
    const lat = parseFloat(debugLat) || 0;
    const lng = parseFloat(debugLng) || 0;
    const loc: DebugLocation = { lat, lng, enabled: value };
    await saveDebugLocation(loc);
    setDebugLocationState(loc);
  };

  // Render onboarding
  if (appState === "loading") {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar style="light" />
        <Text style={styles.title}>Desire Trails</Text>
      </SafeAreaView>
    );
  }

  if (appState === "onboarding") {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar style="light" />
        <Text style={styles.title}>Desire Trails</Text>
        <Text style={styles.subtitle}>Enter your name to get started</Text>
        <TextInput
          style={styles.input}
          placeholder="Display name"
          placeholderTextColor="#666"
          value={displayName}
          onChangeText={setDisplayName}
          autoCapitalize="words"
          autoCorrect={false}
        />
        <TouchableOpacity style={styles.button} onPress={handleGetStarted}>
          <Text style={styles.buttonText}>Get Started</Text>
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  // Main screen (idle / recording / uploading)
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="light" />

      {/* Debug button */}
      <TouchableOpacity
        style={styles.debugButton}
        onPress={() => setShowDebug(true)}
      >
        <Text style={styles.debugButtonText}>Debug</Text>
      </TouchableOpacity>

      <Text style={styles.title}>Desire Trails</Text>

      {appState === "uploading" && (
        <View style={styles.section}>
          <Text style={styles.statusText}>Uploading points...</Text>
        </View>
      )}

      {(appState === "idle" || appState === "uploading") && (
        <View style={styles.section}>
          <Text style={styles.welcomeText}>
            Welcome back, {user?.display_name}
          </Text>
          <Text style={styles.showName}>{DEFAULT_SHOW.name}</Text>

          {uploadError && trailId && (
            <View style={styles.errorContainer}>
              <Text style={styles.errorText}>
                Upload failed. Points are saved locally.
              </Text>
              <TouchableOpacity
                style={styles.retryButton}
                onPress={handleRetryUpload}
              >
                <Text style={styles.buttonText}>Retry Upload</Text>
              </TouchableOpacity>
            </View>
          )}

          {pointCount > 0 && !uploadError && (
            <Text style={styles.pointCount}>
              {pointCount} points from previous session
            </Text>
          )}

          {debugLocation?.enabled && (
            <Text style={styles.debugInfo}>
              Debug override: {debugLocation.lat.toFixed(4)},{" "}
              {debugLocation.lng.toFixed(4)}
            </Text>
          )}

          <TouchableOpacity
            style={[
              styles.button,
              appState === "uploading" && styles.buttonDisabled,
            ]}
            onPress={handleStartRecording}
            disabled={appState === "uploading"}
          >
            <Text style={styles.buttonText}>Start Recording</Text>
          </TouchableOpacity>
        </View>
      )}

      {appState === "recording" && (
        <View style={styles.section}>
          <View style={styles.recordingRow}>
            <Animated.View
              style={[styles.recordingDot, { opacity: pulseAnim }]}
            />
            <Text style={styles.recordingText}>Recording...</Text>
          </View>

          <Text style={styles.pointCount}>
            {pointCount} points captured
          </Text>

          {debugLocation?.enabled && (
            <Text style={styles.debugInfo}>
              Debug override: {debugLocation.lat.toFixed(4)},{" "}
              {debugLocation.lng.toFixed(4)}
            </Text>
          )}

          <TouchableOpacity
            style={[styles.button, styles.stopButton]}
            onPress={handleStopRecording}
          >
            <Text style={styles.buttonText}>Stop Recording</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Debug Modal */}
      <Modal
        visible={showDebug}
        transparent
        animationType="slide"
        onRequestClose={() => setShowDebug(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Debug Menu</Text>

            <Text style={styles.label}>Latitude</Text>
            <TextInput
              style={styles.input}
              placeholder="e.g. 40.7128"
              placeholderTextColor="#666"
              value={debugLat}
              onChangeText={setDebugLat}
              keyboardType="numeric"
            />

            <Text style={styles.label}>Longitude</Text>
            <TextInput
              style={styles.input}
              placeholder="e.g. -74.006"
              placeholderTextColor="#666"
              value={debugLng}
              onChangeText={setDebugLng}
              keyboardType="numeric"
            />

            <View style={styles.switchRow}>
              <Text style={styles.switchLabel}>Use Override Location</Text>
              <Switch
                value={debugEnabled}
                onValueChange={handleToggleDebug}
                trackColor={{ false: "#333", true: "#4a9" }}
                thumbColor="#fff"
              />
            </View>

            <TouchableOpacity style={styles.button} onPress={handleSaveDebug}>
              <Text style={styles.buttonText}>Save</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.button, styles.closeButton]}
              onPress={() => setShowDebug(false)}
            >
              <Text style={styles.buttonText}>Close</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#111",
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  section: {
    alignItems: "center",
    width: "100%",
  },
  title: {
    color: "#fff",
    fontSize: 28,
    fontWeight: "bold",
    marginBottom: 8,
  },
  subtitle: {
    color: "#999",
    fontSize: 16,
    marginBottom: 24,
  },
  welcomeText: {
    color: "#ccc",
    fontSize: 18,
    marginBottom: 8,
  },
  showName: {
    color: "#fff",
    fontSize: 16,
    fontStyle: "italic",
    marginBottom: 24,
  },
  input: {
    width: "100%",
    borderWidth: 1,
    borderColor: "#444",
    borderRadius: 8,
    padding: 14,
    color: "#fff",
    fontSize: 16,
    marginBottom: 16,
  },
  button: {
    width: "100%",
    borderWidth: 1,
    borderColor: "#fff",
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: "center",
    marginBottom: 12,
  },
  buttonDisabled: {
    borderColor: "#444",
    opacity: 0.5,
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  stopButton: {
    borderColor: "#e55",
  },
  retryButton: {
    width: "100%",
    borderWidth: 1,
    borderColor: "#f90",
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: "center",
    marginBottom: 12,
  },
  recordingRow: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 16,
  },
  recordingDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: "#e55",
    marginRight: 8,
  },
  recordingText: {
    color: "#fff",
    fontSize: 20,
    fontWeight: "600",
  },
  pointCount: {
    color: "#999",
    fontSize: 14,
    marginBottom: 24,
  },
  statusText: {
    color: "#999",
    fontSize: 14,
    marginBottom: 12,
  },
  errorContainer: {
    width: "100%",
    marginBottom: 16,
  },
  errorText: {
    color: "#f90",
    fontSize: 14,
    marginBottom: 12,
    textAlign: "center",
  },
  debugButton: {
    position: "absolute",
    top: 50,
    right: 16,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderWidth: 1,
    borderColor: "#333",
    borderRadius: 4,
  },
  debugButtonText: {
    color: "#666",
    fontSize: 12,
  },
  debugInfo: {
    color: "#4a9",
    fontSize: 12,
    marginBottom: 16,
  },
  // Modal
  modalOverlay: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.85)",
    justifyContent: "center",
    padding: 24,
  },
  modalContent: {
    backgroundColor: "#222",
    borderRadius: 12,
    padding: 24,
  },
  modalTitle: {
    color: "#fff",
    fontSize: 20,
    fontWeight: "bold",
    marginBottom: 20,
    textAlign: "center",
  },
  label: {
    color: "#999",
    fontSize: 13,
    marginBottom: 4,
  },
  switchRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 20,
    paddingVertical: 8,
  },
  switchLabel: {
    color: "#fff",
    fontSize: 16,
  },
  closeButton: {
    borderColor: "#666",
  },
});
