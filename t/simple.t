use strict;
use warnings;
use File::pushd 1.00 qw(tempd);
use File::Spec 0 ();
use Capture::Tiny 0 qw(capture);
use Test::More 0.86;
use lib 't/lib';
use DistGen qw/undent/;

plan tests => 9;

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $dist = DistGen->new(name => 'Foo::Bar');
$dist->chdir_in;
$dist->add_file('bin/simple', undent(<<"    ---"));
    use Simple;
    print Simple->VERSION . "\n";
    ---
$dist->regen;

my ($guts, $ec);

sub _slurp { do { local (@ARGV,$/)=$_[0]; <> } }

#--------------------------------------------------------------------------#
# configure
#--------------------------------------------------------------------------#

{
  ok( ! system($^X, "Build.PL"), "Ran Build.PL");
  ok( -f 'Build' && -x _, "Build created and executable" );

  open my $fh, "<", "Build";
  my $line = <$fh>;

  like( $line, qr/\A#!\Q$^X\E/, "Build has shebang line with \$^X" );
  ok( -f '_build/prereqs', "_build/prereqs created" );
  ok( -f '_build/build_params', "_build/build_params created" );
}

#--------------------------------------------------------------------------#
# build
#--------------------------------------------------------------------------#

{
  ok( capture { ! system($^X, "Build") }, "Ran Build");
  ok( -d 'blib',        "created blib" );
  ok( -d 'blib/lib',    "created blib/lib" );
  ok( -d 'blib/script', "created blib/script" );
}


