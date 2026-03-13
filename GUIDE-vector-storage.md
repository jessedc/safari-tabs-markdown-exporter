# Storing Bookmarks & Summaries with sqlite-vec + Ollama

A fully local solution for storing Safari tab exports with semantic search using vector embeddings. No cloud APIs required.

## Architecture

```
Safari Tabs → export_tabs.py → text + summaries
                                      ↓
                              Ollama (nomic-embed-text)
                                      ↓
                              SQLite + sqlite-vec
                                      ↓
                              Semantic search queries
```

- **Ollama** runs `nomic-embed-text` locally to generate 768-dimension embeddings
- **sqlite-vec** adds vector search to a standard SQLite database
- Bookmarks, summaries, and embeddings all live in one `.db` file

---

## 1. Install Ollama

```bash
# Homebrew (CLI only)
brew install ollama

# Or the macOS app (includes menu bar icon, auto-starts server)
brew install --cask ollama-app
```

Start the server (CLI install only — the app starts it automatically):

```bash
ollama serve
# Runs on http://localhost:11434
```

Pull the embedding model:

```bash
ollama pull nomic-embed-text
```

### Model options

| Model | Params | Dimensions | Context | Notes |
|---|---|---|---|---|
| `nomic-embed-text` | 137M | 768 | 8,192 tokens | Best general choice, 56M+ pulls |
| `all-minilm` | 23M | 384 | 256 tokens | Smallest/fastest, short texts only |
| `mxbai-embed-large` | 335M | 1,024 | 512 tokens | Higher quality, larger |

`nomic-embed-text` is the recommended default — good quality, fast on Apple Silicon, long context window for page text.

---

## 2. Python Dependencies

For a `uv run --script` single-file script:

```python
# /// script
# requires-python = ">=3.11"
# dependencies = ["sqlite-vec", "ollama"]
# ///
```

Or install directly:

```bash
uv pip install sqlite-vec ollama
```

### macOS caveat

The system Python on macOS ships with a SQLite build that **does not support `load_extension`**. Use Homebrew Python or `uv`-managed Python (which you're already using).

---

## 3. Database Schema

```python
import sqlite3
import sqlite_vec
import struct

def connect(db_path: str) -> sqlite3.Connection:
    db = sqlite3.connect(db_path)
    db.enable_load_extension(True)
    sqlite_vec.load(db)
    db.enable_load_extension(False)
    return db

def init_db(db: sqlite3.Connection):
    db.executescript("""
        -- Bookmarks table (structured data)
        CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT UNIQUE NOT NULL,
            title TEXT,
            summary TEXT,
            page_text TEXT,
            window_num INTEGER,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );

        -- Vector table for semantic search
        CREATE VIRTUAL TABLE IF NOT EXISTS vec_bookmarks USING vec0(
            bookmark_id INTEGER PRIMARY KEY,
            embedding float[768] distance_metric=cosine
        );
    """)
```

Key design decisions:
- **Separate tables**: `bookmarks` holds structured data, `vec_bookmarks` holds embeddings. Joined via `bookmark_id` → `bookmarks.id`.
- **`float[768]`**: Matches `nomic-embed-text` output dimensions.
- **`distance_metric=cosine`**: Cosine similarity is standard for text embeddings. Distance range is 0 (identical) to 2 (opposite).
- **`url TEXT UNIQUE`**: Natural deduplication key.

---

## 4. Generating Embeddings with Ollama

### Using the `ollama` Python package

```python
import ollama

def embed_texts(texts: list[str]) -> list[list[float]]:
    """Embed multiple texts in a single batch call."""
    response = ollama.embed(
        model="nomic-embed-text",
        input=texts,
    )
    return response["embeddings"]

def embed_one(text: str) -> list[float]:
    """Embed a single text."""
    return embed_texts([text])[0]
```

### Using raw HTTP (no extra dependency)

```python
import requests

def embed_texts(texts: list[str]) -> list[list[float]]:
    response = requests.post(
        "http://localhost:11434/api/embed",
        json={"model": "nomic-embed-text", "input": texts},
    )
    response.raise_for_status()
    return response.json()["embeddings"]
```

### API details

- **Endpoint**: `POST http://localhost:11434/api/embed` (current, replaces deprecated `/api/embeddings`)
- **Batch support**: Pass a list of strings to `input` — returns a corresponding list in `embeddings`
- **Returns**: L2-normalized (unit-length) vectors
- **Truncation**: Enabled by default — inputs longer than the model's context window are truncated

### What text to embed

For best search results, concatenate meaningful fields:

```python
def make_embedding_text(title: str, summary: str, url: str) -> str:
    """Combine fields into a single string for embedding."""
    parts = []
    if title:
        parts.append(title)
    if summary:
        parts.append(summary)
    # Optionally include the URL domain for topical signal
    # parts.append(urlparse(url).netloc)
    return " — ".join(parts)
```

---

## 5. Inserting Bookmarks + Embeddings

```python
def serialize_f32(vector: list[float]) -> bytes:
    """Convert float list to compact binary format for sqlite-vec."""
    return struct.pack(f"{len(vector)}f", *vector)

def upsert_bookmark(
    db: sqlite3.Connection,
    url: str,
    title: str,
    summary: str,
    page_text: str,
    embedding: list[float],
    window_num: int | None = None,
):
    """Insert or update a bookmark and its embedding."""
    cursor = db.execute(
        """
        INSERT INTO bookmarks (url, title, summary, page_text, window_num, updated_at)
        VALUES (?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(url) DO UPDATE SET
            title = excluded.title,
            summary = excluded.summary,
            page_text = excluded.page_text,
            window_num = excluded.window_num,
            updated_at = datetime('now')
        RETURNING id
        """,
        (url, title, summary, page_text, window_num),
    )
    bookmark_id = cursor.fetchone()[0]

    # Replace embedding (delete + insert since vec0 doesn't support ON CONFLICT)
    db.execute("DELETE FROM vec_bookmarks WHERE bookmark_id = ?", (bookmark_id,))
    db.execute(
        "INSERT INTO vec_bookmarks (bookmark_id, embedding) VALUES (?, ?)",
        (bookmark_id, serialize_f32(embedding)),
    )
```

### Batch insert flow

```python
def store_tabs(db, tabs, summaries, texts):
    """Store a full tab export with embeddings."""
    # Build texts to embed
    to_embed = []
    for tab in tabs:
        url = tab["url"]
        title = tab.get("title", "")
        summary = summaries.get(url, "")
        to_embed.append(make_embedding_text(title, summary, url))

    # Batch embed
    embeddings = embed_texts(to_embed)

    # Insert all
    with db:
        for tab, embedding in zip(tabs, embeddings):
            url = tab["url"]
            upsert_bookmark(
                db,
                url=url,
                title=tab.get("title", ""),
                summary=summaries.get(url, ""),
                page_text=texts.get(url, ""),
                embedding=embedding,
                window_num=tab.get("window"),
            )
```

---

## 6. Semantic Search

```python
def search(db: sqlite3.Connection, query: str, limit: int = 10) -> list[dict]:
    """Search bookmarks by semantic similarity to a natural language query."""
    query_embedding = embed_one(query)

    rows = db.execute(
        """
        SELECT
            b.url,
            b.title,
            b.summary,
            v.distance
        FROM vec_bookmarks v
        JOIN bookmarks b ON b.id = v.bookmark_id
        WHERE v.embedding MATCH ?
        ORDER BY v.distance
        LIMIT ?
        """,
        (serialize_f32(query_embedding), limit),
    ).fetchall()

    return [
        {"url": r[0], "title": r[1], "summary": r[2], "distance": r[3]}
        for r in rows
    ]
```

### Using `k =` instead of `LIMIT` (for SQLite < 3.41)

```python
# If your SQLite version is older than 3.41, use this syntax instead:
rows = db.execute(
    """
    SELECT bookmark_id, distance
    FROM vec_bookmarks
    WHERE embedding MATCH ? AND k = ?
    """,
    (serialize_f32(query_embedding), limit),
).fetchall()
```

### Example queries

```python
# Find tabs about Python programming
results = search(db, "python programming tutorials")

# Find tabs about cooking recipes
results = search(db, "recipes and cooking techniques")

# Find tabs about machine learning papers
results = search(db, "recent ML research papers")

for r in results:
    print(f"[{r['distance']:.3f}] {r['title']}")
    print(f"  {r['summary']}")
    print(f"  {r['url']}\n")
```

---

## 7. Performance Characteristics

### sqlite-vec

- **Search method**: Brute-force with SIMD (NEON on Apple Silicon). No ANN index.
- **Sweet spot**: Up to ~100K vectors. More than enough for bookmarks.
- **Benchmarks** (M1 Mac, single query):
  - 10K vectors, 768D: sub-millisecond
  - 100K vectors, 768D: ~3ms
  - 1M vectors, 768D: ~30ms

### Ollama embedding speed

- `nomic-embed-text` on Apple Silicon: ~5-15ms per embedding
- Batch embedding is faster per-item than sequential calls
- First call after model load has ~1-2s warmup
- Model stays loaded for 5 minutes by default (`keep_alive` parameter)

### Storage size

- Each 768D float32 embedding: 3,072 bytes (768 × 4)
- 10,000 bookmarks with embeddings: ~30MB for vectors + text data
- The `.db` file is a single portable file

---

## 8. Useful SQL Queries

```sql
-- Count all bookmarks
SELECT COUNT(*) FROM bookmarks;

-- Recent bookmarks
SELECT title, url, created_at FROM bookmarks ORDER BY created_at DESC LIMIT 20;

-- Bookmarks without embeddings (if any failed)
SELECT b.id, b.url FROM bookmarks b
LEFT JOIN vec_bookmarks v ON v.bookmark_id = b.id
WHERE v.bookmark_id IS NULL;

-- Check SQLite and sqlite-vec versions
SELECT sqlite_version(), vec_version();

-- Inspect an embedding
SELECT vec_length(embedding), vec_type(embedding)
FROM vec_bookmarks LIMIT 1;

-- Manual cosine distance between two bookmarks
SELECT vec_distance_cosine(a.embedding, b.embedding)
FROM vec_bookmarks a, vec_bookmarks b
WHERE a.bookmark_id = 1 AND b.bookmark_id = 2;
```

---

## 9. Full Minimal Example

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["sqlite-vec", "ollama"]
# ///
"""Minimal example: store and search bookmarks with embeddings."""

import sqlite3
import struct
import sqlite_vec
import ollama

DB_PATH = "bookmarks.db"
EMBED_MODEL = "nomic-embed-text"


def serialize_f32(vec: list[float]) -> bytes:
    return struct.pack(f"{len(vec)}f", *vec)


def get_db() -> sqlite3.Connection:
    db = sqlite3.connect(DB_PATH)
    db.enable_load_extension(True)
    sqlite_vec.load(db)
    db.enable_load_extension(False)
    db.executescript("""
        CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT UNIQUE NOT NULL,
            title TEXT,
            summary TEXT
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS vec_bookmarks USING vec0(
            bookmark_id INTEGER PRIMARY KEY,
            embedding float[768] distance_metric=cosine
        );
    """)
    return db


def embed(texts: list[str]) -> list[list[float]]:
    return ollama.embed(model=EMBED_MODEL, input=texts)["embeddings"]


def add_bookmark(db, url, title, summary=""):
    text = f"{title} — {summary}" if summary else title
    [embedding] = embed([text])
    with db:
        cur = db.execute(
            "INSERT OR REPLACE INTO bookmarks (url, title, summary) VALUES (?, ?, ?) RETURNING id",
            (url, title, summary),
        )
        bid = cur.fetchone()[0]
        db.execute("DELETE FROM vec_bookmarks WHERE bookmark_id = ?", (bid,))
        db.execute(
            "INSERT INTO vec_bookmarks (bookmark_id, embedding) VALUES (?, ?)",
            (bid, serialize_f32(embedding)),
        )


def search(db, query, limit=5):
    [qvec] = embed([query])
    return db.execute(
        """
        SELECT b.title, b.url, b.summary, v.distance
        FROM vec_bookmarks v
        JOIN bookmarks b ON b.id = v.bookmark_id
        WHERE v.embedding MATCH ? ORDER BY v.distance LIMIT ?
        """,
        (serialize_f32(qvec), limit),
    ).fetchall()


if __name__ == "__main__":
    db = get_db()

    # Add some example bookmarks
    add_bookmark(db, "https://example.com/python", "Learn Python", "Beginner tutorial for Python programming")
    add_bookmark(db, "https://example.com/rust", "Rust Book", "The official Rust programming language guide")
    add_bookmark(db, "https://example.com/bread", "Sourdough Recipe", "How to bake sourdough bread at home")

    # Search
    for title, url, summary, dist in search(db, "programming languages"):
        print(f"  [{dist:.3f}] {title}: {summary}")
```

---

## Sources

- [sqlite-vec docs](https://alexgarcia.xyz/sqlite-vec/) — API reference, vec0 virtual table, KNN queries
- [sqlite-vec Python guide](https://alexgarcia.xyz/sqlite-vec/python.html) — Python-specific setup and examples
- [sqlite-vec GitHub](https://github.com/asg017/sqlite-vec) — source, issues, examples
- [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md) — `/api/embed` endpoint reference
- [Ollama embedding models](https://ollama.com/blog/embedding-models) — model comparison and usage
- [nomic-embed-text](https://ollama.com/library/nomic-embed-text) — model card, 768D, 8K context
- [ollama Python package](https://github.com/ollama/ollama-python) — `ollama.embed()` usage
