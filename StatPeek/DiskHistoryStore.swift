import Foundation
import SQLite3

final class DiskHistoryStore {
    private var database: OpaquePointer?

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StatPeek", isDirectory: true).appendingPathComponent("disk-history.sqlite")
    }

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            sqlite3_close(database)
            database = nil
            throw DiskHistoryError.storage(message)
        }
        sqlite3_busy_timeout(database, 2000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("""
            CREATE TABLE IF NOT EXISTS disk_samples (
                id INTEGER PRIMARY KEY,
                sampled_at REAL NOT NULL,
                available_bytes INTEGER NOT NULL CHECK(available_bytes >= 0),
                volume_id TEXT NOT NULL CHECK(length(volume_id) > 0)
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS disk_sample_time ON disk_samples(sampled_at)")
    }

    deinit { sqlite3_close(database) }

    @discardableResult
    func append(_ sample: DiskSample) throws -> DiskSample {
        guard sample.availableBytes >= 0, !sample.volumeID.isEmpty,
              sample.date.timeIntervalSince1970.isFinite else { throw DiskHistoryError.invalidSample }
        let statement = try prepare("INSERT INTO disk_samples(sampled_at, available_bytes, volume_id) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, sample.date.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 2, sample.availableBytes)
        sqlite3_bind_text(statement, 3, sample.volumeID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        var saved = sample
        saved.id = sqlite3_last_insert_rowid(database)
        return saved
    }

    func latestSamples() throws -> [DiskSample] {
        try read("SELECT id, sampled_at, available_bytes, volume_id FROM disk_samples ORDER BY id DESC LIMIT 2").reversed()
    }

    func samples(since date: Date?) throws -> [DiskSample] {
        try read("SELECT id, sampled_at, available_bytes, volume_id FROM disk_samples "
                 + (date == nil ? "" : "WHERE sampled_at >= ? ") + "ORDER BY id", since: date)
    }

    func count() throws -> Int {
        let statement = try prepare("SELECT count(*) FROM disk_samples")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func read(_ sql: String, since date: Date? = nil) throws -> [DiskSample] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if let date { sqlite3_bind_double(statement, 1, date.timeIntervalSince1970) }
        var samples: [DiskSample] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let volume = sqlite3_column_text(statement, 3) else { throw DiskHistoryError.invalidSample }
                samples.append(DiskSample(id: sqlite3_column_int64(statement, 0),
                                          date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                                          availableBytes: sqlite3_column_int64(statement, 2),
                                          volumeID: String(cString: volume)))
            case SQLITE_DONE: return samples
            default: throw failure()
            }
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw failure()
        }
        return statement
    }

    private func failure() -> DiskHistoryError {
        .storage(database.map { String(cString: sqlite3_errmsg($0)) } ?? "数据库不可用")
    }
}
