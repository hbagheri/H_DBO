requires 'perl', '5.014';
requires 'DBI', '1.616';
requires 'Carp';
requires 'Scalar::Util';

# DBD::Pg is needed if you want to use the default db_engine => 'Pg'.
# Listed as a recommendation rather than a hard requirement so installs
# without Postgres aren't forced to compile libpq bindings.
recommends 'DBD::Pg', '3.0';

on test => sub {
    requires 'Test::More', '0.96';
    requires 'DBD::SQLite', '1.50';
};
