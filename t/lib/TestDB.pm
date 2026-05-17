package TestDB;

# Helper for tests: build an H_DBO around an in-memory SQLite database.
use strict;
use warnings;
use DBI;
use H_DBO;

sub fresh {
    my (%opts) = @_;
    my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '', {
        RaiseError => 1,
        PrintError => 0,
        sqlite_unicode => 1,
    });
    $dbh->do(q{
        CREATE TABLE users (
            id    INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            name  TEXT,
            role  TEXT DEFAULT 'user',
            score INTEGER
        )
    });
    if ($opts{seed}) {
        for my $row (@{ $opts{seed} }) {
            my @cols = sort keys %$row;
            my $cols = join(',', @cols);
            my $qs   = join(',', ('?') x @cols);
            $dbh->do("INSERT INTO users ($cols) VALUES ($qs)", undef, @{$row}{@cols});
        }
    }
    return H_DBO->new({ dbh => $dbh });
}

1;
