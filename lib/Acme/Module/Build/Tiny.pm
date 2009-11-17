package Acme::Module::Build::Tiny;
use strict;
use warnings;
use File::Copy 0 qw(copy);
use File::Path 0 qw(mkpath rmtree);
use Tie::File 0 ();

run(@ARGV) unless caller; # modulino :-)

sub run {
  my $action = shift || 'build';
  __PACKAGE__->$action() or exit 1;
}

sub import { shift->configure }

sub configure {
  copy $INC{_mod2pm(shift)}, 'Build' or die $!;
  chmod 0755, 'Build';
  tie my @file, 'Tie::File', 'Build';
  unshift @file, "#!$^X";
}

sub build {
}

sub test {

}

sub install {

}

sub dist {

}

sub clean {
  rmtree('Build');
}

sub _mod2pm { (my $mod = shift) =~ s{::}{/}g; return "$mod.pm" }

1;

# vi:et:sts=2:sw=2:ts=2
