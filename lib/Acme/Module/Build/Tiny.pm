package Acme::Module::Build::Tiny;
use strict;
use warnings;
use Config;
use Data::Dumper 0 ();
use ExtUtils::Install 0 ();
use ExtUtils::MakeMaker 0 ();
use File::Copy 0 ();
use File::Find 0 ();
use File::Path 0 ();
use File::Spec 0 ();
use Getopt::Long 0 ();
use Test::Harness 0 ();
use Tie::File 0 ();
our $VERSION = '0.01';

my %re = (
  lib => qr{\.(?:pm|pod)$},
  t => qr{\.t},
  prereq => qr{^\s*use\s+(\S+)\s+(v?[0-9._]+)}m,
);

my %install_map = map { +"blib/$_"  => $Config{"installsite$_"} } qw/lib script/;

my %install_base = ( lib => [qw/lib perl5/], script => [qw/lib bin/] );

my @opts_spec = (
    'install_base:s','uninst:i'
);

sub run {
  my $opt = eval { do '_build/build_params' } || {};
  Getopt::Long::GetOptions($opt, @opts_spec);
  my $action = shift(@ARGV) || 'build';
  __PACKAGE__->can($action)->(%$opt) or exit 1;
}

sub debug {
  my %opt = @_;
  print _data_dump(\%opt) . "\n";
}

sub import {
  Getopt::Long::GetOptions((my $opt={}), @opts_spec);
  my @f = _files('lib');
  print "Creating new 'Build' script for '" . _mod2dist(_path2mod($f[0])) .
        "' version '" . MM->parse_version($f[0]) . "'\n";
  _spew('Build' => "#!$^X\n", _slurp( $INC{_mod2pm(shift)} ) );
  chmod 0755, 'Build';
  File::Path::mkpath '_build';
  _spew( '_build/prereqs', _data_dump(_find_prereqs()) );
  _spew( '_build/build_params', _data_dump($opt) );
  # XXX eventually, copy MYMETA if exists
}

sub build {
  ExtUtils::Install::pm_to_blib({ map {$_=>"blib/$_"} _files('lib')}, 'blib/lib/auto') || 1;
  # XXX eventually scripts/bin
}

sub test {
  build();
  local @INC = (File::Spec->rel2abs('blib/lib'), @INC);
  Test::Harness::runtests(_files('t'));
}

sub _install_base {
  my $map = {map {$_=>File::Spec->catdir($_[0],@{$install_base{$_}})} keys %install_base};
}

sub install {
  my %opt = @_;
  build();
  ExtUtils::Install::install(
    ($opt{install_base} ? _install_base($opt{install_base}) : \%install_map), 1
  );
  return 1;
}

sub distdir {
  require ExtUtils::Manifest; ExtUtils::Manifest->VERSION(1.57);
  File::Path::rmtree(_distdir());
  _spew('MANIFEST.SKIP', "#!include_default\n^"._distbase()."\n") unless -f 'MANIFEST.SKIP';
  ExtUtils::Manifest::mkmanifest();
  ExtUtils::Manifest::manicopy( ExtUtils::Manifest::maniread(), _distdir() );
  # XXX bundle inc && add to MANIFEST in distdir
  # XXX eventually generate META
}

sub dist {
  require Archive::Tar; Archive::Tar->VERSION(1.09);
  distdir();
  my ($distdir,@f) = (_distdir(),_files(_distdir()));
  no warnings 'once';
  $Archive::Tar::DO_NOT_USE_PREFIX = (grep { length($_) >= 100 } @f) ? 0 : 1;
  my $tar = Archive::Tar->new;
  $tar->add_files(@f);
  $_->mode($_->mode & ~022) for $tar->get_files;
  $tar->write("$distdir.tar.gz", 1);
  File::Path::rmtree($distdir);
}

sub clean { File::Path::rmtree('blib'); 1 }

sub realclean { clean(); File::Path::rmtree($_) for qw/Build _build/; 1; }

sub _slurp { do { local (@ARGV,$/)=$_[0]; <> } }
sub _spew { open my $fh, '>', shift; print {$fh} @_ }
sub _data_dump {
  'do{ my ' . Data::Dumper->new([shift],['x'])->Purity(1)->Dump() . '$x; }'
}

sub _mod2pm   { (my $mod = shift) =~ s{::}{/}g; return "$mod.pm" }
sub _path2mod { (my $pm  = shift) =~ s{/}{::}g; return substr $pm, 5, -3 }
sub _mod2dist { (my $mod = shift) =~ s{::}{-}g; return $mod; }

sub _files { my ($dir,@f) = shift;
  my $regex = $re{$dir} || qr/./;
  File::Find::find( sub { -f && /$regex/ && push @f, $File::Find::name},$dir);
  return sort { length $a <=> length $b } @f;
}

sub _distbase { my @f = _files('lib'); return _mod2dist(_path2mod($f[0])) }

sub _distdir { my @f = _files('lib'); return _distbase . "-" . MM->parse_version($f[0]) }

sub _find_prereqs {
  my %requires;
  for my $guts ( map { _slurp($_) } _files('lib') ) {
    while ( $guts =~ m{$re{prereq}}g ) { $requires{$1}=$2; }
  }
  return { requires => \%requires };
}

run() unless caller; # modulino :-)

1;

# vi:et:sts=2:sw=2:ts=2
