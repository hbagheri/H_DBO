use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use TestDB;

my $db = TestDB::fresh(seed => [
    { email => 'a@x', name => 'Alice', role => 'admin',  score => 10 },
    { email => 'b@x', name => 'Bob',   role => 'user',   score => 5  },
    { email => 'c@x', name => 'Carol', role => 'editor', score => 8  },
    { email => 'd@x', name => 'Dan',   role => 'user',   score => 12 },
]);

# Plain select(*)
my $rows = $db->select->from('users')->all;
is scalar(@$rows), 4, 'select * returns all rows';

# Specific columns as arrayref
$rows = $db->select(['id', 'email'])->from('users')->orderBy('id')->all;
is_deeply [sort keys %{ $rows->[0] }], ['email', 'id'], 'columns restricted';

# WHERE hash equality
$rows = $db->select->from('users')->where({ name => 'Bob' })->all;
is scalar(@$rows), 1, 'where equality matches one';
is $rows->[0]{email}, 'b@x', 'and the right one';

# WHERE hash with IN (arrayref)
$rows = $db->select->from('users')
                   ->where({ role => ['admin', 'editor'] })
                   ->orderBy('id')
                   ->all;
is scalar(@$rows), 2, 'IN clause returns two rows';
is_deeply [map { $_->{name} } @$rows], ['Alice', 'Carol'], 'IN names correct';

# WHERE hash with empty IN (should match nothing, not blow up)
$rows = $db->select->from('users')->where({ role => [] })->all;
is scalar(@$rows), 0, 'empty IN matches nothing';

# WHERE with raw fragment + binds
$rows = $db->select->from('users')
                   ->where('score >= ?', 10)
                   ->orderBy('id')
                   ->all;
is scalar(@$rows), 2, 'raw where + binds';

# Chained WHERE -> AND
$rows = $db->select->from('users')
                   ->where({ role => 'user' })
                   ->where('score > ?', 8)
                   ->all;
is scalar(@$rows), 1, 'chained where ANDs';
is $rows->[0]{name}, 'Dan', 'chained where picks Dan';

# WHERE IS NULL
$db->insertInto('users')->set({ email => 'e@x', name => 'Eve' })->execute;
$rows = $db->select->from('users')->where({ score => undef })->all;
is scalar(@$rows), 1, 'IS NULL where';
is $rows->[0]{name}, 'Eve', 'IS NULL matches Eve';

# ORDER BY + LIMIT + OFFSET
$rows = $db->select(['name'])->from('users')
           ->orderBy('score', 'DESC')
           ->limit(2)
           ->all;
is scalar(@$rows), 2, 'limit honoured';
is $rows->[0]{name}, 'Dan', 'order DESC works';

$rows = $db->select(['name'])->from('users')
           ->orderBy('score', 'DESC')
           ->limit(2, 1)
           ->all;
is $rows->[0]{name}, 'Alice', 'limit+offset works';

# GROUP BY — verify the SQL contains GROUP BY (raw aggregate fragments in
# select-columns are intentionally not supported by the builder).
my $gsql = $db->select('role, COUNT(*) AS n')
              ->from('users')
              ->groupBy('role')
              ->orderBy('role')
              ->query
              ->getQuery;
like $gsql, qr/GROUP BY role/, 'GROUP BY clause emitted';
$rows = $db->select('role, COUNT(*) AS n')
           ->from('users')
           ->groupBy('role')
           ->orderBy('role')
           ->all;
ok scalar(@$rows) > 0, 'group by produces rows';

# one()
my $one = $db->select->from('users')->where({ name => 'Alice' })->one;
is $one->{email}, 'a@x', 'one() returns single row';

# getQuery / getBinds for inspection
my $sql = $db->select(['id'])->from('users')->where({ id => 1 })->query->getQuery;
is $sql, 'SELECT id FROM users WHERE id = ?', 'getQuery produces expected SQL';
my @binds = $db->getBinds;
is_deeply \@binds, [1], 'getBinds returns binds';

done_testing;
