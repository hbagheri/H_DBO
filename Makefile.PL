use 5.014;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'H_DBO',
    AUTHOR           => 'Hassan Bagheri <bagheri.h@gmail.com>',
    VERSION_FROM     => 'lib/H_DBO.pm',
    ABSTRACT         => 'Tiny chainable SQL query builder on top of DBI',
    LICENSE          => 'mit',
    MIN_PERL_VERSION => '5.014',
    PREREQ_PM => {
        'DBI'          => '1.616',
        'Carp'         => 0,
        'Scalar::Util' => 0,
    },
    TEST_REQUIRES => {
        'Test::More'   => '0.96',
        'DBD::SQLite'  => '1.50',
        'FindBin'      => 0,
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/hbagheri/H_DBO.git',
                web  => 'https://github.com/hbagheri/H_DBO',
            },
            bugtracker => { web => 'https://github.com/hbagheri/H_DBO/issues' },
        },
    },
    test => { TESTS => 't/*.t' },
);
