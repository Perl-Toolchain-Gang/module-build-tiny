package Acme::Module::Build::Tiny;
use strict;
use warnings;
use Data::Dumper 0 ();
use ExtUtils::Install 0 ();
use ExtUtils::MakeMaker 0 ();
use File::Copy 0 ();
use File::Find 0 ();
use File::Path 0 ();
use File::Spec 0 ();
use Test::Harness 0 ();
use Tie::File 0 ();
our $VERSION = '0.01';

my %re = (
  lib => qr{\.(?:pm|pod)$},
  t => qr{\.t},
  prereq => qr{^\s*use\s+(\S+)\s+(v?[0-9._]+)}
);

run(@ARGV) unless caller; # modulino :-)

sub run {
  my $action = shift || 'build';
  __PACKAGE__->$action() or exit 1;
}

sub import {
  my @f = _files('lib');
  print "Creating new 'Build' script for '" . _mod2dist(_path2mod($f[0])) .
        "' version '" . MM->parse_version($f[0]) . "'\n";
  _spew('Build' => "#!$^X\n", _slurp( $INC{_mod2pm(shift)} ) );
  chmod 0755, 'Build';
  File::Path::mkpath '_build';
  open my $fh, '>', '_build/prereqs';
  print {$fh} _data_dump(_find_prereqs());
}

sub build {
  ExtUtils::Install::pm_to_blib({ map {$_=>"blib/$_"} _files('lib')}, 'blib/lib/auto') || 1;
}

sub test {
  build();
  local @INC = (File::Spec->rel2abs('blib/lib'), @INC);
  Test::Harness::runtests(_files('t'));
}

sub install {

}

sub distdir {
  require ExtUtils::Manifest; ExtUtils::Manifest->VERSION(1.57);
  File::Path::rmtree(_distdir());
  _spew('MANIFEST.SKIP', "#!include_default\n^"._distbase()."\n") unless -f 'MANIFEST.SKIP';
  ExtUtils::Manifest::mkmanifest();
  ExtUtils::Manifest::manicopy( ExtUtils::Manifest::maniread(), _distdir() );
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
sub _data_dump {
  'do{ my ' . Data::Dumper->new([shift],['x'])->Purity(1)->Dump() . '$x; }'
}
sub _find_prereqs {
  my %requires;
  for my $guts ( map { _slurp($_) } _files('lib') ) {
    while ( $guts =~ m{$re{prereq}}msgc ) { $requires{$1}=$2; }
  }
  return { requires => \%requires };
}

1;

# vi:et:sts=2:sw=2:ts=2
