#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Giddy' ) || print "Bail out!
";
}

diag( "Testing Giddy $Giddy::VERSION, Perl $], $^X" );
