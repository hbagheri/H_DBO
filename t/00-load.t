use strict;
use warnings;
use Test::More tests => 3;

use_ok 'H_DBO';
ok defined $H_DBO::VERSION, 'VERSION defined';
ok( H_DBO->can('select'), 'builder methods present' );
