#!/usr/bin/perl -w
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#
# $Id: test.pl,v 1.1 2003/02/10 01:56:21 cfuhrman Exp $
#

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 1 };
use Printer;
ok(1); # If we made it this far, we're ok.

#########################

# Insert your test code below, the Test module is use()ed here so read
# its man page ( perldoc Test ) for help writing this test script.

main : {

    $printer = Net::Printer->new( "filename"    => "./testprint.txt",
				  "lineconvert" => "Yes",
				  "server"      => "localhost",
				  "printer"     => "lp",
				  "debug"       => "No");

    ok( defined ($printer) );

    ok (defined $printer->printfile() );

    print "Please check your default printer\n";

} # main
