import runpy
import sqlite3
import tempfile
from contextlib import closing
from pathlib import Path

module = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts" / "stop-phrase-snippets.py"))
configure, personal = module["configure"], module["PERSONAL"]
with tempfile.TemporaryDirectory() as temp:
    path = Path(temp) / "flow.sqlite"
    with closing(sqlite3.connect(path)) as db, db:
        db.execute("""CREATE TABLE Dictionary (id TEXT PRIMARY KEY, phrase TEXT, teamDictionaryId TEXT,
                   replacement TEXT, replacementHtml TEXT, isDeleted INTEGER DEFAULT 0, isSnippet INTEGER,
                   manualEntry INTEGER, source TEXT, createdAt TEXT, modifiedAt TEXT,
                   UNIQUE(phrase,teamDictionaryId))""")
        db.execute("INSERT INTO Dictionary(id,phrase,teamDictionaryId,replacement) VALUES ('1','and dictation',?,'custom')", (personal,))
    try:
        configure(path)
    except ValueError:
        pass
    else:
        raise AssertionError("Expected a conflicting personal rule to abort the transaction")
    with closing(sqlite3.connect(path)) as db, db:
        assert db.execute("SELECT count(*) FROM Dictionary").fetchone()[0] == 1
        db.execute("UPDATE Dictionary SET isDeleted=1 WHERE id='1'")
        db.execute("INSERT INTO Dictionary (id,phrase,teamDictionaryId,replacement) VALUES ('2','end dictation','team','team text')")
    assert configure(path) == 4
    assert configure(path) == 0
    with closing(sqlite3.connect(path)) as db:
        assert db.execute("SELECT replacement FROM Dictionary WHERE id='2'").fetchone()[0] == "team text"
        assert db.execute("SELECT count(*) FROM Dictionary WHERE isDeleted=0 AND isSnippet=1 AND replacement='' AND teamDictionaryId=?", (personal,)).fetchone()[0] == 4

print("Passed snippet creation, conflict rollback, reactivation and repeat installation.")
