-- Scratchpad schema — applied idempotently on first run (see Db.qml init()).

-- Single table stores both notes and todos, discriminated by `type`.
CREATE TABLE IF NOT EXISTS items (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  type       TEXT NOT NULL,                       -- 'note' or 'todo'
  title      TEXT NOT NULL,                       -- short summary / display title
  body       TEXT,                                -- long description / content
  status     INTEGER NOT NULL DEFAULT 0,          -- 0 = unread/in-progress, 1 = read/completed
  created_at INTEGER NOT NULL,                    -- unix timestamp (seconds)
  updated_at INTEGER NOT NULL                     -- unix timestamp (seconds)
);

-- Fast sort-by-pending-then-recent: status 0 (unread/in-progress) always
-- above status 1 (read/completed), newest first within each group.
CREATE INDEX IF NOT EXISTS idx_items_sort ON items(status, updated_at DESC);

-- Fast type filtering + pending counts.
CREATE INDEX IF NOT EXISTS idx_items_type_status ON items(type, status);

-- Read-only mutation log shown in the History tab.
CREATE TABLE IF NOT EXISTS history (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  type   TEXT NOT NULL,                           -- 'note' or 'todo'
  title  TEXT NOT NULL,                           -- item title at time of mutation
  action TEXT NOT NULL,                           -- added | completed | reopened | deleted
  ts     INTEGER NOT NULL                         -- unix timestamp (seconds)
);

-- History renders newest-first.
CREATE INDEX IF NOT EXISTS idx_history_ts ON history(ts DESC);
