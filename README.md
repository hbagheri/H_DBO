# H_DBO

[![tests](https://github.com/hbagheri/H_DBO/actions/workflows/test.yml/badge.svg)](https://github.com/hbagheri/H_DBO/actions/workflows/test.yml)

A tiny chainable SQL query builder on top of [DBI](https://metacpan.org/pod/DBI),
designed for **PostgreSQL** but happy on any DBI driver. Single-file module,
no Moose, no heavy deps.

```perl
my $db = H_DBO->new({
    db_engine => 'Pg',
    db_name   => 'app',
    db_user   => 'app',
    db_pass   => 'secret',
    host      => 'db.example.com',
});

my $rows = $db->select(['id', 'email'])
              ->from('users')
              ->where({ status => 'active', role => ['admin', 'editor'] })
              ->orderBy('id', 'DESC')
              ->limit(10)
              ->all;
```

## Why use it?

* Chainable builder for `SELECT / INSERT / UPDATE / DELETE / UPSERT` —
  reads close to SQL but stays in Perl.
* Every user-supplied value goes through DBI placeholders, so it's
  injection-safe. Identifiers (`table`, `WHERE col`, `ORDER BY`,
  `GROUP BY`) are validated against an identifier regex.
* Postgres-style `INSERT ... ON CONFLICT` upsert with one call.
* `H_DBO->raw('NOW()')` escape hatch when you actually want a SQL
  fragment instead of a bound value.
* `txn { ... }` transactional wrapper.
* Pure DBI under the hood — you can always reach through with
  `$db->dbh` for things the builder doesn't cover.

## Install

```bash
cpanm DBI DBD::Pg     # or DBD::SQLite / DBD::mysql, whatever you use
cpanm .               # from a checkout of this repo
```

Or manual:

```bash
perl Makefile.PL
make
make test
make install
```

## Quick reference

### Connect

```perl
H_DBO->new({
    db_name   => 'app',           # required (unless dbh => $dbh is supplied)
    db_user   => 'app',
    db_pass   => 'secret',
    db_engine => 'Pg',            # default 'Pg'
    host      => 'db.example.com',
    port      => 5432,
    dsn_extra => 'sslmode=require',
    dbi_attrs => { AutoCommit => 0 },
});

# Reuse an existing handle:
H_DBO->new({ dbh => $existing_dbh });
```

### SELECT

```perl
$db->select                          # equivalent to select('*')
   ->from('users')
   ->where({ id => 1 })
   ->one;                            # hashref of the first row

$db->select(['id', 'email'])
   ->from('users')
   ->where({ role => ['admin', 'editor'] })   # IN ('admin', 'editor')
   ->where('created_at > ?', '2026-01-01')    # ANDed with the previous
   ->orderBy('id', 'DESC')
   ->limit(20, 40)                            # LIMIT 20 OFFSET 40
   ->all;                                      # arrayref of hashrefs
```

`where()` value types:

| Value                      | Generated SQL       |
| -------------------------- | ------------------- |
| scalar (`'a'`)             | `col = ?`           |
| arrayref (`['a','b']`)     | `col IN (?,?)`      |
| empty arrayref (`[]`)      | `1=0` (matches none)|
| `undef`                    | `col IS NULL`       |
| `H_DBO->raw('NOW()')`      | `col = NOW()`       |

For anything more exotic, pass a raw string:

```perl
$db->where("(score > ? OR role = ?)", 100, 'admin');
```

### INSERT / UPDATE / DELETE

```perl
$db->insertInto('users')
   ->set({ email => 'a@b.c', created_at => H_DBO->raw('NOW()') })
   ->execute;

$db->bulkInsertInto('users')
   ->set([ { email => 'a@b.c' }, { email => 'd@e.f' } ])
   ->execute;

$db->update('users')
   ->set({ name => 'Bob', last_seen => H_DBO->raw('NOW()') })
   ->where({ id => 7 })
   ->execute;

$db->deleteFrom('users')->where({ id => 7 })->execute;
```

### UPSERT (Postgres `ON CONFLICT`)

```perl
$db->upsert('users', conflict_target => ['email'])
   ->set({ email => 'a@b.c', name => 'Alice' })
   ->execute;
```

Also works on SQLite 3.24+ — handy for tests.

### Transactions

```perl
$db->txn(sub {
    my ($d) = @_;
    $d->update('accounts')->set({ balance => H_DBO->raw('balance - ?', 10) })->where({ id => 1 })->execute;
    $d->update('accounts')->set({ balance => H_DBO->raw('balance + ?', 10) })->where({ id => 2 })->execute;
});
```

Rolls back on `die`, then re-throws.

### Inspect without running

```perl
my $sql   = $db->select->from('users')->where({ id => 1 })->query->getQuery;
my @binds = $db->getBinds;
```

### Raw SQL when the builder can't help

```perl
$db->setQuery('SELECT * FROM users WHERE custom_op(?) > ?', 'x', 10)->all;
```

## Compatibility

* Perl 5.14+
* PostgreSQL 9.5+ (for upsert) or any DBI driver (for the rest)
* SQLite 3.24+ for upsert; older SQLite still works for everything else.

## Migrating from 1.x

This is a clean break. The 1.x release didn't actually run on any modern Perl
(it pulled in `Switch`, removed from core years ago), so the breakage is
theoretical. The high-level differences:

* Constructor takes a hashref of named params (was 18 positional args).
* Module file moved from `H_DBO.pm` to `lib/H_DBO.pm`.
* `REPLACE INTO` replaced by `upsert()`.
* Several broken or unused methods (`getKey`, `set4update`, etc.) removed.

See `Changes` for the full list.

## License

MIT — see `LICENSE`.
