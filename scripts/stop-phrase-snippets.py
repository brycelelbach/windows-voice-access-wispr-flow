"""Add the optional stop-phrase removal snippets to an existing local Wispr Flow database."""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import sqlite3
from uuid import uuid4

PHRASES = ("end dictation", "end dictation.", "and dictation", "and dictation.")
PERSONAL = "00000000-0000-0000-0000-000000000000"


def configure(path):
    # mode=rw prevents a typo from silently creating an empty database.
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=rw", uri=True, timeout=5)
    try:
        with connection:
            connection.execute("BEGIN IMMEDIATE")
            stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f +00:00")
            changed = 0
            for phrase in PHRASES:
                rows = connection.execute(
                    "SELECT id, isDeleted, isSnippet, replacement, replacementHtml FROM Dictionary "
                    "WHERE phrase = ? COLLATE NOCASE AND teamDictionaryId = ?", (phrase, PERSONAL)
                ).fetchall()
                if len(rows) > 1:
                    raise ValueError(f"Resolve duplicate personal entries for {phrase!r} in Flow first.")
                if rows:
                    entry_id, deleted, snippet, expansion, html = rows[0]
                    if not deleted:
                        if snippet and expansion == "" and not html:
                            continue
                        raise ValueError(f"Personal entry {phrase!r} already exists with different settings.")
                    connection.execute(
                        "UPDATE Dictionary SET replacement='', replacementHtml='', isDeleted=0, "
                        "isSnippet=1, manualEntry=1, source='manual', modifiedAt=? WHERE id=?", (stamp, entry_id)
                    )
                else:
                    connection.execute(
                        "INSERT INTO Dictionary (id, phrase, teamDictionaryId, replacement, replacementHtml, "
                        "isSnippet, manualEntry, source, createdAt, modifiedAt) "
                        "VALUES (?, ?, ?, '', '', 1, 1, 'manual', ?, ?)",
                        (str(uuid4()), phrase, PERSONAL, stamp, stamp),
                    )
                changed += 1
            return changed
    finally:
        connection.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, help="Override the current user's flow.sqlite path")
    args = parser.parse_args()
    path = args.database or Path(os.environ["APPDATA"]) / "Wispr Flow" / "flow.sqlite"
    try:
        print(f"Updated {configure(path)} personal stop-phrase snippets.")
    except (OSError, ValueError, sqlite3.Error) as error:
        parser.exit(1, f"Snippets could not be configured: {error}\n")
