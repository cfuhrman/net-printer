########################################################################
#
# Printer.pm
#
# Christopher M. Fuhrman <cfuhrman@tfcci.com>
#
# $Id: Printer.pm,v 1.3 2000/06/07 21:23:42 cfuhrman Exp $
#
# Usage:
#
#   use Net::Printer
#
# Compiler:
#
#   perl 5.005_03
#
# System:
#
#   AMD K6-300 running Redhat Linux 6.1 (kernel 2.2.12-20)
#   SunOS app1 5.7 Generic_106542-02 i86pc i386 i86pc
#
# Description:
#
#   Perl module which acts as an interface to the lpd/lpsched process
#   without having to build a pipe to lpr or lp.  The goal of this
#   module is to provide a robust way of printing to a line printer
#   and provide immediate feedback as to if it were printed or not.
#
# Copyright (C) 2000 Christopher M. Fuhrman
#
#   This library is free software; you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as
#   published by the Free Software Foundation; either version 2 of the
#   License, or (at your option) any later version.
#
#   This library is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public
#   License along with this library; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
#   USA
#
#   Twenty First Century Communications, Inc., hereby disclaims all
#   copyright interest in the module `Net::Printer' (a module for
#   directly printing to a printer) written by Christopher M. Fuhrman.
#
#   Jim Kennedy, 2 February 2000
#   President of Twenty First Century Communications, Inc.
#
# The Author can be contacted at:
#
#   Twenty First Century Communications, Inc.
#   760 Northlawn Drive
#   Suite 200
#   Columbus, OH 43214
#   Attn: Chris Fuhrman
#
#   (614) 442-1215 x271
#
#   cfuhrman@tfcci.com
#
########################################################################
package Net::Printer;

use strict "vars";
use strict "refs";
use Socket;
use FileHandle;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
require AutoLoader;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(printfile printstring queuestatus);
@EXPORT_OK = qw(%params);

# Global Variable(s)
$VERSION         = '0.20';

my ($SEQNO_FILE) = '/tmp/seqno'; 

my ($dfile,
    $cfile,
    $controlfile);

# Preloaded methods go here.

#-----------------------------------------------------------------------

sub new {

    # Local Variable(s)
    my $type   = shift;
    my %params = @_;
    my $self   = {};

    # Parameters
    if (exists $params{filename}) {
	$self->{filename} = $params{filename};
    } # if exists $params{filename}

    if (exists $params{lineconvert}) {
	$self->{lineconvert} = $params{lineconvert};
    } # if exists $params{lineconvert}
    else {
	$self->{lineconvert} = "NO";
    } # else (if exists $params{lineconvert}

    if (exists $params{printer}) {
	$self->{printer} = $params{printer};
    } # if exists $params{printer}
    else {
	$self->{printer} = "lp";
    } # else (if exists $params{printer}
    
    if (exists $params{server}) {
	$self->{server} = $params{server};
    } # if exists $params{server}
    else {
	$self->{server} = "localhost";
    } # else (if exists $params{server}

    if (exists $params{port}) {
	$self->{port} = $params{port};
    } # if exists $params{port}
    else {
	$self->{port} = 515;
    } # else (if exists $params{port}

    if (exists $params{debug}) {
	$self->{debug} = $params{debug};
    } # if exists $params{debugs}
    else {
	$self->{debug} = "NO";
    } # else (if exists $params{debug}

    return bless $self, $type;

} # new

#-----------------------------------------------------------------------
#
# printfile
#
# Description:
#
#   Connects to a specified remote lpd/lpsched process and transmits a
#   print job.
#
# Parameters:
#
#   none.
#
# Called By:
#
#   Exported.
#
# Calls:
#
#   CopyFile
#   CreateControlFile
#   OpenSocket
#
# Pre:
#
# Post:
#

sub printfile {

    # Local Variable(s)
    my ($hostname,
	$junk,
	$result,
	$reason,
	$buf,
	$i);

    my ($socket)    = new FileHandle();

    my ($self)      = shift;
    
    my ($filename)  = $self->{filename};
    my ($printer)   = $self->{printer};
    my ($server)    = $self->{server};
    my ($port)      = $self->{port};

    # Create Control File
    $controlfile = "/tmp/lineprinter-control-file-$$.txt";

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Creating Control file $controlfile\n";
    } # if uc($self->debug eq "YES"

    # Get Hostname
    chop ($hostname = `hostname`);
    ($hostname, $junk) = split(/\./, $hostname);

    $reason = CreateControlFile($hostname,
				$self->{filename},
				$self);

    if ($reason ne "") {
	return "Printer: Error: $reason\n";
    } # if $reason ne ""

    # Convert Newlines to LF/CR if required
    if (uc($self->{lineconvert}) eq "YES") {
	$filename = NLconvert($filename);
    } # if uc $self->{lineconvert} eq "YES"
    elsif (uc($self->{lineconvert}) ne "NO") {
	return "Printer: Error: Set lineconvert to \"Yes\" or \"No\"\n";
    } # elsif uc $self->{lineconvert} ne "NO"

    # Convert the Control File as well
    # $controlfile = NLconvert($controlfile);

    # Open the socket
    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Connecting to remote host\n";
    } # if uc($self->debug eq "YES"
 
    $reason = OpenSocket($socket,
			 $self);

    if ($reason ne "") {
	return $reason;
    } # if $reason ne ""

    # Autoflush SOCK
    select ($socket);
    $| = 1;
    select (STDOUT);
    
    # Get some info about entered file.
    unless (defined $filename) {
	return "Printer: Error: What file do I print?\n";
    }

    # Send a line to the print server telling it we want to send it
    # some files to print, and specifying the printer to be used.
    $buf = sprintf("%c%s\n",
		   2,
		   $printer);

    $i = length($buf);

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Initializing connection to printer\n";
    } # if uc($self->debug eq "YES"

    if ((syswrite $socket, $buf, $i) != $i) {
	return "Printer: Error: Lost Connection\n";
    } # if syswrite $socket, $buf, $i

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Server, please acknowledge\n";
    } # if uc($self->debug eq "YES"

    # Get ACK from server
    if (($buf = sysread $socket, $result, 1) != 1) {
	return "Printer: Error: Server didn't acknowledge on initial connect.  Returned $result ($buf)\n";
    } # if $buf = sysread $socket, $result, 1 != 1

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Server Acknowledged.  We're kosher\n";
    	print STDOUT "DEBUG: Sleeping 15 seconds.  Do a netstat here to see if we're connected\n";
	sleep 15;	
    } # if uc($self->debug eq "YES"
    
    # Copy the Data File
    $reason = CopyFile($self,
		       $socket,
		       3,
		       $dfile,
		       $filename);

    if ($reason ne "") {
	return "Printer: Error: $reason\n";
    } # if $reason ne ""
    
    # Copy the Control File
    $reason = CopyFile($self,
		       $socket,
		       2,
		       $cfile,
		       $controlfile);

    if ($reason ne "") {
	return "Printer: Error: $reason\n";
    } # if $reason ne ""

    # Clean up

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: We're done.  Cleaning up\n";
    } # if uc($self->debug eq "YES"

    close $socket;
    unlink $controlfile;
    if (uc($self->{lineconvert}) eq "YES") {
	unlink $filename;
    } # if uc $self->{lineconvert} eq "YES"
    
    return 1;

} # printfile

#-----------------------------------------------------------------------
#
# printstring
#
# Description:
#
#   Prints a specified string to a printer using printfile.
#
# Parameters:
#
#   printtext - text to print
#
# Called By:
#
#   Exported.
#
# Calls:
#
#   printfile
#
# Pre:
#
# Post:
#

sub printstring {

    # Local Variable(s)
    my ($printfile,
	$reason);

    # Parameter(s)
    my ($self)        = shift;
    my ($printstring) = @_;

    $printfile = "/tmp/printstring-$$.txt";

    # Generate Printfile
    open (STRINGFILE, "> $printfile") ||
	return "Printer: Error: Could not open temp file: $!\n";

    print STRINGFILE $printstring;

    close STRINGFILE;

    # Print it
    $self->{filename} = $printfile;

    $reason = $self->printfile();

    # Clean up
    unlink $printfile;

    if ($reason != 1) {
	return $reason;
    } # if $reason != 1
    else {
	return 1;
    } # else (if $reason != 1)
    
} # printstring

#-----------------------------------------------------------------------
# 
# queuestatus
#
# Purpose:
#
#   Retrieves status information from a specified printer returning
#   the output in an array.  
#
# Parameters:
#
#   None.
#
# Called By:
#
#   Exported
#   
# Calls:
#    
#   OpenSocket
#
# Pre:
#
# Post:
#
 
sub queuestatus {

    # Local Variable(s);
    my ($reason,
	$buf,
	$i,
	$line,
	$result,
	@result);

    my ($self)   = shift;

    my ($socket)  = new FileHandle;
    my ($printer) = $self->{printer};

    # Open a new socket
    $reason = OpenSocket($socket,
			 $self);

    if ($reason ne "") {
	return "Error: Could not connect: $reason\n";
    } # if $reason ne ""
    
    $buf = sprintf("%c%s\n",
		    4,
		    $printer);

    $i = length($buf);
    if (($result = (syswrite $socket, $buf, $i, 0)) != $i) {
	return "Printer: Error: Lost connection.  Result = $result\n";
    } # if syswrite $socket, $myline, $i != $i
    
    # Read the response from the server and format.
    while (<$socket>) {
	s/($_)/$printer\@$self->{server}: $1/;
	push (@result, $_);
    } # <$socket>

    # Clean Up
    close $socket;
    return @result;

} # queuestatus

#-----------------------------------------------------------------------
#
# OpenSocket
#
# Purpose:
#
#   Establishes a socket connection with a remote port.
#
# Parameters:
#
#   sh - pointer to FileHandle of Socket.
#
# Called By:
#
#   printfile
#   queuestatus
#
# Calls:
#
# Pre:
#
# Post:
#
#   Will connect socket sh.
#

sub OpenSocket {

    # Local Variable(s)
    my ($hostname,
	$junk,
	$name,
	$aliases,
	$proto,
	$type,
	$len,
	$thisaddr,
	$thataddr,
	$sockaddr,
	$this,
	$that);

    # Parameter(s)
    my ($sh, $self) = @_;

    my ($server)    = $self->{server};
    my ($port)      = $self->{port};

    # Get Hostname
    chop ($hostname = `hostname`);
    ($hostname, $junk) = split(/\./, $hostname);

    # Grab the network protocol info
    ($name, $aliases, $proto) = getprotobyname('tcp');

    # Get the port number if it isn't an integer
    ($name, $aliases, $port) = getservbyname($port, 
					     'tcp')
	unless $port =~ /^\d+$/;
    
    # Look up numeric IP address info for current machine
    ($name, $aliases, $type, $len, $thisaddr) =
	gethostbyname($hostname);

    # Look up numeric IP address info for remote machine
    ($name, $aliases, $type, $len, $thataddr) = 
	gethostbyname($server);

    # Create the socket
    socket($sh, AF_INET, SOCK_STREAM, $proto) or 
	return "Printer: Error: Cannot create socket on $server with $proto: $!\n";
    
    # Bind it and connect it.
    $sockaddr = 'S n a4 x8';
    $this     = pack($sockaddr,
		     AF_INET,
		     0,
		     $thisaddr);
    $that     = pack($sockaddr,
		     AF_INET,
		     $port,
		     $thataddr);

    if (!(bind($sh, $this))) {
	return "Printer: Error: Cannot bind socket: $!\n";
    } # if !bind($sh, $this)

    if (!(connect($sh, $that))) {
	return "Printer: Error: Couldn't connect socket:  $!\n";
    } # if !connect($sh, $that)
    
    return "";

} # OpenSocket


#-----------------------------------------------------------------------
#
# CopyFile
#
# Purpose:
#
#   Transmit one file to the server returning a reason on error.
#
# Parameters:
#
#   sh        - Pointer to FileHandle of Socket.
#   xmit_type - Type of file to send.  Either '\002' or '\003'
#   printfile - our fake printer spool file
#   realfile  - Path to real file
#
# Called By:
#
#   printfile
#   
# Calls:
#
# Pre:
#
# Post:
#

sub CopyFile {

    # Local Variable(s)
    my ($size,
	$blksize,
	$buf,
	$offset,
	$result,
	$i,
	$len);

    # Parameter(s)
    my ($self, $sh, $xmit_type, $printfile, $realfile) = @_;

    ($size) = (stat $realfile) [7];

    # Send a line to the print server giving the type of file, the
    # exact size of the file in bytes, and the name of the file 
    $buf = sprintf("%c%ld %s\n",
		   $xmit_type,
		   $size,
		   $printfile);

    $len = length($buf);

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Sending server $printfile of size $size\n";
    } # if uc($self->debug eq "YES"

    if ((syswrite $sh, $buf, $len, 0) != $len) {
	return "Printer: Error: Lost Connection.\n";
    } # if $result = syswrite $sh, $buf, $len, 0 ...
  
    $len = sysread $sh, $result, 1;
    $result = sprintf("%d", $result);

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Got back :$result:\n";
    } # if uc($self->debug eq "YES"

    if (($len != 1) || ($result != 0)) {
	return "Server returned length $len with result :$result:\n";
    } # if (($len != 1) || ($result != 0))

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Server has sufficient space.  Sending actual file\n";
    } # if uc($self->debug eq "YES"


    # Send the actual file itself
    open (DATAFILE, "$realfile") ||
	return "Could not open $realfile for reading: $!\n";
    
    $blksize = (stat DATAFILE)[11] || 16384;
    while ($len = sysread DATAFILE, $buf, $blksize) {
	if (!defined $len) {
	    next if $! =~ /^Interrupted/;
	    return "System read error: $!\n";
	} # if !defined $len
	$offset = 0;

	if (uc($self->{debug}) eq "YES") {
	    print STDOUT "DEBUG: Sending $buf\n";
	} # if uc($self->debug eq "YES"
	
	while ($len) {
	    
	    undef $result;
	    $result = syswrite $sh, $buf, $len, $offset;
	    return "System write error: $!\n"
		unless defined $result;
	    $len -= $result;
	    $offset += $result;
	    
	} # while ($len)

    } # while $len = sysread DATAFILE, $buf, $blksize

    close DATAFILE;

    # Write a byte of zero to the server, and wait for a byte of sero
    # to be returned from the server, telling us all is Ok (I'm OK,
    # you're OK).
    $buf = sprintf("%c",
		   0);
    
    $i = length($buf);

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: I'm okay.  Server, are you okay?\n";
    } # if uc($self->debug eq "YES"

    if ((syswrite $sh, $buf, $i) != $i) {
	return "Printer: Error: Lost Connection\n";
    } # if syswrite $sh, $buf, $i != $i

    undef $result;
    sysread $sh, $result, 1;
    $result = sprintf("%d", $result);

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Got back :$result:\n";
    } # if uc($self->debug eq "YES"

    if ($result != 0) {
	return "Printer: Error: Didn't get an ACK from server\n";
    } # if <$sh> != 0

    if (uc($self->{debug}) eq "YES") {
	print STDOUT "DEBUG: Server just told me it's okay.  Kewl...\n";
	print STDOUT "DEBUG: Sleep for 10 secs.  Do a netstat\n";
	sleep 10;
    } # if uc($self->debug eq "YES"

    return "";

} # Copyfile

#-----------------------------------------------------------------------
#
# CreateControlFile
#
# Purpose:
#
#   Creates a control file to send to the remote lineprinter process.
#   If there is an error, it will return the reason for the error.
#
# Parameters:
#
#   Hostname       - The hostname of the machine we're running on.
#   print_filename - The actual printer file name
#
# Called By:
#
#   printfile
#
# Calls:
#
# Pre:
#
# Post:
#  
#   Will set cfile and dfile globals
#

sub CreateControlFile {

    # Local Variable(s)
    my (%control_hash,
	$junk,
	$key,
	$output);

    # Parameters
    my ($hostname, $print_filename, $self) = @_;

    my ($sequence_no) = Get_SeqNo($self);
    
    # Generate Hash
    $control_hash{'1H'} = $hostname;
    $control_hash{'2P'} = getpwent();
    $control_hash{'3J'} = $print_filename;
    $control_hash{'4C'} = $hostname;
    $control_hash{'5f'} = sprintf("dfA%03d%s",
				 $sequence_no,
				 $control_hash{'1H'});
    $control_hash{'6U'} = sprintf("cfA%03d%s",
				 $sequence_no,
				 $control_hash{'1H'});
    $control_hash{'7N'} = $print_filename;

    $dfile = $control_hash{'5f'};
    $cfile = $control_hash{'6U'};

    # Open control File for printing
    open (CONTROLFILE, ">$controlfile") ||
	return "Could not create control file: $!\n";
    
    foreach $_ (sort keys %control_hash) {
	$key = $_;
	s/(.)(.)/$2/g;
	$output = sprintf("%s%s\n",
			  $_,
			  $control_hash{$key});

	print CONTROLFILE $output;
    } # foreach $key (sort keys %control_hash)

    close CONTROLFILE;
    
    return "";

} # CreateControlFile

#-----------------------------------------------------------------------
#
# NLconvert
#
# Description:
#
#   Iterates through a specified file and converts \n to \n\r.  Will
#   return the location of the new file.
#
# Parameters:
#
#   file - Name of file to process
#
# Called By:
#
#   printfile
#
# Calls:
#
# Pre:
#
# Post:
#  
#   Will set cfile and dfile globals
#

sub NLconvert {

    # Local Variables
    my ($newfile) = "/tmp/printerfile-$$.txt";

    # Parameter(s)
    my ($oldfile) = @_;

    # Open files for reading and writing.
    open (OLDFILE, "$oldfile") ||
        croak "Cannot open file ($oldfile): $!\n";
    
    open (NEWFILE, "> $newfile") ||
	croak "Cannot open file ($newfile): $!\n";

    while (<OLDFILE>) {

	s/\n/\n\r/;
	print NEWFILE $_;

    } # while <OLDFILE>

    # Clean Up
    close OLDFILE;
    close NEWFILE;

    return $newfile;

} # NLconvert

#-----------------------------------------------------------------------
#
# Get_SeqNo
#
# Description:
#
#   Opens up a file containing a sequence number and returns the
#   current number, while updating it for the next user.  If the file
#   doesn't exist, the file is created and the sequence number set to
#   2.  Function will return the current sequence number.
#
# Parameters:
#
#   None.
#
# Called By:
#
#
# Calls:
#
# Pre:
#
# Post:
#  

sub Get_SeqNo {

    # Local Variable(s)
    my ($seqno,
	$fsize);

    # Parameter(s)
    my ($self) = @_;

    # Does the sequence file exist?
    if (-e $SEQNO_FILE and ($fsize) = stat(_) and $fsize > 0) {

	if (uc($self->{debug} eq "YES")) {
	    print "DEBUG: Opening existing stat file for reading\n";
	} # if uc($self->{debug} eq "YES)"

	# Get Current Sequence number
	open (SEQ_FILE, "$SEQNO_FILE") or
	    croak "Printer: Error: Cannot open sequence file: $!\n";
	$seqno = <SEQ_FILE>;
	close SEQ_FILE;

    } # if -e $SEQNO_FILE
    else {
	
	if (uc($self->{debug} eq "YES")) {
	    print "DEBUG: No Sequence File found.  Initializing\n";
	} # if uc($self->{debug} eq "YES")

	$seqno = 1;

    } # else (if (-e $SEQ_FILE))
    
    if (uc($self->{debug} eq "YES")) {
	print "DEBUG: Sequence is $seqno\n";
    } # if uc($self->{debug} eq "YES")

    # Now open the SEQ_FILE for writing to echo new sequence number.
    open (WRITE_FILE, "> $SEQNO_FILE") or
	croak "LinePrinter: Error: Cannot open sequence file for writing: $!\n";

    $seqno++;
    print WRITE_FILE "$seqno\n";

    close WRITE_FILE;

    chmod 0666, $SEQNO_FILE;

    return $seqno - 1;

} # Get_SeqNo

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Net::Printer - Perl extension for direct-to-lpd printing.

=head1 SYNOPSIS

  use Net::Printer;

  # Create new Printer Object
  $lineprinter = new Net::Printer(
				  filename    => "/home/jdoe/myfile.txt",
				  printer     => "lp",
				  server      => "printserver",
				  port        => 515,
				  lineconvert => "YES"
				  );
  # Print the file
  $result = $lineprinter->printfile();

  # Print a string
  $result = 
    $lineprinter->printstring("Smoke me a kipper, I'll be back for breakfast.");

  # Get Queue Status
  $result = $lineprinter->queuestatus();

=head1 DESCRIPTION

    Perl module for directly printing to a print server/printer without
    having to create a pipe to either lpr or lp.  This essentially
    mimics what the BSD LPR program does by connecting directly to the
    line printer printer port (almost always 515), and transmitting
    the data and control information to the print server.

    Please note that this module only talks to print servers that
    speak BSD.  It will not talk to printers using SMB or SysV unless
    they are set up as BSD printers.

=head2 Parameters

    filename    - [optional] absolute path to the file you wish to print.

    printer     - [optional] Name of the printer you wish to print to.  
                  Default "lp".
 
    server      - [optional] Name of the server that is running
                  lpd/lpsched.  Default "localhost".

    port        - [optional] The port you wish to connect to.  
                  Default "515".
 
    lineconvert - [optional] Perform LF -> LF/CR translation.
                  Default "NO"

=head2 Functions

    I<printfile> prints a specified file to the printer.  Returns a 1 on
    success, otherwise returns a string containing the error.

    I<printstring> prints a specified string to the printer as if it
    were a complete file  Returns a 1 on success, otherwise returns a
    string containing the error. 

    I<queuestatus> returns the current status of the print queue.  I
    recommend waiting a short period of time between printing and
    issueing a queuestatus to give your spooler a chance to do it's
    thing.  5 seconds tends to work for me.

=head1 NOTES

    When printing text, if you have the infamous "stair-stepping"
    problem, try setting lineconvert to "YES".  This should, in most
    cases, rectify the problem.

    Running with the -w option will cause the interpreter to complain
    about a couple of sprintf statements.  These can be safely ignored.

=head1 AUTHOR

C. M. Fuhrman, cfuhrman@tfcci.com

=head1 SEE ALSO

Socket, lpr(1), lp(1), perl(1).

=cut

