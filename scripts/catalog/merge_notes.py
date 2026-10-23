"""
Merge a batch of reviewed notes into catalog.json:  python scripts/catalog/merge_notes.py NOTES.json [FILES.txt]
NOTES.json = {"<repo path>": {notes...}}. Validates every path is in the catalog, reports files from
FILES.txt (the batch's expected list) that the batch did not cover, and REPLACES each covered entry's
notes. Does NOT mark entries reviewed — spot-check, then run `catalog.py review` on the batch.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from catalog import load, save  # noqa: E402

ALLOWED = {'purpose', 'params', 'access', 'usedIn', 'errors', 'reads', 'writes', 'origins', 'script',
           'caveats', 'functions'}


def main(notes_path, files_path=None):
    with open(notes_path, encoding='utf-8') as f:
        batch = json.load(f)
    cat = load()
    unknown, bad_keys, merged = [], [], 0
    for p, notes in batch.items():
        p = p.replace('\\', '/')
        if p not in cat['files']:
            unknown.append(p)
            continue
        extra = set(notes) - ALLOWED
        if extra:
            bad_keys.append((p, sorted(extra)))
        if not notes.get('purpose'):
            bad_keys.append((p, ['<missing purpose>']))
        cat['files'][p]['notes'] = notes
        merged += 1
    save(cat)
    print(f'merged {merged} entries from {os.path.basename(notes_path)}')
    if unknown:
        print(f'NOT IN CATALOG ({len(unknown)}): ' + ', '.join(unknown))
    if bad_keys:
        print('SCHEMA ISSUES: ' + '; '.join(f'{p}: {k}' for p, k in bad_keys))
    if files_path:
        expected = [l.strip() for l in open(files_path, encoding='utf-8') if l.strip()]
        missing = [p for p in expected if p not in batch]
        if missing:
            print(f'MISSING FROM BATCH ({len(missing)}): ' + ', '.join(missing))


if __name__ == '__main__':
    main(*sys.argv[1:3])
