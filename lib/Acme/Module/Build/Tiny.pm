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
our $VERSION = 1;

my %re = ( lib => qr{\.(?:pm|pod)$}, t => qr{\.t} );

run(@ARGV) unless caller; # modulino :-)

sub run {
  my $action = shift || 'build';
  __PACKAGE__->$action() or exit 1;
}

sub import {
  my @f = _files('lib');
  print "Creating new 'Build' script for '" . _mod2dist(_path2mod($f[0])) .
        "' version '" . MM->parse_version($f[0]) . "'\n";
  File::Copy::copy $INC{_mod2pm(shift)}, 'Build' or die $!;
  chmod 0755, 'Build';
  tie my @file, 'Tie::File', 'Build';
  unshift @file, "#!$^X";
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

sub dist {

}

sub clean { File::Path::rmtree($_) for qw/Build blib _build/; 1; }

sub _mod2pm   { (my $mod = shift) =~ s{::}{/}g; return "$mod.pm" }
sub _path2mod { (my $pm  = shift) =~ s{/}{::}g; return substr $pm, 5, -3 }
sub _mod2dist { (my $mod = shift) =~ s{::}{-}g; return $mod; }

sub _files { my ($dir,@f) = shift;
  File::Find::find( sub { -f && /$re{$dir}/ && push @f, $File::Find::name},$dir);
  return sort { length $a <=> length $b } @f;
}

sub _data_dump {
  'do{ my ' . Data::Dumper->new([shift],['x'])->Purity(1)->Dump() . '$x; }'
}

sub _slurp { do { local (@ARGV,$/)=$_[0]; <> } }

sub _find_prereqs {
  my %requires;
  for my $guts ( map { _slurp($_) } _files('lib') ) {
    while ( $guts =~ m{^\s*use\s+(\S+)\s+(v?[0-9._]+)}msgc ) {
      $requires{$1}=$2;
    }
  }
  return { requires => \%requires };
}

1;

# vi:et:sts=2:sw=2:ts=2
