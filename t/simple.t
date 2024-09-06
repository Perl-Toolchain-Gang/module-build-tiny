#! perl
use strict;
use warnings;
use Config;
use ExtUtils::CBuilder;
use File::Spec::Functions 0 qw/catdir catfile/;
use IPC::Open2;
use Test::More 0.88;
use lib 't/lib';
use DistGen qw/undent/;
use XSLoader;

local $ENV{PERL_INSTALL_QUIET};
local $ENV{PERL_MB_OPT};

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $dist = DistGen->new(name => 'Foo::Bar');
$dist->chdir_in;
$dist->add_file('share/file.txt', 'FooBarBaz');
$dist->add_file('module-share/Foo-Bar/file.txt', 'BazBarFoo');
$dist->add_file('script/simple', undent(<<'    ---'));
    #!perl
    use Foo::Bar;
    print Foo::Bar->VERSION . "\n";
    ---
my $has_compiler = ExtUtils::CBuilder->new->have_compiler();

if ($has_compiler) {
	$dist->add_file('lib/Foo/Bar.xs', undent(<<'		---'));
		#define PERL_NO_GET_CONTEXT
		#include "EXTERN.h"
		#include "perl.h"
		#include "XSUB.h"
		#include "foo.h"

		MODULE = Foo::Bar                PACKAGE = Foo::Bar

		const char*
		foo()
			CODE:
			RETVAL = foo();
			OUTPUT:
			RETVAL
		---
	$dist->add_file('include/foo.h', undent(<<'		---'));
		char* foo();
		---
	$dist->add_file('src/foo.c', undent(<<'		---'));
		char* foo() {
			return "Hello World!\n";
		}
		---
}

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
  is(system($^X, 'Build.PL', '--install_base=install'), 0, 'Ran Build.PL');
  ok( -f 'Build', "Build created" );
  if ($^O eq 'MSWin32') {
    ok( -f 'Build.bat', 'Build is executable');
  }
  else {
    ok( -x 'Build', "Build is executable" );
  }

  open my $fh, "<", "Build";
  my $line = <$fh>;

  like( $line, qr{\A$interpreter}, "Build has shebang line with \$^X" );
  ok( -f '_build_params', "_build_params created" );
}

#--------------------------------------------------------------------------#
# build
#--------------------------------------------------------------------------#

{
  ok( open2(my($in, $out), $^X, 'Build'), 'Could run Build' );
  my $output = do { local $/; <$in> };
  like( $output, qr{lib/Foo/Bar\.pm}, 'Build output looks correctly');
  ok( -d 'blib',        "created blib" );
  ok( -d 'blib/lib',    "created blib/lib" );
  ok( -d 'blib/script', "created blib/script" );

  # check pm
  my $pmfile = _mod2pm($dist->name);
  ok( -f 'blib/lib/' . $pmfile, "$dist->{name} copied to blib" );
  is( _slurp("lib/$pmfile"), _slurp("blib/lib/$pmfile"), "pm contents are correct" );
  is((stat "blib/lib/$pmfile")[2] & 0222, 0, "pm file in blib is readonly" );

  # check bin
  ok( -f 'blib/script/simple', "bin/simple copied to blib" );
  like( _slurp("blib/script/simple"), '/' .quotemeta(_slurp("blib/script/simple")) . "/", "blib/script/simple contents are correct" );
  if ($^O eq 'MSWin32') {
    ok( -f "blib/script/simple.bat", "blib/script/simple is executable");
  }
  else {
    ok( -x "blib/script/simple", "blib/script/simple is executable" );
  }
  is((stat "blib/script/simple")[2] & 0222, 0, "script in blib is readonly" );
  if ($^O ne 'MSWin32') {
    open my $fh, "<", "blib/script/simple";
    my $line = <$fh>;
    like( $line, qr{\A$interpreter}, "blib/script/simple has shebang line with \$^X" );
  }

  require blib;
  blib->import;
  if (eval { require File::ShareDir }) {
    ok( -d File::ShareDir::dist_dir('Foo-Bar'), 'sharedir has been made');
    ok( -f File::ShareDir::dist_file('Foo-Bar', 'file.txt'), 'sharedir file has been made');
    require Foo::Bar;
    ok( -d File::ShareDir::module_dir('Foo::Bar'), 'sharedir has been made');
    ok( -f File::ShareDir::module_file('Foo::Bar', 'file.txt'), 'sharedir file has been made');
  }
  ok( -d catdir(qw/blib lib auto share dist Foo-Bar/), 'dist sharedir has been made');
  ok( -f catfile(qw/blib lib auto share dist Foo-Bar file.txt/), 'dist sharedir file has been made');
  ok( -d catdir(qw/blib lib auto share module Foo-Bar/), 'moduole sharedir has been made');
  ok( -f catfile(qw/blib lib auto share module Foo-Bar file.txt/), 'module sharedir file has been made');

  SKIP: {
    skip 'No CPAN::Requirements::Dynamic', 1 unless eval { require CPAN::Requirements::Dynamic };
    require CPAN::Meta;
    my $meta = CPAN::Meta->load_file("MYMETA.json");
    my $req = $meta->effective_prereqs->requirements_for('runtime', 'requires');
    my $dynamic_dependency = join ',', sort $req->required_modules;

    is($dynamic_dependency, 'Bar,perl', 'Dependency on Foo has been inserted');
  }


  if ($has_compiler) {
    XSLoader::load('Foo::Bar');
    is(Foo::Bar::foo(), "Hello World!\n", 'Can run XSub Foo::Bar::foo');
  }

  SKIP: {
    require ExtUtils::InstallPaths;
    skip 'No manification supported', 1 if not ExtUtils::InstallPaths->new->is_default_installable('libdoc');
    require ExtUtils::Helpers;
    my $file = "blib/libdoc/" . ExtUtils::Helpers::man3_pagename($pmfile, '.');
    ok( -e $file, 'Module gets manified properly');
  }
}

{
  ok( open2(my($in, $out), $^X, Build => 'install'), 'Could run Build install' );
  my $output = do { local $/; <$in> };
  my $filename = catfile(qw/install lib perl5/, ($has_compiler? $Config{archname} : () ), qw/Foo Bar.pm/);
  like($output, qr/Installing \Q$filename/, 'Build install output looks correctly');

  ok( -f $filename, 'Module is installed');
  ok( -f 'install/bin/simple', 'Script is installed');
}

done_testing;
