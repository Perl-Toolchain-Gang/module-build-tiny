package Module::Build::Tiny;
use strict;
use warnings;
use Config;
use Data::Dumper 0 ();
use ExtUtils::Install 0 qw/pm_to_blib install/;
use ExtUtils::MakeMaker 0 ();
use File::Basename 0 qw/dirname/;
use File::Find 0 qw/find/;
use File::Path 0 qw/mkpath rmtree/;
use File::Spec::Functions 0 qw/catfile catdir rel2abs/;
use Getopt::Long 0 qw/GetOptions/;
use Test::Harness 0 qw/runtests/;
use Text::ParseWords 0 qw/shellwords/;
use Exporter 5.57 'import';
our $VERSION = '0.05';
our @EXPORT = qw/Build Build_PL/;

my %re = (
  lib     => qr{\.(?:pm|pod)$},
  t       => qr{\.t},
);

my %install_map = map { +"blib/$_"  => $Config{"installsite$_"} } qw/lib script/;

my %install_base = ( lib => [qw/lib perl5/], script => [qw/lib bin/] );

my @opts_spec = ( 'install_base:s', 'uninst:i' );

sub _split_like_shell {
  my $string = shift;
  $string =~ s/^\s+|\s+$//g;
  return shellwords($string);
}

sub _home { return $ENV{HOME} || $ENV{USERPROFILE} }

sub _default_rc { return catfile( _home(), '.modulebuildrc' ) }

sub _get_rc_opts {
  my $rc_file = ($ENV{MODULEBUILDRC} || _default_rc());
  return {} unless -f $rc_file;
  my $guts = _slurp( $rc_file );
  $guts =~ s{\n[ \t]+}{ }mg; # join lines with leading whitespace
  $guts =~ s{^#.*$}{}mg; # strip comments
  $guts =~ s{\n\s*\n}{\n}mg; # empty lines
  my %opt = map  { my ($k,$v) = $_ =~ /(\S+)\s+(.*)/; $k => $v } 
            grep { /\S/ } split /\n/, $guts;
  return \%opt;
}

sub _get_options {
  my ($action,$opt) = @_;
  my $rc_opts = _get_rc_opts;
  for my $s ( $ENV{PERL_MB_OPT}, $rc_opts->{$action}, $rc_opts->{'*'} ) {
    unshift @ARGV, _split_like_shell($s) if defined $s && length $s;
  }
  GetOptions($opt, @opts_spec);
}

my %actions;
%actions = (
	build => sub {
	  my $map = {
		(map {$_=>"blib/$_"} _files('lib')),
		(map {;"bin/$_"=>"blib/script/$_"} map {s{^bin/}{}; $_} _files('bin')),
	  };
	  pm_to_blib($map, 'blib/lib/auto');
	  ExtUtils::MM->fixin($_), chmod(0555, $_) for _files('blib/script');
	  return 1;
	},
	test => sub {
	  $actions{build}->();
	  local @INC = (rel2abs('blib/lib'), @INC);
	  runtests(grep { !m{/\.} } _files('t'));
	},
	install => sub {
	  my %opt = @_;
	  $actions{build}->();
	  install(($opt{install_base} ? _install_base($opt{install_base}) : \%install_map), 1);
	  return 1;
	},
	clean => sub {
	 	rmtree('blib');
		1;
	},
	realclean => sub {
		$actions{clean}->();
		rmtree($_) for _distdir(), qw/Build _build/;
		1;
	},
);

sub Build(\@) {
  my $arguments = shift;
  my $opt = eval { do '_build/build_params' } || {};
  my $action = defined $arguments->[0] && $arguments->[0] =~ /\A\w+\z/ ? $ARGV[0] : 'build';
  _get_options($action, $opt);
  my $action_sub = $actions{$action};
  $action_sub ? $action_sub->(%$opt) : exit 1;
}

sub Build_PL {
  _get_options('Build_PL', my $opt = {});
  my @f = _files('lib');
  my $meta = {
    name     => _mod2dist(_path2mod($f[0])),
    version  => MM->parse_version($f[0]),
  };
  print "Creating new 'Build' script for '$meta->{name}' version '$meta->{version}'\n";
  my $perl = $^X =~ /\Aperl[.0-9]*\z/ ? $Config{perlpath} : $^X;
  my $dir = _path2mod($f[0]) eq __PACKAGE__ ? 'lib' : 'inc' ;
  _spew('Build' => "#!$perl\n", "use lib '$dir';\nuse Module::Build::Tiny;\nBuild(\@ARGV);\n");
  chmod 0755, 'Build';
  _spew( '_build/build_params', _data_dump($opt) );
  _spew( 'MYMETA.yml', _slurp('META.yml')) if -f 'META.yml';
}

sub _install_base {
  return { map { $_ => catdir($_[0], @{ $install_base{$_} }) } keys %install_base };
}

sub _slurp { do { local (@ARGV,$/)=$_[0]; <> } }
sub _spew {
  my $file = shift;
  mkpath(dirname($file));
  open my $fh, '>', $file;
  print {$fh} @_;
}

sub _data_dump {
  'do{ my ' . Data::Dumper->new([shift],['x'])->Purity(1)->Dump() . '$x; }'
}

sub _path2mod { (my $pm  = shift) =~ s{/}{::}g; return substr $pm, 5, -3 }
sub _mod2dist { (my $mod = shift) =~ s{::}{-}g; return $mod; }

sub _files {
  my ($dir,@f) = shift;
  return unless -d $dir;
  my $regex = $re{$dir} || qr/./;
  find( sub { -f && /$regex/ && push @f, $File::Find::name},$dir);
  return sort { length $a <=> length $b } @f;
}

sub _distbase { my @f = _files('lib'); return _mod2dist(_path2mod($f[0])) }

sub _distdir {
  my @f = _files('lib');
  return catfile(_distbase ."-". MM->parse_version($f[0]), @_);
}

1;

__END__

=head1 NAME

Module::Build::Tiny - A tiny replacement for Module::Build

=head1 SYNOPSIS

 # First, install Module::Build::Tiny

 # Then copy this file into inc

 # Then create this Build.PL
 use lib 'inc';
 use Module::Build::Tiny;
 Build_PL(@ARGV);

 # That's it!

=head1 DESCRIPTION

Many Perl distributions use a Build.PL file instead of a Makefile.PL file
to drive distribution configuration, build, test and installation.
Traditionally, Build.PL uses Module::Build as the underlying build system.
This module provides a simple, lightweight, drop-in replacement.

Whereas Module::Build has over 6,700 lines of code; this module has under
200, yet supports the features needed by most pure-Perl distributions along
with some useful automation for lazy programmers.  Plus, it bundles itself
with the distribution, so end users don't even need to have it (or
Module::Build) installed.

=head2 Supported

  * Pure Perl distributions
  * Recursive test files
  * Automatic 'requires' and 'build_requires' detection (see below)
  * Automatic MANIFEST generation
  * Automatic MANIFEST.SKIP generation (if not supplied)
  * Automatically bundles itself in inc/
  * MYMETA

=head2 Not Supported

  * Dynamic prerequisites
  * Generated code from PL files
  * Building XS or C
  * Manpage or HTML documentation generation
  * Subclassing Module::Build::Tiny
  * Licenses in META.yml other than 'perl'

=head2 Other limitations

  * May only work on a Unix-like or Windows OS
  * This is an experimental module -- use at your own risk

=head2 Directory structure

Your .pm and .pod files must be in F<lib/>.  Any executables must be in
F<bin/>.  Test files must be in F<t/>.  Bundled test modules must be in
F<t/lib/>.

=head2 Automatic prequisite detection

Prerequisites of type 'requires' are automatically detected in *.pm files
in F<lib/> from lines that contain a C<use()> function with a version
number.  E.g.:

  use Carp 0 qw/carp croak/;
  use File::Spec 0.86 ();

Lines may have leading white space.  You may not have more than one
C<use()> function per line.  No other C<use()> or C<require()> functions
are detected.

Prerequisites of type 'build_requires' are automatically detected in a
similar fashion from any *.t files (recusively) in F<t/> and from any
*.pm files in F<t/lib/>.

=head1 USAGE

These all work pretty much like their Module::Build equivalents.  The
only configuration options currently supported are:

=over

=item *

install_base

=item *

uninst

=back

=head2 perl Build.PL

=head2 Build

=head2 Build test

=head2 Build install

=head2 Build clean

=head2 Build realclean

=head2 Build distdir

=head2 Build dist

=head1 CONFIG FILE AND ENVIRONMENT

Options can be provided in a F<.modulebuildrc> file or in the C<PERL_MB_OPT>
environment variable the same way they can with Module::Build.

=head1 SEE ALSO

L<Module::Build>

=head1 AUTHOR

  David Golden <dagolden@cpan.org>
  Leon Timmermans <leont@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by David A. Golden, Leon Timmermans

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
# vi:et:sts=2:sw=2:ts=2
