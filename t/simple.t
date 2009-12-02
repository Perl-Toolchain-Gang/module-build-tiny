use strict;
use warnings;
use File::pushd 1.00 qw(tempd);
use File::Spec 0 ();
use Test::More 0.86;
use lib 't/lib';
use DistGen;

plan tests => 3;

my $dist = DistGen->new(name => 'Foo::Bar');
$dist->chdir_in;
$dist->regen;

ok( ! system($^X, "Build.PL"), "Ran Build.PL");
ok( -f '_build/prereqs', "_build/prereqs created" );
ok( -f '_build/build_params', "_build/build_params created" );



