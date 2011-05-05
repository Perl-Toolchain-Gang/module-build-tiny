#! perl
use strict;
use warnings;
use Config;
use File::pushd 1.00 qw(tempd);
use File::Spec 0 ();
use Capture::Tiny 0 qw(capture);
use Test::More 0.86;
use lib 't/lib';
use DistGen qw/undent/;

plan tests => 16;

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $dist = DistGen->new(name => 'Foo::Bar');
$dist->chdir_in;
$dist->add_file('script/simple', undent(<<"    ---"));
    #!perl
    use Foo::Bar;
    print Simple->VERSION . "\n";
    ---
$dist->regen;

my $interpreter = ($Config{startperl} eq $^X )
                ? qr/#!\Q$^X\E/
                : qr/(?:#!\Q$^X\E|\Q$Config{startperl}\E)/;
my ($guts, $ec);

sub _mod2pm   { (my $mod = shift) =~ s{::}{/}g; return "$mod.pm" }
sub _path2mod { (my $pm  = shift) =~ s{/}{::}g; return substr $pm, 5, -3 }
sub _mod2dist { (my $mod = shift) =~ s{::}{-}g; return $mod; }
sub _slurp { do { local (@ARGV,$/)=$_[0]; <> } }

#--------------------------------------------------------------------------#
# configure
#--------------------------------------------------------------------------#

{
  ok( ! system($^X, "Build.PL"), "Ran Build.PL");
  ok( -f 'Build' && -x _, "Build created and executable" );

  open my $fh, "<", "Build";
  my $line = <$fh>;

  like( $line, qr{\A$interpreter}, "Build has shebang line with \$^X" );
  ok( -f '_build_params', "_build_params created" );
}

#--------------------------------------------------------------------------#
# build
#--------------------------------------------------------------------------#

{
  ok( capture { ! system($^X, "Build") }, "Ran Build");
  ok( -d 'blib',        "created blib" );
  ok( -d 'blib/lib',    "created blib/lib" );
  ok( -d 'blib/script', "created blib/script" );

  # check pm
  my $pmfile = _mod2pm($dist->name);
  ok( -f 'blib/lib/' . $pmfile, "$dist->{name} copied to blib" );
  is( _slurp("lib/$pmfile"), _slurp("blib/lib/$pmfile"), "pm contents are correct" );
  ok( ! ((stat "blib/lib/$pmfile")[2] & 0222), "pm file in blib is readonly" );

  # check bin
  ok( -f 'blib/script/simple', "bin/simple copied to blib" );
  like( _slurp("blib/script/simple"), '/' .quotemeta(_slurp("blib/script/simple")) . "/",
    "blib/script/simple contents are correct" );
  ok( ! ((stat "blib/script/simple")[2] & 0222), "blib/script/simple is readonly" );
  ok( -x "blib/script/simple", "blib/script/simple is executable" );
  open my $fh, "<", "blib/script/simple";
  my $line = <$fh>;
  like( $line, qr{\A$interpreter}, "blib/script/simple has shebang line with \$^X" );

}

