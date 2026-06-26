//! SQLCipher borrowers-vault access. Opens a zetetic-written `borrowers.db`
//! using the raw 32-byte key fed to `sqlite3_key()` — the exact mechanism
//! zetetic's `SupportOpenHelperFactory(byte[])` uses (verified in Step 0:
//! rusqlite-4.5.7 opens a zetetic-4.5.4 DB this way).
//!
//! NOT `PRAGMA key='x'..'` (raw-key hex mode) and NOT a UTF-8 string passphrase.

use rusqlite::Connection;
use std::ffi::{c_int, c_void};
use zeroize::Zeroizing;

extern "C" {
    fn sqlite3_key(
        db: *mut libsqlite3_sys::sqlite3,
        p_key: *const c_void,
        n_key: c_int,
    ) -> c_int;
}

#[derive(Debug)]
pub enum VaultError {
    Open(String),
    Key(String),
    Read(String),
    /// A write failed because it would violate a DB constraint — most
    /// importantly the `loans.borrower_id` FK `ON DELETE RESTRICT` (deleting a
    /// borrower who still has loans). Surfaced distinctly so the UI can say
    /// "this borrower still has active loans" rather than a generic error.
    Constraint(String),
    /// A write affected zero rows where one was expected (e.g. update/delete of
    /// a non-existent id). Lets callers distinguish "not found" from success.
    NotFound,
}

/// One borrower row (4 columns, matches BorrowersDatabase/1.json `borrowers`).
#[derive(Debug, Clone)]
pub struct BorrowerRow {
    pub id: i64,
    pub name: Option<String>,
    pub contact: Option<String>,
    pub notes: Option<String>,
}

/// One loan row (7 columns, matches `loans`). Dates are epoch millis.
#[derive(Debug, Clone)]
pub struct LoanRow {
    pub id: i64,
    pub book_id: i64,
    pub borrower_id: i64,
    pub lent_date: Option<i64>,
    pub due_date: Option<i64>,
    pub returned_date: Option<i64>,
    pub notes: Option<String>,
}

/// Exhaustive vault contents read out of a legacy `borrowers.db`.
#[derive(Debug, Default)]
pub struct VaultData {
    pub borrowers: Vec<BorrowerRow>,
    pub loans: Vec<LoanRow>,
}

/// The `borrowers` + `loans` schema, byte-for-byte the column contract from
/// `BorrowersDatabase/1.json` (Room). Single source of truth so a freshly
/// CREATED vault (#26) is identical to what Kotlin/restore produce — including
/// the `loans.borrower_id` FK ON DELETE RESTRICT that the write path enforces.
pub const SCHEMA_SQL: &str = "CREATE TABLE IF NOT EXISTS borrowers(
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        name TEXT NOT NULL, contact TEXT, notes TEXT);
     CREATE TABLE IF NOT EXISTS loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        book_id INTEGER NOT NULL, borrower_id INTEGER NOT NULL,
        lent_date INTEGER NOT NULL, due_date INTEGER,
        returned_date INTEGER, notes TEXT,
        FOREIGN KEY(borrower_id) REFERENCES borrowers(id)
            ON UPDATE NO ACTION ON DELETE RESTRICT);";

/// Creates a NEW empty `borrowers.db` at `db_path`, encrypted under `vault_key`
/// via SQLCipher `sqlite3_key`, with the canonical [SCHEMA_SQL]. Fails if a
/// file already exists at the path (refuse to clobber an existing vault —
/// fail-closed; the caller decides whether to overwrite). The key never leaves
/// this function.
pub fn create_vault(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
) -> Result<(), VaultError> {
    if std::path::Path::new(db_path).exists() {
        return Err(VaultError::Open(format!(
            "refusing to overwrite existing file at {db_path}"
        )));
    }
    let conn = Connection::open(db_path)
        .map_err(|e| VaultError::Open(e.to_string()))?;
    let rc = unsafe {
        sqlite3_key(
            conn.handle(),
            vault_key.as_ptr() as *const c_void,
            vault_key.len() as c_int,
        )
    };
    if rc != 0 {
        return Err(VaultError::Key(format!("sqlite3_key rc={rc}")));
    }
    conn.execute_batch(SCHEMA_SQL)
        .map_err(|e| VaultError::Open(format!("create schema: {e}")))?;
    Ok(())
}

/// Opens `db_path`, feeds `vault_key` to SQLCipher via the raw-bytes
/// `sqlite3_key` mechanism (the zetetic `SupportOpenHelperFactory(byte[])`
/// path), verifies the key by forcing a decryption, and optionally enables
/// foreign-key enforcement.
///
/// Single source of truth for opening the vault: both the read path
/// (`open_and_read`, `enforce_fk=false` — read-only, FK irrelevant) and the
/// write path (`enforce_fk=true` — honour `loans` ON DELETE RESTRICT) go
/// through here, so the proven keying + decrypt-check logic exists once.
///
/// SQLite needs `PRAGMA foreign_keys=ON` set **per connection** (it defaults
/// off); without it the schema's ON DELETE RESTRICT is silently ignored, so the
/// write path MUST pass `enforce_fk=true` to fail closed.
fn open_and_key(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
    enforce_fk: bool,
) -> Result<Connection, VaultError> {
    let conn = Connection::open(db_path)
        .map_err(|e| VaultError::Open(e.to_string()))?;

    let rc = unsafe {
        sqlite3_key(
            conn.handle(),
            vault_key.as_ptr() as *const c_void,
            vault_key.len() as c_int,
        )
    };
    if rc != 0 {
        return Err(VaultError::Key(format!("sqlite3_key rc={rc}")));
    }

    // Force decryption by touching the schema; a wrong key fails here.
    conn.query_row("SELECT count(*) FROM sqlite_master", [], |r| r.get::<_, i64>(0))
        .map_err(|e| VaultError::Key(format!("decrypt check failed: {e}")))?;

    if enforce_fk {
        conn.execute_batch("PRAGMA foreign_keys = ON;")
            .map_err(|e| VaultError::Open(format!("enable foreign_keys: {e}")))?;
    }

    Ok(conn)
}

/// Maps a rusqlite error to our typed [VaultError], distinguishing a constraint
/// violation (FK RESTRICT / NOT NULL) from a generic read/write failure.
fn map_sqlite_err(e: rusqlite::Error, context: &str) -> VaultError {
    if let rusqlite::Error::SqliteFailure(err, ref msg) = e {
        if err.code == rusqlite::ErrorCode::ConstraintViolation {
            return VaultError::Constraint(
                msg.clone().unwrap_or_else(|| context.to_string()),
            );
        }
    }
    VaultError::Read(format!("{context}: {e}"))
}

/// Opens `db_path` with `vault_key` (raw bytes → `sqlite3_key`) and reads every
/// borrower + loan row. The key is wiped by its `Zeroizing` owner on drop; it
/// never leaves this function.
pub fn open_and_read(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
) -> Result<VaultData, VaultError> {
    // Read-only: FK enforcement is irrelevant (no writes), so keep the proven
    // read behaviour byte-identical by leaving it off.
    let conn = open_and_key(db_path, vault_key, false)?;

    let mut data = VaultData::default();

    let mut stmt = conn
        .prepare("SELECT id, name, contact, notes FROM borrowers")
        .map_err(|e| VaultError::Read(e.to_string()))?;
    let rows = stmt
        .query_map([], |r| {
            Ok(BorrowerRow {
                id: r.get(0)?,
                name: r.get(1)?,
                contact: r.get(2)?,
                notes: r.get(3)?,
            })
        })
        .map_err(|e| VaultError::Read(e.to_string()))?;
    for row in rows {
        data.borrowers.push(row.map_err(|e| VaultError::Read(e.to_string()))?);
    }

    let mut stmt = conn
        .prepare(
            "SELECT id, book_id, borrower_id, lent_date, due_date, returned_date, notes FROM loans",
        )
        .map_err(|e| VaultError::Read(e.to_string()))?;
    let rows = stmt
        .query_map([], |r| {
            Ok(LoanRow {
                id: r.get(0)?,
                book_id: r.get(1)?,
                borrower_id: r.get(2)?,
                lent_date: r.get(3)?,
                due_date: r.get(4)?,
                returned_date: r.get(5)?,
                notes: r.get(6)?,
            })
        })
        .map_err(|e| VaultError::Read(e.to_string()))?;
    for row in rows {
        data.loans.push(row.map_err(|e| VaultError::Read(e.to_string()))?);
    }

    Ok(data)
}

// --- Write path (#25) -----------------------------------------------------
//
// All writes open the vault through `open_and_key(.., enforce_fk=true)`, so the
// schema's `loans.borrower_id ON DELETE RESTRICT` is honoured. Statements are
// parameterised (no string interpolation of values) and each function maps
// constraint violations to `VaultError::Constraint` so the UI can distinguish
// "borrower still has loans" / "NOT NULL violated" from a generic failure.
//
// `id` is INTEGER PRIMARY KEY AUTOINCREMENT in the schema, so inserts omit it
// and return the new rowid. The key never leaves these functions.

/// Fields for a new or updated borrower. `name` is NOT NULL in the schema.
#[derive(Debug, Clone)]
pub struct BorrowerInput {
    pub name: String,
    pub contact: Option<String>,
    pub notes: Option<String>,
}

/// Fields for a new or updated loan. `book_id`, `borrower_id`, `lent_date` are
/// NOT NULL in the schema; the rest are nullable.
#[derive(Debug, Clone)]
pub struct LoanInput {
    pub book_id: i64,
    pub borrower_id: i64,
    pub lent_date: i64,
    pub due_date: Option<i64>,
    pub returned_date: Option<i64>,
    pub notes: Option<String>,
}

/// Inserts a borrower and returns its new id.
pub fn insert_borrower(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
    input: &BorrowerInput,
) -> Result<i64, VaultError> {
    let conn = open_and_key(db_path, vault_key, true)?;
    conn.execute(
        "INSERT INTO borrowers(name, contact, notes) VALUES (?1, ?2, ?3)",
        rusqlite::params![input.name, input.contact, input.notes],
    )
    .map_err(|e| map_sqlite_err(e, "insert_borrower"))?;
    Ok(conn.last_insert_rowid())
}

/// Updates an existing borrower by id. Returns `NotFound` if no such row.
pub fn update_borrower(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
    id: i64,
    input: &BorrowerInput,
) -> Result<(), VaultError> {
    let conn = open_and_key(db_path, vault_key, true)?;
    let affected = conn
        .execute(
            "UPDATE borrowers SET name = ?1, contact = ?2, notes = ?3 WHERE id = ?4",
            rusqlite::params![input.name, input.contact, input.notes, id],
        )
        .map_err(|e| map_sqlite_err(e, "update_borrower"))?;
    if affected == 0 {
        return Err(VaultError::NotFound);
    }
    Ok(())
}

/// Deletes a borrower by id. Fails with `Constraint` if loans still reference
/// them (ON DELETE RESTRICT); `NotFound` if no such row.
pub fn delete_borrower(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
    id: i64,
) -> Result<(), VaultError> {
    let conn = open_and_key(db_path, vault_key, true)?;
    let affected = conn
        .execute("DELETE FROM borrowers WHERE id = ?1", rusqlite::params![id])
        .map_err(|e| map_sqlite_err(e, "delete_borrower"))?;
    if affected == 0 {
        return Err(VaultError::NotFound);
    }
    Ok(())
}

/// Inserts a loan and returns its new id. The `borrower_id` FK is enforced.
pub fn insert_loan(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
    input: &LoanInput,
) -> Result<i64, VaultError> {
    let conn = open_and_key(db_path, vault_key, true)?;
    conn.execute(
        "INSERT INTO loans(book_id, borrower_id, lent_date, due_date, returned_date, notes)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![
            input.book_id,
            input.borrower_id,
            input.lent_date,
            input.due_date,
            input.returned_date,
            input.notes,
        ],
    )
    .map_err(|e| map_sqlite_err(e, "insert_loan"))?;
    Ok(conn.last_insert_rowid())
}

/// Updates a loan by id. Returns `NotFound` if no such row.
pub fn update_loan(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
    id: i64,
    input: &LoanInput,
) -> Result<(), VaultError> {
    let conn = open_and_key(db_path, vault_key, true)?;
    let affected = conn
        .execute(
            "UPDATE loans SET book_id = ?1, borrower_id = ?2, lent_date = ?3,
                 due_date = ?4, returned_date = ?5, notes = ?6 WHERE id = ?7",
            rusqlite::params![
                input.book_id,
                input.borrower_id,
                input.lent_date,
                input.due_date,
                input.returned_date,
                input.notes,
                id,
            ],
        )
        .map_err(|e| map_sqlite_err(e, "update_loan"))?;
    if affected == 0 {
        return Err(VaultError::NotFound);
    }
    Ok(())
}

/// Deletes a loan by id. Returns `NotFound` if no such row.
pub fn delete_loan(
    db_path: &str,
    vault_key: &Zeroizing<Vec<u8>>,
    id: i64,
) -> Result<(), VaultError> {
    let conn = open_and_key(db_path, vault_key, true)?;
    let affected = conn
        .execute("DELETE FROM loans WHERE id = ?1", rusqlite::params![id])
        .map_err(|e| map_sqlite_err(e, "delete_loan"))?;
    if affected == 0 {
        return Err(VaultError::NotFound);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    // Process-wide counter so concurrently-running tests never collide on a
    // temp path (a nanosecond timestamp alone CAN collide under parallelism,
    // which previously polluted one DB's rows into another and flaked the
    // autoincrement assertions).
    static COUNTER: AtomicU64 = AtomicU64::new(0);

    // A unique temp path for `prefix`, with any stale main/-wal/-shm files
    // removed so a leftover never leaks rows into a new test DB.
    fn unique_temp_path(prefix: &str) -> String {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let mut path = PathBuf::from(std::env::temp_dir());
        path.push(format!("{prefix}_{nanos}_{n}.db"));
        let path = path.to_string_lossy().into_owned();
        for suffix in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{path}{suffix}"));
        }
        path
    }

    // A fixed raw 32-byte key — the write functions are key-agnostic, so any
    // valid key works for a hermetic round-trip (no passphrase/Argon2 needed).
    fn test_key() -> Zeroizing<Vec<u8>> {
        Zeroizing::new((1u8..=32).collect())
    }

    // Creates a fresh SQLCipher DB at a unique temp path, keyed with `key`, with
    // the EXACT BorrowersDatabase/1.json schema (incl. the loans FK ON DELETE
    // RESTRICT). Returns the path; the caller removes it.
    fn fresh_vault(key: &Zeroizing<Vec<u8>>) -> String {
        let path = unique_temp_path("pitak_vault_write_test");
        let conn = Connection::open(&path).expect("open new db");
        let rc = unsafe {
            sqlite3_key(
                conn.handle(),
                key.as_ptr() as *const c_void,
                key.len() as c_int,
            )
        };
        assert_eq!(rc, 0, "sqlite3_key failed creating test db");
        conn.execute_batch(SCHEMA_SQL).expect("create schema");
        drop(conn);
        path
    }

    // Returns a fresh unique temp path WITHOUT creating the file (for
    // create_vault, which must own the file creation).
    fn fresh_path() -> String {
        unique_temp_path("pitak_vault_create_test")
    }

    fn cleanup(path: &str) {
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn insert_then_read_round_trips_borrower_and_loan() {
        let key = test_key();
        let db = fresh_vault(&key);

        let bid = insert_borrower(
            &db,
            &key,
            &BorrowerInput {
                name: "Asha".into(),
                contact: Some("555-0101".into()),
                notes: None,
            },
        )
        .expect("insert borrower");
        assert!(bid > 0, "autoincrement id assigned");

        let lid = insert_loan(
            &db,
            &key,
            &LoanInput {
                book_id: 7,
                borrower_id: bid,
                lent_date: 1_700_000_000_000,
                due_date: Some(1_700_600_000_000),
                returned_date: None,
                notes: Some("first loan".into()),
            },
        )
        .expect("insert loan");
        assert!(lid > 0);

        // Read back through the PROVEN read path — proves the writes landed in
        // the encrypted DB and decrypt correctly.
        let data = open_and_read(&db, &key).expect("read back");
        assert_eq!(data.borrowers.len(), 1);
        assert_eq!(data.borrowers[0].id, bid);
        assert_eq!(data.borrowers[0].name.as_deref(), Some("Asha"));
        assert_eq!(data.borrowers[0].contact.as_deref(), Some("555-0101"));
        assert_eq!(data.borrowers[0].notes, None);
        assert_eq!(data.loans.len(), 1);
        assert_eq!(data.loans[0].id, lid);
        assert_eq!(data.loans[0].borrower_id, bid);
        assert_eq!(data.loans[0].lent_date, Some(1_700_000_000_000));
        assert_eq!(data.loans[0].notes.as_deref(), Some("first loan"));

        cleanup(&db);
    }

    #[test]
    fn update_borrower_changes_columns() {
        let key = test_key();
        let db = fresh_vault(&key);
        let bid = insert_borrower(
            &db,
            &key,
            &BorrowerInput { name: "Old".into(), contact: None, notes: None },
        )
        .unwrap();

        update_borrower(
            &db,
            &key,
            bid,
            &BorrowerInput {
                name: "New".into(),
                contact: Some("x".into()),
                notes: Some("note".into()),
            },
        )
        .expect("update");

        let data = open_and_read(&db, &key).unwrap();
        assert_eq!(data.borrowers[0].name.as_deref(), Some("New"));
        assert_eq!(data.borrowers[0].contact.as_deref(), Some("x"));
        assert_eq!(data.borrowers[0].notes.as_deref(), Some("note"));
        cleanup(&db);
    }

    #[test]
    fn update_or_delete_missing_id_is_not_found() {
        let key = test_key();
        let db = fresh_vault(&key);

        let upd = update_borrower(
            &db,
            &key,
            999,
            &BorrowerInput { name: "X".into(), contact: None, notes: None },
        );
        assert!(matches!(upd, Err(VaultError::NotFound)), "got {upd:?}");

        let del = delete_borrower(&db, &key, 999);
        assert!(matches!(del, Err(VaultError::NotFound)), "got {del:?}");

        let del_loan = delete_loan(&db, &key, 999);
        assert!(matches!(del_loan, Err(VaultError::NotFound)), "got {del_loan:?}");
        cleanup(&db);
    }

    #[test]
    fn delete_borrower_with_loans_is_restricted() {
        let key = test_key();
        let db = fresh_vault(&key);
        let bid = insert_borrower(
            &db,
            &key,
            &BorrowerInput { name: "HasLoan".into(), contact: None, notes: None },
        )
        .unwrap();
        insert_loan(
            &db,
            &key,
            &LoanInput {
                book_id: 1,
                borrower_id: bid,
                lent_date: 1,
                due_date: None,
                returned_date: None,
                notes: None,
            },
        )
        .unwrap();

        // ON DELETE RESTRICT + PRAGMA foreign_keys=ON must block this.
        let res = delete_borrower(&db, &key, bid);
        assert!(
            matches!(res, Err(VaultError::Constraint(_))),
            "expected Constraint, got {res:?}"
        );

        // The borrower is still there (fail-closed: nothing was deleted).
        let data = open_and_read(&db, &key).unwrap();
        assert_eq!(data.borrowers.len(), 1);
        cleanup(&db);
    }

    #[test]
    fn insert_loan_for_missing_borrower_violates_fk() {
        let key = test_key();
        let db = fresh_vault(&key);
        let res = insert_loan(
            &db,
            &key,
            &LoanInput {
                book_id: 1,
                borrower_id: 4242, // no such borrower
                lent_date: 1,
                due_date: None,
                returned_date: None,
                notes: None,
            },
        );
        assert!(
            matches!(res, Err(VaultError::Constraint(_))),
            "expected Constraint (FK), got {res:?}"
        );
        cleanup(&db);
    }

    #[test]
    fn delete_borrower_succeeds_after_loan_removed() {
        let key = test_key();
        let db = fresh_vault(&key);
        let bid = insert_borrower(
            &db,
            &key,
            &BorrowerInput { name: "B".into(), contact: None, notes: None },
        )
        .unwrap();
        let lid = insert_loan(
            &db,
            &key,
            &LoanInput {
                book_id: 1,
                borrower_id: bid,
                lent_date: 1,
                due_date: None,
                returned_date: None,
                notes: None,
            },
        )
        .unwrap();

        delete_loan(&db, &key, lid).expect("delete loan");
        delete_borrower(&db, &key, bid).expect("delete borrower now allowed");

        let data = open_and_read(&db, &key).unwrap();
        assert!(data.borrowers.is_empty());
        assert!(data.loans.is_empty());
        cleanup(&db);
    }

    #[test]
    fn create_vault_makes_an_empty_readable_writable_db() {
        use crate::crypto::{generate_vault_key, unwrap_vault_key, wrap_vault_key, WrappedBlob};
        // End-to-end: generate key → wrap under a passphrase → create vault →
        // unwrap the blob back to the key → write+read. Proves a freshly created
        // vault is openable via the SAME proven unwrap path as a restored one.
        let key = generate_vault_key();
        let pass = b"new-vault-pass";
        let blob = wrap_vault_key(pass, &key).expect("wrap");
        let path = fresh_path();

        create_vault(&path, &key).expect("create vault");

        // A newly created vault reads as empty.
        let empty = open_and_read(&path, &key).expect("read fresh vault");
        assert!(empty.borrowers.is_empty());
        assert!(empty.loans.is_empty());

        // The wrapped blob unwraps to the same key the DB was created with.
        let parsed = WrappedBlob::parse(&blob).expect("parse blob");
        let recovered = unwrap_vault_key(pass, &parsed).expect("unwrap");
        let recovered_z: Zeroizing<Vec<u8>> = Zeroizing::new(recovered.to_vec());
        let bid = insert_borrower(
            &path,
            &recovered_z,
            &BorrowerInput { name: "First".into(), contact: None, notes: None },
        )
        .expect("write via unwrapped key");
        let data = open_and_read(&path, &recovered_z).unwrap();
        assert_eq!(data.borrowers.len(), 1);
        assert_eq!(data.borrowers[0].id, bid);
        cleanup(&path);
    }

    #[test]
    fn create_vault_refuses_to_clobber_existing_file() {
        let key = test_key();
        let db = fresh_vault(&key); // file now exists
        let res = create_vault(&db, &key);
        assert!(matches!(res, Err(VaultError::Open(_))), "got {res:?}");
        cleanup(&db);
    }

    #[test]
    fn wrong_key_cannot_open_for_write() {
        let key = test_key();
        let db = fresh_vault(&key);
        let wrong: Zeroizing<Vec<u8>> = Zeroizing::new(vec![9u8; 32]);
        let res = insert_borrower(
            &db,
            &wrong,
            &BorrowerInput { name: "X".into(), contact: None, notes: None },
        );
        // A wrong key fails the decrypt-check in open_and_key → Key error.
        assert!(matches!(res, Err(VaultError::Key(_))), "got {res:?}");
        cleanup(&db);
    }
}
