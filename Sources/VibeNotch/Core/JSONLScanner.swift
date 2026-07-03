import Foundation

/// Cached per-file parse state, shared by both providers. Invalidated when
/// (mtime, size) changes. Holds all entries newer than the retention cutoff so
/// a provider can compute both today's totals and the rolling block from one
/// list without re-reading the file.
///
/// Generic over `Entry` because Claude and Codex keep different per-line
/// payloads (a billed assistant turn vs a token_count delta), but share the
/// exact same incremental-read bookkeeping.
struct FileCache<Entry> {
    var mtime: Date
    var size: UInt64
    var parsedToOffset: Int   // bytes already parsed from the start
    var entries: [Entry]      // chronological
}

/// Incremental JSONL reader. Seeks to `offset`, splits the tail into lines,
/// and — for lines containing the literal bytes of `marker` — invokes `body`
/// with the raw line `Data`. Lines without the marker are skipped without any
/// JSON decoding (the cheap path for the dominant uninteresting events).
///
/// Returns the new `parsedToOffset` (offset + bytes consumed up to the last
/// complete line). An unterminated final line is deferred until its newline
/// arrives. On read failure, returns `fileSize` so the caller doesn't retry
/// the same bytes forever.
enum JSONLScanner {
    /// Chunk size for the incremental read. Bounded so a first-launch parse of
    /// a multi-hundred-MB session file doesn't materialize the whole file in
    /// memory the way `readToEnd()` did — only one chunk (plus any partial
    /// line carried across the boundary) is resident at a time.
    private static let chunkSize = 4 << 20   // 4 MB

    static func scanAppended(url: URL,
                             from offset: Int,
                             fileSize: UInt64,
                             marker: [UInt8],
                             body: (Data) -> Void) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Int(fileSize)
        }
        defer { try? handle.close() }
        if offset > 0 {
            do { try handle.seek(toOffset: UInt64(offset)) }
            catch { return Int(fileSize) }
        }

        var totalRead = 0
        var carry = Data()   // partial line spilling over a chunk boundary
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            totalRead += chunk.count
            let data = carry.isEmpty ? chunk : carry + chunk
            var lastLineEnd = 0   // index just past the last '\n' seen
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                let buf = UnsafeBufferPointer(start: base, count: data.count)
                var lineStart = 0
                for idx in 0..<buf.count {
                    if buf[idx] == 0x0A {
                        if idx > lineStart,
                           containsMarker(buf, lineStart: lineStart, lineEnd: idx, marker: marker) {
                            let lineData = Data(bytes: buf.baseAddress!.advanced(by: lineStart),
                                                count: idx - lineStart)
                            body(lineData)
                        }
                        lineStart = idx + 1
                        lastLineEnd = lineStart
                    }
                }
            }
            carry = lastLineEnd < data.count
                ? data.subdata(in: lastLineEnd..<data.count)
                : Data()
        }
        // Nothing read at all (error or already at EOF): report the file as
        // fully consumed so the caller doesn't retry the same bytes forever.
        if totalRead == 0 { return Int(fileSize) }
        // The trailing `carry` is an unterminated final line — leave it for
        // the next poll, once its newline has been written.
        return offset + totalRead - carry.count
    }

    /// True if `marker` occurs as a byte subsequence within `[lineStart, lineEnd)`.
    static func containsMarker(_ buf: UnsafeBufferPointer<UInt8>,
                               lineStart: Int, lineEnd: Int,
                               marker: [UInt8]) -> Bool {
        let lineLen = lineEnd - lineStart
        guard lineLen >= marker.count, !marker.isEmpty else { return false }
        let limit = lineEnd - marker.count
        var i = lineStart
        while i <= limit {
            if buf[i] == marker[0] {
                var match = true
                for j in 1..<marker.count {
                    if buf[i + j] != marker[j] { match = false; break }
                }
                if match { return true }
            }
            i += 1
        }
        return false
    }

    /// Reads the first `maxBytes` of `url` and returns its complete lines in
    /// file order (oldest-first). Used as a fallback for tail scans that come
    /// up empty: a session's model is set in an early `turn_context` /
    /// `session_meta` line, which can sit far enough from EOF (Codex writes
    /// very large lines) that a fixed-size tail window misses it. The final,
    /// possibly-incomplete line is dropped to avoid feeding a truncated JSON.
    static func headLines(url: URL, maxBytes: UInt64 = 65536) -> [Data]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: Int(maxBytes)), !head.isEmpty else { return nil }

        var lines: [Data] = []
        var lineStart = 0
        for i in 0..<head.count {
            if head[i] == 0x0A {
                if i > lineStart { lines.append(head.subdata(in: lineStart..<i)) }
                lineStart = i + 1
            }
        }
        // Trailing bytes after the last newline are an incomplete line — skip.
        return lines
    }

    /// Reads the last `maxBytes` of `url` and returns its lines in
    /// most-recent-first order. Used for tail scans (current model / work
    /// state) that only care about the end of the file.
    static func tailLines(url: URL, maxBytes: UInt64 = 65536) -> [Data]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let endOffset = (try? handle.seekToEnd()) ?? 0
        let offset: UInt64 = endOffset > maxBytes ? endOffset - maxBytes : 0
        try? handle.seek(toOffset: offset)
        guard let tail = try? handle.readToEnd() else { return nil }

        var lines: [Data] = []
        var lineEnd = tail.count
        for i in stride(from: tail.count - 1, through: 0, by: -1) {
            if tail[i] == 0x0A {
                if i + 1 < lineEnd {
                    lines.append(tail.subdata(in: (i + 1)..<lineEnd))
                }
                lineEnd = i
            }
        }
        if lineEnd > 0 { lines.append(tail.subdata(in: 0..<lineEnd)) }
        return lines
    }
}
