use ExtUtils::MakeMaker;

#
# $Id$
#

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Net::Printer',
    'VERSION_FROM'	=> 'lib/Net/Printer.pm', # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
    ($] >= 5.006 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/Net/Printer.pm', # retrieve abstract from module
       AUTHOR     => 'Chris Fuhrman <chris.fuhrman@tfcci.com>') : ()),
);
