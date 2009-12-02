#!perl
use strict;
use warnings;
use File::pushd 1.00 qw(tempd);
use File::Spec 0 ();
use Test::More 0.86;

plan tests => 5;

my $btiny = File::Spec->rel2abs(File::Spec->catfile('blib', 'script', 'btiny'));
my $td = tempd() or die "Couldn't create tmpdir!\n";
ok( -x $btiny, "btiny is in blib and executable" )
  or BAIL_OUT("Can't test without btiny");
ok( ! -e 'Build.PL', "Build.PL doens't exist (new directory)");
ok( ! system($^X, $btiny), "ran btiny without error" );
ok( -e 'Build.PL', "Build.PL created");

my $text = do { local (@ARGV,$/) = 'Build.PL'; <> };
is( $text, "use lib 'inc'; use Acme::Module::Build::Tiny;\n", "contents correct");

