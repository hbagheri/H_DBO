use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use Test::More;
use TestDB;

# Values that would break naive single-quote-escaping must round-trip safely
# through placeholders.

my $db = TestDB::fresh();

my @nasty = (
    q{O'Brien},
    q{Robert'); DROP TABLE users;--},
    q{back\\slash},
    qq{newline\nhere},
    q{},                       # empty string
    q{🎉 unicode},
);

for my $i (0 .. $#nasty) {
    my $email = "user$i\@x";
    $db->insertInto('users')->set({ email => $email, name => $nasty[$i] })->execute;
}

# Table must still exist (i.e. the injection didn't work)
my $rows = $db->select->from('users')->all;
is scalar(@$rows), scalar(@nasty), 'table intact, all rows inserted';

# Each value must round-trip exactly
for my $i (0 .. $#nasty) {
    my $row = $db->select->from('users')->where({ email => "user$i\@x" })->one;
    is $row->{name}, $nasty[$i], "value $i round-tripped exactly";
}

# WHERE with nasty value
my $bobby = $db->select->from('users')
                       ->where({ name => q{Robert'); DROP TABLE users;--} })
                       ->all;
is scalar(@$bobby), 1, 'nasty value matched via placeholder';

# Identifier validation
eval { $db->orderBy("id; DROP TABLE users") };
like $@, qr/not a valid identifier/, 'orderBy rejects non-identifier';

eval { $db->groupBy("foo; DROP TABLE users") };
like $@, qr/not a valid identifier/, 'groupBy rejects non-identifier';

eval { $db->drop("users; DROP TABLE x") };
like $@, qr/not a valid identifier/, 'drop rejects non-identifier';

done_testing;
