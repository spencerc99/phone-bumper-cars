CREATE TABLE shows (
  id TEXT PRIMARY KEY,
  name TEXT,
  lat REAL,
  lng REAL,
  radius_meters INTEGER,
  active INTEGER DEFAULT 1
);

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  display_name TEXT,
  color TEXT,
  created_at TEXT
);

CREATE TABLE trails (
  id TEXT PRIMARY KEY,
  show_id TEXT,
  user_id TEXT,
  started_at TEXT,
  ended_at TEXT,
  FOREIGN KEY (show_id) REFERENCES shows(id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE points (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trail_id TEXT,
  lat REAL,
  lng REAL,
  recorded_at TEXT,
  FOREIGN KEY (trail_id) REFERENCES trails(id)
);

-- Seed a test show
INSERT INTO shows (id, name, lat, lng, radius_meters, active)
VALUES ('test-show-1', 'Test Show', 40.7128, -74.0060, 5000, 1);
