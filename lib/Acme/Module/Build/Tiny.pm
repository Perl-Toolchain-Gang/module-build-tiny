package Acme::Module::Build::Tiny;
use strict;
use warnings;

run() unless caller; # modulino :-)

sub run {
  my $action = shift || 'build';
  exit __PACKAGE__->$action;  
}

sub import { shift->configure }

sub configure {

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

}


1;

# vi:et:sts=2:sw=2:ts=2
