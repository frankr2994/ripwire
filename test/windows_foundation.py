import json, os, subprocess, sys, tempfile
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
binary = str(Path(sys.argv[1]).resolve())
def command(args, cwd, codes=(0,)):
    r = subprocess.run(args, cwd=cwd, capture_output=True, encoding='utf-8', errors='replace', timeout=90)
    assert r.returncode in codes, (args, r.returncode, r.stdout, r.stderr)
    return r

with tempfile.TemporaryDirectory(prefix='ripwire foundation ') as scratch:
    repo = Path(scratch) / 'répo 空間'; repo.mkdir()
    (repo/'src').mkdir(); (repo/'nested').mkdir(); (repo/'ignored').mkdir()
    (repo/'.gitignore').write_text('ignored/\n', encoding='utf-8')
    (repo/'src/demo.ts').write_text('export function shared(value: number) { return value + 1; }\n', encoding='utf-8')
    (repo/'nested/demo.ts').write_text('export function shared(value: number) { return value + 9; }\n', encoding='utf-8')
    (repo/'ignored/demo.ts').write_text('export function ignored() { return 0; }\n', encoding='utf-8')
    (repo/'config.unknown').write_text('unsupported', encoding='utf-8')
    def git(*args): return command(['git', *args], repo).stdout.strip()
    git('init', '-q'); git('config', 'user.name', 'fixture'); git('config', 'user.email', 'fixture@example.invalid')
    git('add', '.'); git('commit', '-qm', 'fixture')
    (repo/'src/demo.ts').write_text('export function shared(value: number) { return value + 2; }\n', encoding='utf-8')
    variants = ['.', repo.as_posix(), str(repo), str(repo) + os.sep]
    for root in variants:
        coverage = json.loads(command([binary, root, '--index-coverage', '--no-cache'], repo).stdout)
        assert 'src/demo.ts' in coverage['indexed'], coverage
        assert any(s['reason'] == 'ignored-directory' for s in coverage['skipped']), coverage
        situ = command([binary, root, '--situ', '--no-cache'], repo)
        assert '1 changed file(s)' in situ.stdout, (root, situ.stdout, situ.stderr)
        expanded = command([binary, root, '--expand=src/demo.ts:shared', '--top-k=0', '--no-cache'], repo)
        assert 'value + 2' in expanded.stdout and 'value + 9' not in expanded.stdout, expanded.stdout
        print('PASS root and qualified selection:', root)
    nested = command([binary, str(repo/'src'), '--situ', '--no-cache'], repo)
    assert '1 changed file(s)' in nested.stdout, (nested.stdout, nested.stderr)
    print('PASS nested crawl root')
    (repo/'src/名前 file.ts').write_text('export function unicodePath() { return 42; }\n', encoding='utf-8')
    coverage = json.loads(command([binary, str(repo), '--index-coverage', '--no-cache'], repo).stdout)
    assert 'src/名前 file.ts' in coverage['indexed'], coverage
    print('PASS Unicode filename inventory')
    git('mv', 'nested/demo.ts', 'nested/renamed.ts')
    (repo/'src/demo.ts').unlink()
    result = command([binary, str(repo), '--situ', '--no-cache'], repo)
    assert 'working tree is clean' not in result.stdout
    assert 'incomplete coverage' in result.stderr, result.stderr
    print('PASS deletion and rename disclose omissions')
    worktree = Path(scratch)/'worktree'
    git('worktree', 'add', '--detach', str(worktree), 'HEAD')
    (worktree/'src/demo.ts').write_text('export function shared(value: number) { return value + 3; }\n', encoding='utf-8')
    result = command([binary, str(worktree), '--situ', '--no-cache'], worktree)
    assert '1 changed file(s)' in result.stdout, result.stdout
    print('PASS worktree')
