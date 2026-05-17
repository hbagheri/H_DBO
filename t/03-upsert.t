use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use DBD::SQLite;

# Upsert (ON CONFLICT) requires SQLite >= 3.24.
plan skip_all => "SQLite < 3.24 has no ON CONFLICT (found $DBD::SQLite::sqlite_version)"
    if $DBD::SQLite::sqlite_version =~ /^(\d+)\.(\d+)/ && ($1 < 3 || ($1 == 3 && $2 < 24));

use TestDB;

my $db = TestDB::fresh();

# Initial insert via upsert
$db->upsert('users', conflict_target => ['email'])
   ->set({ email => 'a@x', name => 'Alice', score => 1 })
   ->execute;
my $row = $db->select->from('users')->where({ email => 'a@x' })->one;
is $row->{name},  'Alice', 'upsert inserted';
is $row->{score}, 1,       'upsert score 1';

# Upsert again -> updates
$db->upsert('users', conflict_target => ['email'])
   ->set({ email => 'a@x', name => 'Alicia', score => 2 })
   ->execute;
$row = $db->select->from('users')->where({ email => 'a@x' })->one;
is $row->{name},  'Alicia', 'upsert updated name';
is $row->{score}, 2,        'upsert updated score';

my $count = scalar @{ $db->select->from('users')->all };
is $count, 1, 'still only one row';

# Upsert with only target columns -> DO NOTHING path
eval {
    $db->upsert('users', conflict_target => ['email'])
       ->set({ email => 'a@x' })
       ->execute;
};
ok !$@, 'DO NOTHING upsert ran without error';

# Missing conflict_target should croak
eval { $db->upsert('users') };
like $@, qr/conflict_target/, 'upsert requires conflict_target';

done_testing;
