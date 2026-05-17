use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use TestDB;

my $db = TestDB::fresh();

# Successful txn commits
$db->txn(sub {
    my ($d) = @_;
    $d->insertInto('users')->set({ email => 'a@x', name => 'A' })->execute;
    $d->insertInto('users')->set({ email => 'b@x', name => 'B' })->execute;
});
is scalar @{ $db->select->from('users')->all }, 2, 'txn committed two rows';

# Failing txn rolls back
eval {
    $db->txn(sub {
        my ($d) = @_;
        $d->insertInto('users')->set({ email => 'c@x', name => 'C' })->execute;
        die "boom\n";
    });
};
like $@, qr/boom/, 'txn rethrows the error';
my $c = $db->select->from('users')->where({ email => 'c@x' })->one;
is $c, undef, 'failed txn rolled back the insert';

# Unique-violation error propagates
eval {
    $db->insertInto('users')->set({ email => 'a@x', name => 'duplicate' })->execute;
};
ok $@, 'unique violation raised an exception';

# Bad SQL via setQuery propagates too
eval { $db->setQuery("SELECT * FROM no_such_table")->execute };
ok $@, 'execute on bad SQL raised exception';

done_testing;
