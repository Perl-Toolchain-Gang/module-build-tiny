package Acme::Module::Build::Tiny;
use strict;
use warnings;
use Config;
use Data::Dumper 0 ();
use ExtUtils::Install 0 ();
use ExtUtils::MakeMaker 0 ();
use File::Find 0 ();
use File::Path 0 ();
use File::Spec 0 ();
use Getopt::Long 0 ();
use Test::Harness 0 ();
use Tie::File 0 ();
use Text::ParseWords 0 ();
our $VERSION = '0.04';

my %re = (
  lib     => qr{\.(?:pm|pod)$},
  t       => qr{\.t},
  't/lib' => qr{\.(?:pm|pod)$},
  prereq  => qr{^\s*use[ \t]+(\S+)[ \t]+(v?[0-9._]+)[^;]*;}m,
  authors => qr{^=head1 AUTHORS?\s*\n(.*?)^=\w}sm,
);

my %install_map = map { +"blib/$_"  => $Config{"installsite$_"} } qw/lib script/;

my %install_base = ( lib => [qw/lib perl5/], script => [qw/lib bin/] );

my @opts_spec = ( 'install_base:s', 'uninst:i' );

sub _split_like_shell {
  my $string = shift;
  $string =~ s/^\s+|\s+$//g;
  return Text::ParseWords::shellwords($string);
}

sub _home { return $ENV{HOME} || $ENV{USERPROFILE} }

sub _default_rc { return File::Spec->catfile( _home(), '.modulebuildrc' ) }

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
  Getopt::Long::GetOptions($opt, @opts_spec);
}

sub run {
  my $opt = eval { do '_build/build_params' } || {};
  my $action = $ARGV[0] =~ /\A\w+\z/ ? $ARGV[0] : 'build';
  _get_options($action, $opt);
  __PACKAGE__->can($action)->(%$opt) or exit 1;
}

sub debug {
  my %opt = @_;
  print _data_dump(\%opt) . "\n";
}

sub import {
  _get_options('Build_PL', my $opt = {});
  my @f = _files('lib');
  my $meta = {
    name     => _mod2dist(_path2mod($f[0])),
    version  => MM->parse_version($f[0]),
  };
  print "Creating new 'Build' script for '$meta->{name}'" .
        " version '$meta->{version}'\n";
  _spew('Build' => "#!$^X\n", _slurp( $INC{_mod2pm(shift)} ) );
  chmod 0755, 'Build';
  _spew( '_build/prereqs', _data_dump(_find_prereqs()) );
  _spew( '_build/build_params', _data_dump($opt) );
  _spew( '_build/meta', _data_dump(_fill_meta($meta, $f[0])) );
  _spew( 'MYMETA.yml', _slurp('META.yml')) if -f 'META.yml';
}

sub build {
  my $map = {
    (map {$_=>"blib/$_"} _files('lib')),
    (map {;"bin/$_"=>"blib/script/$_"} map {s{^bin/}{}; $_} _files('bin')),
  };
  ExtUtils::Install::pm_to_blib($map, 'blib/lib/auto');
  ExtUtils::MM->fixin($_), chmod(0555, $_) for _files('blib/script');
  return 1;
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
  local $ExtUtils::Manifest::Quiet = 1;
  ExtUtils::Manifest::mkmanifest();
  ExtUtils::Manifest::manicopy( ExtUtils::Manifest::maniread(), _distdir() );
  _spew(_distdir("/inc/",_mod2pm(__PACKAGE__)) => _slurp( __FILE__ ) );
  _append(_distdir("MANIFEST"), "inc/" . _mod2pm(__PACKAGE__) . "\n");
  _write_meta(_distdir("META.yml")); 
  _append(_distdir("MANIFEST"), "META.yml");
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

sub realclean { clean(); File::Path::rmtree($_) for _distdir(), qw/Build _build/; 1; }

sub _slurp { do { local (@ARGV,$/)=$_[0]; <> } }
sub _spew {
  my $file = shift;
  File::Path::mkpath(File::Basename::dirname($file));
  open my $fh, '>', $file;
  print {$fh} @_;
}
sub _append { open my $fh, ">>", shift; print {$fh} @_ }

sub _data_dump {
  'do{ my ' . Data::Dumper->new([shift],['x'])->Purity(1)->Dump() . '$x; }'
}

sub _mod2pm   { (my $mod = shift) =~ s{::}{/}g; return "$mod.pm" }
sub _path2mod { (my $pm  = shift) =~ s{/}{::}g; return substr $pm, 5, -3 }
sub _mod2dist { (my $mod = shift) =~ s{::}{-}g; return $mod; }

sub _files {
  my ($dir,@f) = shift;
  return unless -d $dir;
  my $regex = $re{$dir} || qr/./;
  File::Find::find( sub { -f && /$regex/ && push @f, $File::Find::name},$dir);
  return sort { length $a <=> length $b } @f;
}

sub _distbase { my @f = _files('lib'); return _mod2dist(_path2mod($f[0])) }

sub _distdir {
  my @f = _files('lib');
  return File::Spec->catfile(_distbase ."-". MM->parse_version($f[0]), @_);
}

sub _fill_meta {
  my ($m, $src) = @_;
  for ( split /\n/, _slurp($src) ) {
    next unless /^=(?!cut)/ .. /^=cut/;  # in POD
    ($m->{abstract}) = /^  (?:  [a-z:]+  \s+ - \s+  )  (.*\S)  /ix
      unless $m->{abstract};
  }
  $m->{author} = _find_authors($src);
  return $m;
}

sub _find_authors {
  my $guts = _slurp($_[0]);
  my ($block) = $guts =~ $re{authors};
  return $block ? [ map { s{^\s+}{}; s{\s+$}{}; $_ } grep { /\S/ } split /\n/, $block ] : [];
}

sub _write_meta {
  my $file = shift; 
  my $meta = eval { do '_build/meta' } || {};
  my $prereqs = eval { do '_build/prereqs' } || {};
  $meta->{$_} = $prereqs->{$_} for keys %$prereqs;
  $meta->{generated_by} = sprintf("%s version %s", __PACKAGE__, $VERSION);
  $meta->{'meta-spec'} = { version => 1.4, url => 'http://module-build.sourceforge.net/META-spec-v1.4.html' };
  $meta->{'license'} = 'perl';
  require Module::Build::YAML;
  Module::Build::YAML::DumpFile($file,$meta);
}

sub _find_prereqs {
  my (%requires, %build_requires);
  for my $guts ( map { _slurp($_) } _files('lib'), _files('bin') ) {
    while ( $guts =~ m{$re{prereq}}g ) { $requires{$1}=$2; }
  }
  for my $guts ( map { _slurp($_) } _files('t'), _files('t/lib') ) {
    while ( $guts =~ m{$re{prereq}}g ) { $build_requires{$1}=$2; }
  }
  return { requires => \%requires, build_requires => \%build_requires };
}

run() unless caller; # modulino :-)

1;

__END__

=head1 NAME

Acme::Module::Build::Tiny - A tiny replacement for Module::Build

=head1 SYNOPSIS

  # First, install Acme::Module::Build::Tiny

  # From the command line, run this:
  $ btiny

  # Which generates this Build.PL:
  use lib 'inc'; use Acme::Module::Build::Tiny;

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
  * Subclassing Acme::Module::Build::Tiny
  * Licenses in META.yml other than 'perl'

=head2 Other limitations

  * May only work on a Unix-like or Windows OS
  * This is an Acme module -- use at your own risk

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

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by David A. Golden

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
# vi:et:sts=2:sw=2:ts=2
