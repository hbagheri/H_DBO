use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use TestDB;

my $db = TestDB::fresh();

# Single insert
$db->insertInto('users')->set({ email => 'a@x', name => 'Alice' })->execute;
is $db->rows, 1, 'insert affected 1 row';

# Insert with NULL value (undef in set)
$db->insertInto('users')->set({ email => 'b@x', name => undef })->execute;
my $row = $db->select->from('users')->where({ email => 'b@x' })->one;
is $row->{name}, undef, 'undef stored as NULL';

# Bulk insert
$db->bulkInsertInto('users')->set([
    { email => 'c@x', name => 'Carol' },
    { email => 'd@x', name => 'Dan'   },
    { email => 'e@x', name => 'Eve'   },
])->execute;
my $rows = $db->select->from('users')->all;
is scalar(@$rows), 5, 'bulk insert added three rows';

# Update with WHERE
$db->update('users')->set({ name => 'Alicia' })->where({ email => 'a@x' })->execute;
$row = $db->select->from('users')->where({ email => 'a@x' })->one;
is $row->{name}, 'Alicia', 'update wrote new value';

# Update with raw fragment
$db->update('users')->set({ name => H_DBO->raw("UPPER(name)") })->where({ email => 'c@x' })->execute;
$row = $db->select->from('users')->where({ email => 'c@x' })->one;
is $row->{name}, 'CAROL', 'raw fragment in set executed in SQL';

# Update with raw fragment carrying its own bind
$db->update('users')->set({ name => H_DBO->raw("name || ?", '!') })->where({ email => 'd@x' })->execute;
$row = $db->select->from('users')->where({ email => 'd@x' })->one;
is $row->{name}, 'Dan!', 'raw fragment + bind executed';

# Delete with WHERE
$db->deleteFrom('users')->where({ email => 'e@x' })->execute;
$rows = $db->select->from('users')->all;
is scalar(@$rows), 4, 'delete removed one row';

# Delete with chained WHERE
$db->insertInto('users')->set({ email => 'f@x', name => 'Frank', role => 'guest' })->execute;
$db->deleteFrom('users')->where({ role => 'guest' })->where({ email => 'f@x' })->execute;
$rows = $db->select->from('users')->all;
is scalar(@$rows), 4, 'chained where in delete';

done_testing;
