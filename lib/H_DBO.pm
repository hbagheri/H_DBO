package H_DBO;

use 5.014;
use strict;
use warnings;
use Carp qw(croak);
use DBI;
use Scalar::Util qw(blessed);

our $VERSION = '2.0.0';

# ---------------------------------------------------------------------------
# H_DBO::Raw  --  marker for a raw SQL fragment (with optional bind values)
# Used as an escape hatch so callers can inject things like NOW(), nextval(),
# JSON expressions, etc. without us guessing via regex.
# ---------------------------------------------------------------------------
package H_DBO::Raw;

sub new {
    my ($class, $sql, @binds) = @_;
    return bless { sql => $sql, binds => [@binds] }, $class;
}
sub sql   { $_[0]->{sql} }
sub binds { @{ $_[0]->{binds} } }

package H_DBO;

sub _is_raw { blessed($_[0]) && $_[0]->isa('H_DBO::Raw') }

# Identifier validator. Permits letters, digits, underscore and dot
# (for schema-qualified names). Anything else is rejected to avoid
# unsanitised identifiers reaching the SQL string.
my $IDENT_RE = qr/\A[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\z/;

# ---------------------------------------------------------------------------
# Constructor.  Accepts a hashref or a flat list of key/value pairs:
#     H_DBO->new({ db_name => 'app', db_user => 'u', db_pass => 'p' });
#     H_DBO->new( db_name => 'app', db_engine => 'Pg', host => 'db.local' );
#     H_DBO->new({ dbh => $existing_dbh });
# ---------------------------------------------------------------------------
sub new {
    my $class = shift;
    my %args  = (@_ == 1 && ref $_[0] eq 'HASH') ? %{ $_[0] } : @_;

    my $self = {
        _db_name   => $args{db_name},
        _db_user   => $args{db_user},
        _db_pass   => $args{db_pass},
        _db_engine => $args{db_engine} // 'Pg',
        _host      => $args{host},
        _port      => $args{port},
        _dsn_extra => $args{dsn_extra},
        _dbi_attrs => $args{dbi_attrs} // {},
        _db        => $args{dbh},
        _binds     => [],
    };
    bless $self, $class;
    $self->_db_connect unless $self->{_db};
    return $self;
}

sub _db_connect {
    my ($self) = @_;
    croak "db_name is required" unless defined $self->{_db_name};
    my $engine = $self->{_db_engine};

    my $dsn;
    if ($engine eq 'SQLite') {
        $dsn = "DBI:SQLite:dbname=$self->{_db_name}";
    } else {
        my @parts = ("dbname=$self->{_db_name}");
        push @parts, "host=$self->{_host}" if defined $self->{_host};
        push @parts, "port=$self->{_port}" if defined $self->{_port};
        push @parts, $self->{_dsn_extra}   if defined $self->{_dsn_extra};
        $dsn = "DBI:$engine:" . join(';', @parts);
    }

    my %attrs = (
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
        %{ $self->{_dbi_attrs} },
    );

    $self->{_db} = DBI->connect($dsn, $self->{_db_user}, $self->{_db_pass}, \%attrs);
    return $self;
}

sub dbh { $_[0]->{_db} }

sub disconnect {
    my ($self) = @_;
    $self->{_db}->disconnect if $self->{_db};
    delete $self->{_db};
    return $self;
}

# Class/instance method, returns a raw-SQL marker.
sub raw {
    my $proto = shift;
    return H_DBO::Raw->new(@_);
}

# ---------------------------------------------------------------------------
# Internal: clear builder state before starting a new query.
# ---------------------------------------------------------------------------
sub _reset {
    my ($self) = @_;
    delete @{$self}{qw(
        _table _fields _set_fields _values _where _order_by _group_by
        _query _limit _offset _type _isBulk _conflict_target _sth
    )};
    $self->{_binds} = [];
    return $self;
}

# ---------------------------------------------------------------------------
# Statement-type entry points.  Each clears prior state then sets the type.
# ---------------------------------------------------------------------------
sub select {
    my ($self, $fields) = @_;
    $self->_reset;
    $self->{_type}   = 'SELECT';
    $self->{_fields} = $fields // '*';
    return $self;
}

sub insertInto {
    my ($self, $table) = @_;
    $self->_reset;
    $self->{_type}   = 'INSERT';
    $self->{_table}  = $table;
    $self->{_isBulk} = 0;
    return $self;
}

sub bulkInsertInto {
    my ($self, $table) = @_;
    $self->_reset;
    $self->{_type}   = 'INSERT';
    $self->{_table}  = $table;
    $self->{_isBulk} = 1;
    return $self;
}

sub upsert {
    my ($self, $table, %opts) = @_;
    $self->_reset;
    croak "upsert requires conflict_target => ['col', ...]"
        unless ref $opts{conflict_target} eq 'ARRAY' && @{ $opts{conflict_target} };
    $self->{_type}             = 'UPSERT';
    $self->{_table}            = $table;
    $self->{_isBulk}           = $opts{bulk} ? 1 : 0;
    $self->{_conflict_target}  = $opts{conflict_target};
    return $self;
}

sub update {
    my ($self, $table) = @_;
    $self->_reset;
    $self->{_type}  = 'UPDATE';
    $self->{_table} = $table;
    return $self;
}

sub deleteFrom {
    my ($self, $table) = @_;
    $self->_reset;
    $self->{_type}  = 'DELETE';
    $self->{_table} = $table;
    return $self;
}

# ---------------------------------------------------------------------------
# Builder methods.  All chainable.
# ---------------------------------------------------------------------------
sub from {
    my ($self, $table) = @_;
    $self->{_table} = $table if defined $table;
    return $self;
}

sub table {
    my ($self, $table) = @_;
    $self->{_table} = $table if defined $table;
    return $self;
}

sub fields {
    my ($self, $fields) = @_;
    $self->{_fields} = $fields if defined $fields;
    return $self;
}

sub set {
    my ($self, $data) = @_;
    croak "set() needs a hashref or arrayref of hashrefs"
        unless ref $data eq 'HASH' || ref $data eq 'ARRAY';
    $self->{_set_fields} = $data;
    $self->{_isBulk}     = (ref $data eq 'ARRAY') ? 1 : 0;
    return $self;
}

sub where {
    my ($self, $where, @binds) = @_;
    return $self unless defined $where;

    my (@preds, @new_binds);

    if (ref $where eq 'HASH') {
        for my $col (sort keys %$where) {
            croak "where: column name '$col' is not a valid identifier"
                unless $col =~ $IDENT_RE;
            my $val = $where->{$col};
            if (ref $val eq 'ARRAY') {
                if (!@$val) {
                    # Empty IN list — match nothing rather than emit invalid SQL.
                    push @preds, '1=0';
                } else {
                    push @preds, "$col IN (" . join(',', ('?') x @$val) . ')';
                    push @new_binds, @$val;
                }
            } elsif (_is_raw($val)) {
                push @preds, "$col = " . $val->sql;
                push @new_binds, $val->binds;
            } elsif (!defined $val) {
                push @preds, "$col IS NULL";
            } else {
                push @preds, "$col = ?";
                push @new_binds, $val;
            }
        }
    } else {
        push @preds,     $where;
        push @new_binds, @binds;
    }

    my $clause = join(' AND ', @preds);
    $self->{_where} = (defined $self->{_where} && length $self->{_where})
        ? "$self->{_where} AND $clause"
        : $clause;
    push @{ $self->{_binds} }, @new_binds;
    return $self;
}

sub orderBy {
    my ($self, $col, $dir) = @_;
    return $self unless defined $col;
    $dir = uc($dir // 'ASC');
    croak "orderBy direction must be ASC or DESC" unless $dir eq 'ASC' || $dir eq 'DESC';
    croak "orderBy: '$col' is not a valid identifier"
        unless $col =~ $IDENT_RE;
    $self->{_order_by} = (defined $self->{_order_by} && length $self->{_order_by})
        ? "$self->{_order_by}, $col $dir"
        : "$col $dir";
    return $self;
}

sub groupBy {
    my ($self, @cols) = @_;
    return $self unless @cols;
    for my $c (@cols) {
        croak "groupBy: '$c' is not a valid identifier" unless $c =~ $IDENT_RE;
    }
    $self->{_group_by} = join(', ', @cols);
    return $self;
}

sub limit {
    my ($self, $limit, $offset) = @_;
    if (defined $limit) {
        croak "limit must be a non-negative integer" unless $limit =~ /\A\d+\z/;
        $self->{_limit} = $limit;
    }
    if (defined $offset) {
        croak "offset must be a non-negative integer" unless $offset =~ /\A\d+\z/;
        $self->{_offset} = $offset;
    }
    return $self;
}

sub offset {
    my ($self, $offset) = @_;
    if (defined $offset) {
        croak "offset must be a non-negative integer" unless $offset =~ /\A\d+\z/;
        $self->{_offset} = $offset;
    }
    return $self;
}

# ---------------------------------------------------------------------------
# Internal query builders.
# ---------------------------------------------------------------------------
sub _build_insert_parts {
    my ($self) = @_;
    my @rows = $self->{_isBulk}
        ? @{ $self->{_set_fields} // [] }
        : ($self->{_set_fields});
    croak "set() required before insert/upsert"
        unless @rows && ref $rows[0] eq 'HASH' && %{ $rows[0] };

    my @cols       = sort keys %{ $rows[0] };
    my $col_clause = '(' . join(', ', @cols) . ')';

    my (@row_clauses, @binds);
    for my $row (@rows) {
        my @placeholders;
        for my $c (@cols) {
            my $v = $row->{$c};
            if (_is_raw($v)) {
                push @placeholders, $v->sql;
                push @binds, $v->binds;
            } elsif (!defined $v) {
                push @placeholders, 'NULL';
            } else {
                push @placeholders, '?';
                push @binds, $v;
            }
        }
        push @row_clauses, '(' . join(', ', @placeholders) . ')';
    }
    return ($col_clause, join(', ', @row_clauses), \@cols, \@binds);
}

sub _build_set {
    my ($self) = @_;
    croak "set() with a hashref is required for update"
        unless ref $self->{_set_fields} eq 'HASH' && %{ $self->{_set_fields} };
    my (@parts, @binds);
    for my $col (sort keys %{ $self->{_set_fields} }) {
        croak "update: column name '$col' is not a valid identifier"
            unless $col =~ $IDENT_RE;
        my $v = $self->{_set_fields}{$col};
        if (_is_raw($v)) {
            push @parts, "$col = " . $v->sql;
            push @binds, $v->binds;
        } elsif (!defined $v) {
            push @parts, "$col = NULL";
        } else {
            push @parts, "$col = ?";
            push @binds, $v;
        }
    }
    return (join(', ', @parts), \@binds);
}

# ---------------------------------------------------------------------------
# query()  --  materialise the SQL and bind list from the current state.
# Stored on $self as _query and _binds.  Returns $self.
# ---------------------------------------------------------------------------
sub query {
    my ($self, $sql) = @_;

    if (defined $sql) {
        $self->{_query} = $sql;
        return $self;
    }

    my $type = $self->{_type} // croak "no query type set; call select/insertInto/update/deleteFrom/upsert first";
    my $table = $self->{_table};
    croak "table name required" unless defined $table && length $table;

    if ($type eq 'SELECT') {
        my $cols = $self->{_fields} // '*';
        $cols = join(', ', @$cols) if ref $cols eq 'ARRAY';
        my $q = "SELECT $cols FROM $table";
        $q .= " WHERE $self->{_where}"       if defined $self->{_where} && length $self->{_where};
        $q .= " GROUP BY $self->{_group_by}" if defined $self->{_group_by};
        $q .= " ORDER BY $self->{_order_by}" if defined $self->{_order_by};
        $q .= " LIMIT $self->{_limit}"       if defined $self->{_limit};
        $q .= " OFFSET $self->{_offset}"     if defined $self->{_offset};
        $self->{_query} = $q;
    }
    elsif ($type eq 'INSERT') {
        my ($cols, $vals, undef, $binds) = $self->_build_insert_parts;
        $self->{_query} = "INSERT INTO $table $cols VALUES $vals";
        $self->{_binds} = $binds;
    }
    elsif ($type eq 'UPSERT') {
        my ($cols, $vals, $col_arr, $binds) = $self->_build_insert_parts;
        my $target = join(', ', @{ $self->{_conflict_target} });
        my %tset   = map { $_ => 1 } @{ $self->{_conflict_target} };
        my @upd    = grep { !$tset{$_} } @$col_arr;
        if (@upd) {
            my $set = join(', ', map { "$_ = EXCLUDED.$_" } @upd);
            $self->{_query} = "INSERT INTO $table $cols VALUES $vals "
                            . "ON CONFLICT ($target) DO UPDATE SET $set";
        } else {
            $self->{_query} = "INSERT INTO $table $cols VALUES $vals "
                            . "ON CONFLICT ($target) DO NOTHING";
        }
        $self->{_binds} = $binds;
    }
    elsif ($type eq 'UPDATE') {
        my ($set_sql, $set_binds) = $self->_build_set;
        my $q     = "UPDATE $table SET $set_sql";
        my @binds = @$set_binds;
        if (defined $self->{_where} && length $self->{_where}) {
            $q .= " WHERE $self->{_where}";
            push @binds, @{ $self->{_binds} };
        }
        $self->{_query} = $q;
        $self->{_binds} = \@binds;
    }
    elsif ($type eq 'DELETE') {
        my $q = "DELETE FROM $table";
        $q .= " WHERE $self->{_where}" if defined $self->{_where} && length $self->{_where};
        $self->{_query} = $q;
        # _binds already contains the where bindings.
    }
    else {
        croak "unknown query type: $type";
    }

    return $self;
}

sub setQuery {
    my ($self, $sql, @binds) = @_;
    $self->_reset;
    $self->{_query} = $sql;
    $self->{_binds} = [@binds];
    return $self;
}

sub getQuery { $_[0]->{_query} }
sub getBinds { @{ $_[0]->{_binds} // [] } }

# ---------------------------------------------------------------------------
# Execution.  Errors propagate via DBI's RaiseError -> croak.
# ---------------------------------------------------------------------------
sub execute {
    my ($self) = @_;
    $self->query unless defined $self->{_query};
    my $sth = $self->{_db}->prepare($self->{_query});
    $sth->execute(@{ $self->{_binds} // [] });
    $self->{_sth} = $sth;
    return $self;
}

# Backward-compatible alias for the old name.
sub execQuery { goto &execute }

sub all {
    my ($self) = @_;
    $self->execute unless $self->{_sth};
    return $self->{_sth}->fetchall_arrayref({});
}

sub one {
    my ($self) = @_;
    $self->execute unless $self->{_sth};
    return $self->{_sth}->fetchrow_hashref;
}

# Legacy alias — returns a list of hashrefs rather than an arrayref.
sub loadObjectList {
    my ($self) = @_;
    return @{ $self->all };
}

sub rows {
    my ($self) = @_;
    return $self->{_sth} ? $self->{_sth}->rows : 0;
}

# ---------------------------------------------------------------------------
# Utilities.
# ---------------------------------------------------------------------------
sub drop {
    my ($self, $table) = @_;
    croak "drop: '$table' is not a valid identifier" unless defined $table && $table =~ $IDENT_RE;
    $self->{_db}->do("DROP TABLE IF EXISTS $table");
    return $self;
}

# Wrap a coderef in BEGIN/COMMIT, rolling back on exception.
sub txn {
    my ($self, $code) = @_;
    croak "txn requires a coderef" unless ref $code eq 'CODE';
    my $dbh = $self->{_db};
    $dbh->begin_work;
    my $rv = eval { $code->($self) };
    if (my $err = $@) {
        eval { $dbh->rollback };
        croak $err;
    }
    $dbh->commit;
    return $rv;
}

1;

__END__

=encoding utf-8

=head1 NAME

H_DBO - Tiny chainable SQL query builder on top of DBI

=head1 SYNOPSIS

    use H_DBO;

    my $db = H_DBO->new({
        db_engine => 'Pg',
        db_name   => 'app',
        db_user   => 'app',
        db_pass   => 'secret',
        host      => 'db.example.com',
        port      => 5432,
    });

    # SELECT
    my $rows = $db->select(['id', 'email'])
                  ->from('users')
                  ->where({ status => 'active', role => ['admin', 'editor'] })
                  ->orderBy('id', 'DESC')
                  ->limit(10)
                  ->all;

    # INSERT
    $db->insertInto('users')
       ->set({ email => 'a@b.c', created_at => H_DBO->raw('NOW()') })
       ->execute;

    # Bulk INSERT
    $db->bulkInsertInto('users')
       ->set([
           { email => 'a@b.c' },
           { email => 'd@e.f' },
       ])
       ->execute;

    # UPSERT (PostgreSQL or SQLite >= 3.24)
    $db->upsert('users', conflict_target => ['email'])
       ->set({ email => 'a@b.c', name => 'Alice' })
       ->execute;

    # UPDATE
    $db->update('users')
       ->set({ name => 'Bob' })
       ->where({ id => 7 })
       ->execute;

    # DELETE
    $db->deleteFrom('users')->where({ id => 7 })->execute;

    # Inspect the prepared SQL without running it
    my $sql   = $db->select('*')->from('users')->where({ id => 1 })->query->getQuery;
    my @binds = $db->getBinds;

    # Transactions
    $db->txn(sub {
        my ($d) = @_;
        $d->update('accounts')->set({ balance => H_DBO->raw('balance - ?', 10) })->where({ id => 1 })->execute;
        $d->update('accounts')->set({ balance => H_DBO->raw('balance + ?', 10) })->where({ id => 2 })->execute;
    });

=head1 DESCRIPTION

C<H_DBO> is a small, opinionated wrapper around L<DBI> that builds SQL via a
chainable interface and uses placeholders + bind values for every user-supplied
value. It is designed for PostgreSQL but works with any DBD that DBI supports;
the L</upsert> method emits standard SQL:2003 C<INSERT ... ON CONFLICT> syntax,
which is supported by PostgreSQL >= 9.5 and SQLite >= 3.24.

=head1 CONSTRUCTOR

=head2 new(\%opts | %opts)

Connects to the database. Recognised options:

=over 4

=item * C<db_name>   - required unless C<dbh> is supplied.

=item * C<db_user>, C<db_pass>

=item * C<db_engine> - defaults to C<Pg>; use C<SQLite> for sqlite, etc.

=item * C<host>, C<port>, C<dsn_extra> - extra DSN bits (joined with C<;>).

=item * C<dbi_attrs> - hashref merged into DBI connect attrs. Defaults turn on
        C<RaiseError> and turn off C<PrintError>.

=item * C<dbh> - an already-opened DBI handle; bypasses connecting.

=back

=head1 BUILDER METHODS

C<select>, C<insertInto>, C<bulkInsertInto>, C<upsert>, C<update>, C<deleteFrom>
each clear builder state and set the statement type. Then chain:
C<from>, C<table>, C<fields>, C<set>, C<where>, C<orderBy>, C<groupBy>,
C<limit>, C<offset>. All return C<$self>.

C<where> accepts either a hashref (column => value, value may be a scalar, an
arrayref for C<IN>, C<undef> for C<IS NULL>, or an C<H_DBO::Raw> fragment) or a
raw SQL fragment with bind values:

    $db->where("created_at > ? AND status = ?", '2026-01-01', 'active');

Multiple calls to C<where> are ANDed together.

=head1 EXECUTION

=over 4

=item C<query()> - materialise SQL + bind list, store on the object.

=item C<execute()> - prepare and execute. Returns C<$self>. Errors propagate via
C<DBI>'s C<RaiseError>.

=item C<all()> - execute (if needed) and return an arrayref of row hashrefs.

=item C<one()> - execute and return the first row as a hashref (or undef).

=item C<rows()> - number of rows affected by the last execute.

=item C<loadObjectList()> - legacy: returns the rows as a list.

=item C<getQuery>, C<getBinds> - inspect the materialised query and binds.

=item C<setQuery($sql, @binds)> - skip the builder and run arbitrary SQL.

=item C<txn(\&code)> - run C<&code> inside a transaction; rollback on exception.

=back

=head1 RAW SQL FRAGMENTS

Use C<< H_DBO->raw($sql, @binds) >> to inject an unquoted SQL fragment in any
place a value is accepted (in C<set>, in a C<where> hash). The fragment is
spliced into the query and its binds are appended in order.

    $db->update('users')
       ->set({ last_seen => H_DBO->raw('NOW()') })
       ->where({ id => 7 })
       ->execute;

=head1 SECURITY

All user-supplied B<values> go through DBI placeholders. Identifiers (table,
column, ORDER BY / GROUP BY targets) are validated against
C<[A-Za-z_][A-Za-z0-9_]*> with optional schema prefix; anything else is
rejected.

If you find yourself wanting to inject something more dynamic, build it with
L</raw> rather than string-concatenating into a builder method.

=head1 LICENSE

MIT - see the C<LICENSE> file.

=cut
