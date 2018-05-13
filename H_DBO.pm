#!/usr/bin/perl
#######################################################################
#H_DBO PAkage ver 1.0.4
#######################################################################
package H_DBO; 

use strict;
use Switch;
use DBI();
use Data::Dumper;
###---------------------------------------------------------------------
## Define Module varables
## return self
###---------------------------------------------------------------------
sub new{
    my $class = shift;
    my $self = {
        _db_name   => shift,
        _db_user   => shift,
        _db_pass   => shift,
        _db_engin  => shift,
        _table     => shift,
        _fields    => shift,
        _set_fields=> shift,
        _set       => shift,
        _values    => shift,
        _where     => shift,
        _order_by  => shift,
        _group_by  => shift,
        _query     => shift,
        _db        => shift,
        _limit     => shift,
        _offset    => shift,
        _type      => shift,
        _object_list=>shift,
        _sth       => shift,
        _isBulk    => shift, 
        _set_rec   => shift, 
    };
    bless $self,$class;
    $self->db_connect();
    return $self;
}
###---------------------------------------------------------------------
## db_disconnect
## Disconnect from db, 
## return UNDEF
###----------------------------------------------------------------------
sub db_disconnect{
    my ($self)=@_;
    $self -> {_db }->disconnect;
}
###---------------------------------------------------------------------
## db_connect
## Connects to db, Currently just to localhost
## return $self
###----------------------------------------------------------------------
sub db_connect{
    my ($self) = @_;
    my $db_engin = $self->{_db_engin};
    my $db_name = $self->{_db_name};
    my $db_user = $self->{_db_user};
    my $db_pass = $self->{_db_pass};
    my $dsn = "DBI:$db_engin:dbname=$db_name";
    my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 }) or die $DBI::errstr;
    $self -> {_db }= $dbh;
    return $self;
}
###---------------------------------------------------------------------
## 
##
###----------------------------------------------------------------------
sub fields{
    my ( $self, $fields ) = @_;
    $self->{_fields} = $fields 	if defined($fields);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub table{
    my ( $self, $table ) = @_;
    $self->{_table} = $table 	if defined($table);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub where{
    my ( $self, $where ) = @_;

    if (defined($where)){
        if(ref($where) eq "HASH"){
            my @keys = keys %$where;
            
            foreach (@keys){
                $self->{_where}.= " AND " if (length $self->{_where} > 0);
                if(ref $where->{$_} eq "ARRAY"){
                    $self->{_where} .= "$_ IN ('".join('\',\'',$where->{$_})."')'";
                } else{
                    $self->{_where} .= "$_ = '".$where->{$_}."'";
                }
            }
        }else{
            $self->{_where}.= " AND " if (length $self->{_where} > 0);
            $self->{_where} = $self->{_where}.$where;
        }
    }
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub orderBy{
    my ( $self, $orderBy,$orderType ) = @_;
    $orderType = "ASC" if ($orderType != "DESC");
    $self->{_order_by} = " " if(length $self->{_order_by} == 0);
    $self->{_order_by} = " $orderBy $orderType " if defined($orderBy);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub limit{
    my($self,$limit,$offset)= @_;
    $self->{_limit} = $limit if defined($limit);
    $self->{_offset}= $offset if defined($offset);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub setQuery{
    my($self , $query)= @_;
    $self->{_query } = $query	if defined($query);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub select{
    my ($self,$fields)=@_;
    $self->{_type} = "SELECT";
    $self->{_fields} = $fields 	if defined($fields);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub update{
    my ($self,$table)=@_;
    $self->{_type} = "UPDATE";
    $self->{_table} = $table 	if defined($table);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub getKey{
    my($self,$req)=@_;
    my %selt_Fieldt = $self->{_set_fields}; 
    my @keys = keys %selt_Fieldt;
    return @keys;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub set{
    my ($self,$set_fields)=@_;
    $self->{_isBulk} = (ref $set_fields eq 'ARRAY')?1:0;
    $self -> {_set_fields}=$set_fields;
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub insertInto{
    my ($self,$table)=@_;
    $self->{_isBulk} = 0;
    $self->{_type} = "INSERT";
    $self->{_table} = $table if defined($table);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub bulkInsertInto{
    my ($self , $table)=@_;
    $self->{_isBulk} = 1;
    $self->{_type} = "INSERT";
    $self->{_table} = $table if defined($table);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub replaceInto{
    my ($self , $table)=@_;
    $self->{_type} = "REPLACE";
    $self->{_table} = $table if defined($table);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub deleteFrom{
    my($self,$table) = @_;
    $self->{_type} = "DELETE";
    $self->{_table} = $table	if defined($table);
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub values{
    my($self,$values) = @_;
    $self->{_values} = $values;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub execQuery{
    my ($self) = @_;
    my $rv;
    $self->{_sth} = $self->{_db}->prepare( $self->{_query} );
    eval {$rv  = $self->{_sth}->execute();};
    if($@){
        print ($@);
        print $self->{_query};
    }
    $self->queryReset();
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub loadObjectList{
    my($self) = @_;
    my @list;
    my $i=0;
    my $row;
    while ($row = $self->{_sth}->fetchrow_hashref()) {
        push (@list, $row);
    }
    return @list;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub from{
    my($self,$table) = @_;
    $self->{_table} = $table;
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub drop{
    my($self,$table) = @_ ; 
    my $db = $self->{_db};
    my $query = qq(DROP TABLE IF EXISTS $table);
    $db->do($query);
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub set4update{
    my($self) = @_;
    my $set=" ";    
    my @keys = keys %{$self->{_set_fields}};
    my $size = @keys;
    foreach my $field ( @keys ){
		my $value = $self->{_set_fields}->{$field};
		$value =~ s/^\s+|\s+$//g;
		if ($value =~ /\w+\([\w\(\)-_\'\"]+\)(\W+)?/ ){
			$set .= "$field = ".$self->{_set_fields}->{$field}.", ";
		}else{
			$set .= "$field = ".$self->{_db}->quote($self->{_set_fields}->{$field}).", ";
		}
    }
    $set =~ s/, $//; # replace comma at the end of the string with empty string
    $self->{_set} = $set;
    return $set;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub makeInsert{
    my($self) = @_;
    my $valString=" ";
    my $fields = "(";
    my @keys;   
    if($self->{_isBulk} eq 1){
		my @recs =@{ $self->{_set_fields}};
        my $rec = $recs[0];
        @keys = keys %$rec;
		$self->{_fields} = \@keys; 
        foreach my $rec (@recs){
            $valString .= $self->makeInsertVals($rec).", ";
        }
        $valString =~ s/, $//;
    }else{
		@keys = keys %{ $self->{_set_fields} };
		$self->{_fields} = \@keys;
        $valString = $self->makeInsertVals($self->{_set_fields});
    }
    
    $fields = join ', ', sort @keys;
    $self->{_fields} = "($fields)";
    $self->{_values} = $valString;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub makeInsertVals{
    my ($self,$rec)=@_;
    my @keys= @{ $self->{_fields} };
    my $valString="(";
    foreach my $key (sort (@keys)){
	   print Dumper $key."=".$rec->{$key};
       if($rec->{$key} eq undef){
           $valString .= "NULL, ";
       }else{
           $valString .= $self->{_db}->quote($rec->{$key}).", ";
       }
    }
    $valString =~ s/, $/)/;
    return $valString; 
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub query{
    my($self,$query) = @_;
    
    if($query ne undef ){
        $self->{ _query } = $query;# if defined($query);
    }else{	
        my $qType =  uc $self->{_type};
        switch($qType){
            case "INSERT" { 
                $self->makeInsert();
                $self->{_query} = "INSERT INTO ".$self->{_table}." " .$self->{_fields}." VALUES ".$self->{_values};
            }
            
            case "REPLACE" { 
				$self->makeInsert();
                $self->{_query} = "REPLACE INTO ".$self->{_table}." ".$self->{_fields}." VALUES ".$self->{_values};
            }
            
            case "SELECT" {
                my $query = "SELECT "       .$self->{_fields}." FROM ".$self->{_table};
                $query = $query." WHERE "   .$self->{_where}    if (length($self->{_where}));
                $query = $query." GROUP BY ".$self->{_groupby}  if (length($self->{_groupby}));
                $query = $query." ORDER BY ".$self->{_order_by} if (length($self->{_order_by}));
                $query = $query." LIMIT "   .$self->{_limit}    if (length($self->{_limit}));
                $query = $query." OFFSET "  .$self->{_offset}   if (length($self->{_offset}));
                $self->{_query}=$query;
            }
            
            case "DELETE"{
                $self->{_query} = "DELETE FROM ".$self->{_table};
                $self->{_query} = $self->{_query}." WHERE ".$self->{_where} if (length($self->{_where}));
            }
            
            case "UPDATE"{
                $self->set4update();
                    $self->{_query} =  "UPDATE ".$self->{_table} ." SET ".$self->{_set};
                    $self->{_query} = $self->{_query}." WHERE ".$self->{_where} if (length($self->{_where}));
            }
		}
    }
    return $self;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub queryReset{
    my($self)=@_;
    $self->{_table}     = undef;
    $self->{_fields}    = undef;
    $self->{_set_fields}= undef;
    $self->{_values}    = undef;
    $self->{_where}     = undef;
    $self->{_order_by}  = undef;
    $self->{_group_by}  = undef;
    $self->{_query}     = undef;
    $self->{_limit}     = undef;
    $self->{_offset}    = undef;
    $self->{_type}      = undef;
    $self->{_isBulk}    = undef;
}
###---------------------------------------------------------------------
##
##
###----------------------------------------------------------------------
sub getQuery{
    my($self)=@_;
    return $self->{_query};
}
##----------------------------------------------------------------------
1;#important
