use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
#
# $Id: Makefile.PL,v 1.1 2000/06/06 21:12:08 cfuhrman Exp $
#
WriteMakefile(
    'NAME'	=> 'Net::Printer',
    'VERSION_FROM' => 'Printer.pm', # finds $VERSION
);
