#!/usr/bin/env python3
"""
Repo card catalog — see docs/catalog/README.md and .claude/skills/catalog-maintenance.md.

One source of truth: docs/catalog/catalog.json. Each in-scope file has an entry with two halves:
  "auto"  — MECHANICAL facts re-extracted from the file every run (tables read/written, columns,
            params, THROWs, GRANTs, EXEC calls, app imports/routes/gates). Never hand-edited.
  "notes" — MEANING filled in by reading the file (purpose, verified field-level reads/writes,
            access rule, error conditions, where/how it is used, data origins, script kind).
            Hand-maintained; rendering prefers notes over auto where both exist.
  "reviewedBlob" — git blob hash of the file when its notes were last reviewed. check flags any
            file whose current content differs (notes may be stale), plus new + deleted files.

Subcommands:
  extract           refresh every entry's "auto" half (+ add skeletons for new files, drop deleted)
  check             exit 1 if any in-scope file is new / changed-since-review / deleted, or if a
                    note's tables disagree with what the extractor sees
  review PATH...    mark entries reviewed (reviewedBlob := current blob) after updating their notes
  build             render docs/catalog/{by-file,by-table,by-error,by-route,scripts}.md
Run from anywhere inside the repo. Python 3.8+, standard library only.
"""
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from datetime import date

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True,
                      check=True).stdout.strip()
CATALOG_DIR = os.path.join(ROOT, 'docs', 'catalog')
CATALOG = os.path.join(CATALOG_DIR, 'catalog.json')

# ---------------------------------------------------------------------------------------------
# Scope
# ---------------------------------------------------------------------------------------------
SQL_EXCLUDE = ('sql/deploy/',)          # bundles are COPIES of source files


def in_scope_files():
    out = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard'],
                         capture_output=True, text=True, cwd=ROOT, check=True).stdout.splitlines()
    files = []
    for p in out:
        if p.startswith('sql/') and p.endswith('.sql') and not p.startswith(SQL_EXCLUDE):
            files.append(p)
        elif p.startswith('webapp/src/') and (p.endswith('.ts') or p.endswith('.tsx')):
            files.append(p)
    return sorted(set(files))


_BLOBS = {}


def prime_blobs(paths):
    """Hash every file in ONE git call (per-file calls made a full run ~45s)."""
    out = subprocess.run(['git', 'hash-object', '--stdin-paths'], input='\n'.join(paths) + '\n',
                         capture_output=True, text=True, cwd=ROOT, check=True).stdout.split()
    _BLOBS.update(zip(paths, out))


def blob_of(path):
    if path not in _BLOBS:
        prime_blobs([path])
    return _BLOBS[path]


def read(path):
    with open(os.path.join(ROOT, path), encoding='utf-8', errors='replace') as f:
        return f.read()


def kind_of(path):
    if path.startswith('sql/'):
        d = path.split('/')[1]
        return {'dimensions': 'table', 'facts': 'table', 'staging': 'staging-table',
                'procedures': 'procedure', 'scripts': 'script'}.get(d, 'sql')
    name = os.path.basename(path)
    if name == 'page.tsx':
        return 'page'
    if name == 'route.ts':
        return 'api-route'
    if name == 'actions.ts':
        return 'action'
    if path == 'webapp/src/lib/data.ts':
        return 'data-module'
    if '/lib/' in path:
        return 'lib'
    if '/components/' in path:
        return 'component'
    return 'app-file'


# ---------------------------------------------------------------------------------------------
# SQL extraction
# ---------------------------------------------------------------------------------------------
IDENT = r'(?:\[?(\w+)\]?\.)?\[?([A-Za-z_]\w*)\]?'
SQL_KEYWORDS = set('''select from where join inner left right full outer cross apply on and or not
group order by having union all as with set values into update delete insert merge when then else
end case is null in exists between like top distinct over partition row_number cast convert
begin return returns table go declare if while print exec execute output using matched'''.split())


def strip_sql_comments(text):
    """Remove /* */ and -- comments, preserving newlines (so line numbers survive)."""
    out, i, n = [], 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "'":
                if i + 1 < n and text[i + 1] == "'":
                    out.append("'"); i += 2; continue
                in_str = False
            i += 1
        elif c == "'":
            in_str = True; out.append(c); i += 1
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r'[^\n]', ' ', text[i:j])); i = j
        elif text.startswith('--', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        else:
            out.append(c); i += 1
    return ''.join(out)


def blank_strings(text):
    return re.sub(r"N?'(?:[^']|'')*'", lambda m: "'" + ' ' * (len(m.group(0)) - 2) + "'", text)


def line_at(text, idx):
    return text.count('\n', 0, idx) + 1


def header_field(text, field):
    """Pull a multi-line ' * Field: ...' value out of the standard file header."""
    m = re.search(r'\*\s*' + field + r':\s*(.+?)(?=\n\s*\*\s*(?:[A-Z][A-Za-z ]+:|\n|/)|\n\s*\*\s*\n|\*/)',
                  text, re.S)
    if not m:
        return None
    v = re.sub(r'\s*\n\s*\*\s*', ' ', m.group(1)).strip()
    v = re.sub(r'\s+', ' ', v)
    return v[:600]


def sql_definitions(code):
    """Objects this file CREATEs (tables, functions, procedures, views)."""
    defs = []
    for m in re.finditer(r'\bCREATE\s+(?:OR\s+ALTER\s+)?(TABLE|FUNCTION|PROCEDURE|PROC|VIEW)\s+' + IDENT,
                         code, re.I):
        typ = m.group(1).upper()
        typ = 'PROCEDURE' if typ == 'PROC' else typ
        defs.append({'type': typ.lower(), 'name': m.group(3), 'pos': m.start()})
    return defs


def table_columns(code, start):
    """Columns of the CREATE TABLE starting at code[start:]."""
    open_i = code.find('(', start)
    depth, i = 0, open_i
    while i < len(code):
        if code[i] == '(':
            depth += 1
        elif code[i] == ')':
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = code[open_i + 1:i]
    cols, depth, cur = [], 0, ''
    for ch in body:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            cols.append(cur); cur = ''
        else:
            cur += ch
    cols.append(cur)
    out = []
    for c in cols:
        c = ' '.join(c.split())
        m = re.match(r'\[?(\w+)\]?\s+([A-Za-z0-9]+(?:\s*\([^)]*\))?)(.*)', c)
        if not m or m.group(1).upper() in ('CONSTRAINT', 'PRIMARY', 'INDEX', 'UNIQUE', 'FOREIGN'):
            continue
        rest = m.group(3).upper()
        out.append({'name': m.group(1), 'type': m.group(2).replace(' ', ''),
                    'nullable': 'NOT NULL' not in rest,
                    **({'identity': True} if 'IDENTITY' in rest else {})})
    return out


def routine_params(code, start, typ):
    if typ == 'function':
        # balanced-paren scan: VARCHAR(255) inside the list must not end it
        i = code.find('(', start)
        depth, j = 0, i
        while 0 <= j < len(code):
            if code[j] == '(':
                depth += 1
            elif code[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        seg = code[i + 1:j] if i >= 0 else ''
    else:
        m = re.compile(r'\bAS\b', re.I).search(code, start)
        seg = code[start:m.start()] if m else ''
    return [{'name': p.group(1), 'type': p.group(2).replace(' ', '')}
            for p in re.finditer(r'@(\w+)\s+([A-Za-z0-9]+(?:\s*\([^)]*\))?)', seg)]


def exec_string_bodies(code):
    """SQL inside EXEC('...') / EXEC(N'...') — the idempotent-deploy pattern hides CREATE TABLE,
    UPDATE etc. in a string. Return it unescaped + comment-stripped + string-blanked so it can be
    parsed like ordinary code (appended after the file's own code)."""
    parts = []
    for m in re.finditer(r"\bEXEC(?:UTE)?\s*\(\s*N?'((?:[^']|'')*)'\s*\)", code, re.I):
        body = m.group(1).replace("''", "'")
        parts.append(blank_strings(strip_sql_comments(body)))
    return '\n'.join(parts)


def extract_sql(path, text):
    code = strip_sql_comments(text)
    nostr = blank_strings(code)
    hidden = exec_string_bodies(code)
    if hidden:
        nostr = nostr + '\n' + hidden
    auto = {}

    defs = sql_definitions(nostr)
    auto['defines'] = [{'type': d['type'], 'name': d['name']} for d in defs]
    for d in defs:
        if d['type'] == 'table':
            d['columns'] = table_columns(nostr, d['pos'])
        elif d['type'] in ('function', 'procedure'):
            d['params'] = routine_params(nostr, d['pos'], d['type'])
    tables_def = [d for d in defs if d['type'] == 'table']
    if tables_def:
        auto['columns'] = {d['name']: d['columns'] for d in tables_def}
    routines = [d for d in defs if d['type'] in ('function', 'procedure')]
    if routines:
        auto['params'] = {d['name']: d['params'] for d in routines}

    # CTE names (never real objects)
    ctes = set(m.group(1).lower() for m in re.finditer(r'\bWITH\s+(\w+)\s+AS\s*\(', nostr, re.I))
    ctes |= set(m.group(1).lower() for m in re.finditer(r',\s*(\w+)\s+AS\s*\(', nostr, re.I))

    # references: FROM / JOIN (reads), and TVF calls
    alias_map, reads, calls_fn = {}, set(), set()
    for m in re.finditer(r'\b(FROM|JOIN|APPLY)\s+' + IDENT + r'(\s*\()?(?:\s+(?:AS\s+)?(\w+))?', nostr, re.I):
        schema, name, paren, alias = m.group(2), m.group(3), m.group(4), m.group(5)
        if name.lower() in SQL_KEYWORDS or name.lower() in ctes:
            continue
        full = f'{schema}.{name}' if schema and schema.lower() != 'dbo' else name
        if paren:
            calls_fn.add(full)
        else:
            reads.add(full)
        if alias and alias.lower() not in SQL_KEYWORDS:
            alias_map[alias.lower()] = full
        alias_map[name.lower()] = full

    writes = defaultdict(lambda: {'ops': set(), 'columns': set()})
    for m in re.finditer(r'\bINSERT\s+(?:INTO\s+)?' + IDENT + r'\s*(\(([^)]*)\))?', nostr, re.I):
        name = m.group(2)
        if name.lower() in SQL_KEYWORDS:
            continue
        w = writes[name]; w['ops'].add('insert')
        if m.group(4) and not re.search(r'\bSELECT\b', m.group(4), re.I):
            w['columns'] |= set(c.strip(' []\n\t') for c in m.group(4).split(',') if c.strip())
    for m in re.finditer(r'\bUPDATE\s+' + IDENT + r'\s+SET\b(.*?)(?=\bFROM\b|\bWHERE\b|;|\bGO\b|$)', nostr, re.I | re.S):
        name = alias_map.get(m.group(2).lower(), m.group(2))
        w = writes[name]; w['ops'].add('update')
        w['columns'] |= set(c.group(2) for c in re.finditer(r'(?:\w+\.)?\[?(?:(\w+)\.)?(\w+)\]?\s*=', m.group(3)))
    for m in re.finditer(r'\bDELETE\s+(?:FROM\s+)?' + IDENT, nostr, re.I):
        name = alias_map.get(m.group(2).lower(), m.group(2))
        if name.lower() not in SQL_KEYWORDS:
            writes[name]['ops'].add('delete')
    for m in re.finditer(r'\bTRUNCATE\s+TABLE\s+' + IDENT, nostr, re.I):
        writes[m.group(2)]['ops'].add('truncate')
    for m in re.finditer(r'\bMERGE\s+(?:INTO\s+)?' + IDENT, nostr, re.I):
        writes[m.group(2)]['ops'].add('merge')
    for m in re.finditer(r'\bALTER\s+TABLE\s+' + IDENT, nostr, re.I):
        writes[m.group(2)]['ops'].add('alter')
    for m in re.finditer(r'\bDROP\s+(TABLE|FUNCTION|PROCEDURE|PROC|VIEW)\s+(?:IF\s+EXISTS\s+)?' + IDENT, nostr, re.I):
        writes[m.group(3)]['ops'].add('drop')
    for m in re.finditer(r'\bCOPY\s+INTO\s+' + IDENT, nostr, re.I):
        writes[m.group(2)]['ops'].add('copy-into')

    # field-level reads via alias.Column
    fields = defaultdict(set)
    for m in re.finditer(r'\b(\w+)\.\[?(\w+)\]?', nostr):
        a, col = m.group(1).lower(), m.group(2)
        if a in alias_map and a not in ('dbo', 'sys') and not col.isdigit():
            fields[alias_map[a]].add(col)

    auto['reads'] = {t: sorted(fields.get(t, [])) for t in sorted(reads)}
    if calls_fn:
        auto['callsFunctions'] = sorted(calls_fn)
    if writes:
        auto['writes'] = {t: {'ops': sorted(v['ops']), 'columns': sorted(v['columns'])}
                          for t, v in sorted(writes.items())}

    execs = sorted(set(m.group(2) for m in re.finditer(r'\bEXEC(?:UTE)?\s+' + IDENT, nostr, re.I)
                       if m.group(2).lower() not in ('sp_executesql',)))
    if re.search(r'\bsp_executesql\b', nostr, re.I):
        auto['dynamicSql'] = True
    if execs:
        auto['execs'] = execs

    throws = []
    for m in re.finditer(r'\bTHROW\s+(\d+)\s*,\s*(N?\'(?:[^\']|\'\')*\'|@\w+|CONCAT\s*\(.*?\))\s*,\s*\d+',
                         code, re.I | re.S):
        msg = m.group(2)
        if msg.startswith(("'", "N'")):
            msg = msg[msg.index("'") + 1:-1].replace("''", "'")
        throws.append({'code': int(m.group(1)), 'message': ' '.join(msg.split())[:300],
                       'line': line_at(code, m.start())})
    for m in re.finditer(r'\bRAISERROR\s*\(\s*(N?\'(?:[^\']|\'\')*\')', code, re.I):
        throws.append({'code': None, 'message': m.group(1).strip("N'")[:300], 'line': line_at(code, m.start())})
    if throws:
        auto['errors'] = throws

    grants = [{'perm': ' '.join(m.group(1).split()), 'object': m.group(3), 'to': m.group(4)}
              for m in re.finditer(r'\bGRANT\s+([\w, ]+?)\s+ON\s+(?:OBJECT::)?' + IDENT + r'\s+TO\s+\[?([\w.@-]+)\]?',
                                   nostr, re.I)]
    if grants:
        auto['grants'] = grants

    # @UPN / @CallerUPN = caller-scoped; AccessLevel predicates = role gates
    roles = sorted(set(re.findall(r"'(Administrator|SpecialistTeacher|RegionalAnalyst|Teacher|ProvincialAnalyst|SupportStaff)'", code)))
    scoped = [p for p in ('@UPN', '@CallerUPN') if re.search(re.escape(p) + r'\b', code)]
    if roles or scoped:
        auto['accessSignals'] = {'callerParams': scoped, 'rolesReferenced': roles,
                                 'usesStaffSchoolAccess': bool(re.search(r'\bStaffSchoolAccess\b', nostr)),
                                 'usesFactSectionTeachers': bool(re.search(r'\bFactSectionTeachers\b', nostr)),
                                 'usesStaffAppAccess': bool(re.search(r'\bStaffAppAccess\b', nostr))}

    if path.startswith('sql/scripts/'):
        decl = [{'name': m.group(1), 'type': m.group(2).replace(' ', ''),
                 **({'default': ' '.join(m.group(3).split())[:120]} if m.group(3) else {})}
                for m in re.finditer(r'\bDECLARE\s+@(\w+)\s+([A-Za-z0-9]+(?:\s*\([^)]*\))?)\s*(?:=\s*([^;\n]+))?',
                                     code, re.I)]
        if decl:
            auto['declares'] = decl
        writes_data = any(set(v['ops']) & {'insert', 'update', 'delete', 'truncate', 'merge', 'copy-into'}
                          for v in auto.get('writes', {}).values())
        ddl = bool(defs) or any(set(v['ops']) & {'alter', 'drop'} for v in auto.get('writes', {}).values())
        auto['scriptEffect'] = 'writes-data' if writes_data else ('ddl' if ddl else 'read-only')
        auto['lastCommit'] = subprocess.run(['git', 'log', '-1', '--format=%as %h %s', '--', path],
                                            capture_output=True, text=True, cwd=ROOT).stdout.strip()[:160]

    for f in ('Purpose', 'Script', 'Table', 'Function', 'Procedure'):
        v = header_field(text, f)
        if v:
            auto['header' + f] = v
    return auto


# ---------------------------------------------------------------------------------------------
# TypeScript extraction
# ---------------------------------------------------------------------------------------------
def ts_route(path):
    """URL of a page / route / actions file (its directory under app/)."""
    rel = path[len('webapp/src/app'):] if path.startswith('webapp/src/app') else None
    if rel is None:
        return None
    parts = [p for p in os.path.dirname(rel).split('/') if p and not (p.startswith('(') and p.endswith(')'))]
    return '/' + '/'.join(parts)


def resolve_import(src_path, spec):
    base = os.path.join(ROOT, 'webapp', 'src') if spec.startswith('@/') else \
        os.path.dirname(os.path.join(ROOT, src_path))
    target = os.path.normpath(os.path.join(base, spec[2:] if spec.startswith('@/') else spec))
    for cand in (target + '.ts', target + '.tsx', os.path.join(target, 'index.ts'),
                 os.path.join(target, 'index.tsx'), target):
        if os.path.isfile(cand):
            return os.path.relpath(cand, ROOT).replace('\\', '/')
    return None


GATE_PATTERNS = [
    (r'\bisSysAdmin\b', 'capability:isSysAdmin'), (r'\bcanManageCycles\b', 'capability:canManageCycles'),
    (r'\bcanRunIngest\b', 'capability:canRunIngest'), (r'\bcanOverrideMath\b', 'capability:canOverrideMath'),
    (r'fresh:\s*true', 'fresh-recheck'), (r'\bgetCallerAccessLevel\b', 'role:AccessLevel'),
    (r'\bgetCurrentUpn\s*\(', 'signed-in (UPN)'), (r'\bredirect\(', 'redirect'), (r'\bnotFound\(', 'notFound'),
    (r'\bauthMode\(', 'auth-mode'), (r'\bOVERSIGHT\b', 'role:oversight-set'),
]


def extract_ts(path, text, data_fns):
    auto = {}
    imports = []
    for m in re.finditer(r'''import\s+(?:type\s+)?([^;]*?)\s+from\s+['"]([^'"]+)['"]''', text):
        spec = m.group(2)
        if spec.startswith(('.', '@/')):
            r = resolve_import(path, spec)
            if r:
                imports.append(r)
    if imports:
        auto['imports'] = sorted(set(imports))
    used = set()
    for m in re.finditer(r'''import\s+\{([^}]*)\}\s+from\s+['"]@/lib/data['"]''', text):
        for part in m.group(1).split(','):
            part = part.strip()
            if not part or part.startswith('type '):
                continue
            name = part.split(' as ')[0].strip()
            if name in data_fns:
                used.add(name)
    if used:
        auto['dataFunctions'] = sorted(used)
    procs = sorted(set(re.findall(r"execProc\(\s*['\"](usp_\w+)['\"]", text)))
    if procs:
        auto['execProcs'] = procs
    dbo = sorted(set(re.findall(r'\bdbo\.(\w+)', text)))
    if dbo and path != 'webapp/src/lib/data.ts':
        auto['sqlObjects'] = dbo
    gates = []
    for pat, label in GATE_PATTERNS:
        for m in re.finditer(pat, text):
            ln = line_at(text, m.start())
            src = text.splitlines()[ln - 1].strip()[:160]
            gates.append({'gate': label, 'line': ln, 'code': src})
    if gates:
        auto['gates'] = gates
    errs = []
    for pat, kind in ((r'new\s+UserError\(\s*([\'"`])((?:\\.|(?!\1).)*)\1', 'UserError'),
                      (r'throw\s+new\s+Error\(\s*([\'"`])((?:\\.|(?!\1).)*)\1', 'Error'),
                      (r'\bmessage:\s*([\'"`])((?:\\.|(?!\1).)*)\1', 'message')):
        for m in re.finditer(pat, text):
            errs.append({'kind': kind, 'message': m.group(2)[:300], 'line': line_at(text, m.start())})
    if errs:
        auto['errors'] = errs
    if os.path.basename(path) in ('page.tsx', 'route.ts', 'actions.ts', 'layout.tsx'):
        auto['route'] = ts_route(path)
    if text.lstrip().startswith(("'use client'", '"use client"')):
        auto['client'] = True
    if text.lstrip().startswith(("'use server'", '"use server"')):
        auto['serverActions'] = sorted(set(re.findall(r'export\s+async\s+function\s+(\w+)', text)))
    return auto


def extract_data_module(text):
    """lib/data.ts: per exported function, the SQL objects / tables it touches."""
    fns = {}
    starts = [(m.start(), m.group(1)) for m in re.finditer(r'export\s+async\s+function\s+(\w+)', text)]
    for i, (pos, name) in enumerate(starts):
        body = text[pos:starts[i + 1][0] if i + 1 < len(starts) else len(text)]
        objs = set(re.findall(r'\bdbo\.(\w+)', body))
        objs |= set(m.group(1) for m in re.finditer(r'\b(?:FROM|JOIN)\s+(?:dbo\.)?([A-Z]\w+)', body))
        procs = set(re.findall(r"execProc\(\s*['\"](usp_\w+)['\"]", body))
        fns[name] = {'line': line_at(text, pos), 'objects': sorted(objs), **({'procs': sorted(procs)} if procs else {})}
    return fns


# ---------------------------------------------------------------------------------------------
# Catalog I/O
# ---------------------------------------------------------------------------------------------
def load():
    if os.path.isfile(CATALOG):
        with open(CATALOG, encoding='utf-8') as f:
            return json.load(f)
    return {'schemaVersion': 1, 'files': {}}


def save(cat):
    os.makedirs(CATALOG_DIR, exist_ok=True)
    with open(CATALOG, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(cat, f, indent=1, ensure_ascii=False, sort_keys=False)
        f.write('\n')


EMPTY_NOTES = {'purpose': ''}


def refine_kind(kind, auto):
    """sql/security holds tables, functions AND legacy views — label by what the file defines."""
    if kind != 'sql':
        return 'app-component' if kind == 'app-file' else kind
    types = [d['type'] for d in auto.get('defines', [])]
    if 'table' in types:
        return 'security-table'
    if 'view' in types:
        return 'legacy-view'
    if 'function' in types:
        return 'function'
    if 'procedure' in types:
        return 'procedure'
    if auto.get('grants'):
        return 'grants'
    return 'sql'


def cmd_extract():
    cat = load()
    files = in_scope_files()
    prime_blobs(files)
    data_text = read('webapp/src/lib/data.ts') if 'webapp/src/lib/data.ts' in files else ''
    data_fns = extract_data_module(data_text)
    new, dropped = [], []
    entries = cat['files']
    for p in list(entries):
        if p not in files:
            dropped.append(p)
            del entries[p]
    for p in files:
        text = read(p)
        auto = extract_sql(p, text) if p.endswith('.sql') else extract_ts(p, text, data_fns)
        if p == 'webapp/src/lib/data.ts':
            auto['functions'] = data_fns
        e = entries.get(p)
        if e is None:
            new.append(p)
            e = {'kind': kind_of(p), 'reviewedBlob': None, 'notes': dict(EMPTY_NOTES)}
        e['kind'] = refine_kind(kind_of(p), auto)
        e['blob'] = blob_of(p)
        e['auto'] = auto
        entries[p] = e
    cat['files'] = dict(sorted(entries.items()))
    cat['extractedAt'] = date.today().isoformat()
    cat['extractedFrom'] = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], capture_output=True,
                                          text=True, cwd=ROOT).stdout.strip()
    save(cat)
    print(f'extract: {len(files)} in-scope files; {len(new)} new; {len(dropped)} removed')
    for p in dropped:
        print(f'  removed (file gone): {p}')


def note_tables(notes):
    t = set()
    for k in ('reads', 'writes'):
        v = notes.get(k)
        if isinstance(v, dict):
            t |= set(v)
    return t


def auto_tables(auto):
    return set(auto.get('reads', {})) | set(auto.get('writes', {})) | set(auto.get('callsFunctions', []))


def cmd_check():
    cat = load()
    entries = cat.get('files', {})
    files = in_scope_files()
    prime_blobs(files)
    new = [p for p in files if p not in entries]
    gone = [p for p in entries if p not in files]
    changed, unreviewed, mismatch = [], [], []
    for p in files:
        e = entries.get(p)
        if not e:
            continue
        b = blob_of(p)
        if e.get('reviewedBlob') is None:
            unreviewed.append(p)
        elif e['reviewedBlob'] != b:
            changed.append(p)
        nt = note_tables(e.get('notes', {}))
        if nt:
            extra = nt - auto_tables(e.get('auto', {})) - {d['name'] for d in e.get('auto', {}).get('defines', [])}
            if extra:
                mismatch.append((p, sorted(extra)))
    stale_auto = [p for p in files if p in entries and entries[p].get('blob') != blob_of(p)]

    def section(title, items, fmt=lambda x: x):
        if items:
            print(f'{title} ({len(items)}):')
            for x in items:
                print('  ' + fmt(x))
    section('NEW — no catalog entry (run extract, then write notes)', new)
    section('DELETED — entry for a file that no longer exists (run extract)', gone)
    section('AUTO STALE — file changed since last extract (run extract)', stale_auto)
    section('CHANGED SINCE REVIEW — re-check notes, then `review`', sorted(set(changed)))
    section('NOTE/EXTRACT MISMATCH — notes name tables the extractor does not see',
            mismatch, lambda x: f'{x[0]}: {", ".join(x[1])}')
    print(f'unreviewed (skeleton only): {len(unreviewed)} of {len(files)}')
    failing = new or gone or stale_auto or changed or mismatch
    print('CHECK: ' + ('FAIL' if failing else 'OK'))
    return 1 if failing else 0


def cmd_review(paths):
    cat = load()
    for p in paths:
        p = p.replace('\\', '/')
        if p not in cat['files']:
            print(f'not in catalog: {p}'); continue
        b = blob_of(p)
        cat['files'][p]['reviewedBlob'] = b
        cat['files'][p]['blob'] = b
        cat['files'][p]['reviewedOn'] = date.today().isoformat()
    save(cat)
    print(f'review: marked {len(paths)} entr{"y" if len(paths) == 1 else "ies"}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    cmd = sys.argv[1]
    if cmd == 'extract':
        cmd_extract()
    elif cmd == 'check':
        sys.exit(cmd_check())
    elif cmd == 'review':
        cmd_review(sys.argv[2:])
    elif cmd == 'build':
        sys.path.insert(0, os.path.dirname(__file__))
        from render import build
        build(load(), CATALOG_DIR)
    else:
        print(__doc__); sys.exit(2)
