package Acme::Module::Build::Tiny;
use strict;
use warnings;
use ExtUtils::Install 0 ();
use File::Copy 0 ();
use File::Find 0 ();
use File::Path 0 ();
use File::Spec 0 ();
use Test::Harness 0 ();
use Tie::File 0 ();

my %re = ( lib => qr{\.(?:pm|pod)$}, t => qr{\.t} );

run(@ARGV) unless caller; # modulino :-)

sub run {
  my $action = shift || 'build';
  __PACKAGE__->$action() or exit 1;
}

sub import {
  File::Copy::copy $INC{_mod2pm(shift)}, 'Build' or die $!;
  chmod 0755, 'Build';
  tie my @file, 'Tie::File', 'Build';
  unshift @file, "#!$^X";
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

sub clean { File::Path::rmtree($_) for qw/Build blib/; 1; }

sub _mod2pm { (my $mod = shift) =~ s{::}{/}g; return "$mod.pm" }
sub _pm2mod { (my $pm  = shift) =~ s{/}{::}g; return substr $pm, 0, -3 }

sub _files { my ($dir,@f) = shift;
  File::Find::find( sub { -f && /$re{$dir}/ && push @f, $File::Find::name},$dir);
  return @f;
}

1;

# vi:et:sts=2:sw=2:ts=2
