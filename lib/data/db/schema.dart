/// SQLite schema for Project सत्र.
///
/// Every table that participates in LAN sync carries the same four trailing
/// columns:
///
///   `updated_at` — millisecond epoch of the last write, the merge watermark
///   `deleted`    — tombstone flag; rows are never hard-deleted, so a deletion
///                  propagates like any other change
///   `node`       — id of the install that made the write, used to break
///                  last-write-wins ties deterministically
///   `dirty`      — set locally on write, cleared once the hub has accepted it
///
/// Credential material deliberately lives in tables that are *not* in
/// [kSyncedTables]. That is the whole enforcement mechanism for "hashes must
/// not end up on every machine": the sync engine can only ever see tables it
/// is told about.
library;

const int kSchemaVersion = 1;

/// Tables replicated between an install and its hub, in dependency order so
/// that a bulk apply never violates a foreign key.
const List<String> kSyncedTables = [
  'users',
  'patients',
  'medicines',
  'visits',
  'symptoms',
  'prescriptions',
  'prescription_items',
  'stock_movements',
  'appointments',
  'audit_log',
];

/// Columns common to every synced table.
const String _syncColumns = '''
  updated_at INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0,
  node       TEXT    NOT NULL,
  dirty      INTEGER NOT NULL DEFAULT 1
''';

const List<String> kCreateStatements = [
  // ---- Staff -------------------------------------------------------------
  '''
  CREATE TABLE IF NOT EXISTS users (
    id          TEXT PRIMARY KEY,
    username    TEXT NOT NULL,
    full_name   TEXT NOT NULL,
    role        TEXT NOT NULL,
    speciality  TEXT,
    phone       TEXT,
    email       TEXT,
    active      INTEGER NOT NULL DEFAULT 1,
    created_by  TEXT,
    created_at  INTEGER NOT NULL,
    $_syncColumns
  )''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(username)',

  // Password material for accounts this install is authoritative for.
  // Only ever populated on a hub. Never listed in kSyncedTables.
  '''
  CREATE TABLE IF NOT EXISTS user_credentials (
    user_id    TEXT PRIMARY KEY,
    algo       TEXT NOT NULL,
    salt       TEXT NOT NULL,
    iterations INTEGER NOT NULL,
    hash       TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
  )''',

  // Offline-login verifier cached on *this* machine for users who have
  // actually signed in here. Derived independently of the hub's hash with a
  // local salt, so it cannot be replayed against the hub.
  '''
  CREATE TABLE IF NOT EXISTS local_credentials (
    user_id    TEXT PRIMARY KEY,
    username   TEXT NOT NULL,
    algo       TEXT NOT NULL,
    salt       TEXT NOT NULL,
    iterations INTEGER NOT NULL,
    hash       TEXT NOT NULL,
    cached_at  INTEGER NOT NULL
  )''',

  // Sessions issued by a hub to its clients.
  '''
  CREATE TABLE IF NOT EXISTS sessions (
    token      TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL,
    issued_at  INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
  )''',

  // ---- Patients ----------------------------------------------------------
  '''
  CREATE TABLE IF NOT EXISTS patients (
    id               TEXT PRIMARY KEY,
    code             TEXT NOT NULL,
    name             TEXT NOT NULL,
    age              INTEGER,
    sex              TEXT NOT NULL DEFAULT 'other',
    weight_kg        REAL,
    address          TEXT,
    phone            TEXT,
    chief_complaints TEXT,
    notes            TEXT,
    assigned_to      TEXT,
    registered_at    INTEGER NOT NULL,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_patients_name ON patients(name)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_patients_code ON patients(code)',

  // A consultation. Symptom readings and prescriptions hang off a visit so the
  // clinic can see how a patient moved between appointments.
  '''
  CREATE TABLE IF NOT EXISTS visits (
    id               TEXT PRIMARY KEY,
    patient_id       TEXT NOT NULL,
    appointment_id   TEXT,
    visited_at       INTEGER NOT NULL,
    weight_kg        REAL,
    chief_complaints TEXT,
    findings         TEXT,
    advice           TEXT,
    recorded_by      TEXT,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_visits_patient ON visits(patient_id, visited_at)',

  // One graded reading. `value` holds a level name, or an ISO date for LMP.
  '''
  CREATE TABLE IF NOT EXISTS symptoms (
    id         TEXT PRIMARY KEY,
    visit_id   TEXT NOT NULL,
    patient_id TEXT NOT NULL,
    key        TEXT NOT NULL,
    value      TEXT NOT NULL,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_symptoms_visit ON symptoms(visit_id)',
  'CREATE INDEX IF NOT EXISTS idx_symptoms_patient ON symptoms(patient_id, key)',

  // ---- Pharmacy ----------------------------------------------------------
  '''
  CREATE TABLE IF NOT EXISTS medicines (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    form          TEXT NOT NULL,
    strength      TEXT,
    unit          TEXT NOT NULL DEFAULT 'unit',
    stock_qty     INTEGER NOT NULL DEFAULT 0,
    reorder_level INTEGER NOT NULL DEFAULT 0,
    notes         TEXT,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_medicines_name ON medicines(name)',

  // Append-only ledger. `stock_qty` on medicines is the running total, kept in
  // step by MedicineRepository so the UI never has to sum the ledger.
  '''
  CREATE TABLE IF NOT EXISTS stock_movements (
    id          TEXT PRIMARY KEY,
    medicine_id TEXT NOT NULL,
    delta       INTEGER NOT NULL,
    reason      TEXT NOT NULL,
    reference   TEXT,
    moved_at    INTEGER NOT NULL,
    by_user     TEXT,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_stock_medicine ON stock_movements(medicine_id, moved_at)',

  '''
  CREATE TABLE IF NOT EXISTS prescriptions (
    id             TEXT PRIMARY KEY,
    patient_id     TEXT NOT NULL,
    visit_id       TEXT,
    prescribed_by  TEXT,
    prescribed_at  INTEGER NOT NULL,
    notes          TEXT,
    dispensed      INTEGER NOT NULL DEFAULT 0,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_presc_patient ON prescriptions(patient_id, prescribed_at)',

  '''
  CREATE TABLE IF NOT EXISTS prescription_items (
    id              TEXT PRIMARY KEY,
    prescription_id TEXT NOT NULL,
    medicine_id     TEXT NOT NULL,
    dose            TEXT NOT NULL,
    duration_days   INTEGER NOT NULL DEFAULT 1,
    quantity        INTEGER NOT NULL DEFAULT 0,
    instructions    TEXT,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_presc_items ON prescription_items(prescription_id)',

  // ---- Scheduling --------------------------------------------------------
  '''
  CREATE TABLE IF NOT EXISTS appointments (
    id           TEXT PRIMARY KEY,
    patient_id   TEXT NOT NULL,
    staff_id     TEXT,
    scheduled_at INTEGER NOT NULL,
    duration_min INTEGER NOT NULL DEFAULT 15,
    status       TEXT NOT NULL DEFAULT 'scheduled',
    reason       TEXT,
    notes        TEXT,
    created_by   TEXT,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_appt_when ON appointments(scheduled_at)',
  'CREATE INDEX IF NOT EXISTS idx_appt_patient ON appointments(patient_id)',

  // ---- Bookkeeping -------------------------------------------------------
  '''
  CREATE TABLE IF NOT EXISTS audit_log (
    id        TEXT PRIMARY KEY,
    at        INTEGER NOT NULL,
    user_id   TEXT,
    user_name TEXT,
    action    TEXT NOT NULL,
    entity    TEXT,
    entity_id TEXT,
    detail    TEXT,
    $_syncColumns
  )''',
  'CREATE INDEX IF NOT EXISTS idx_audit_at ON audit_log(at)',

  // Local-only key/value store: node identity, hub address, sync watermarks,
  // clinic name. Never replicated — each install has its own.
  '''
  CREATE TABLE IF NOT EXISTS app_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )''',
];
