########################################################################
#
# Net::Printer
#
# $Id: Printer.pm,v 1.6 2003/02/10 18:24:33 cfuhrman Exp $
#
# Chris Fuhrman <chris.fuhrman@tfcci.com>
#
# Description:
#
#   Perl module which acts as an interface to an lpd/lpsched process
#   without having to build a pipe to lpr or lp.  The goal of this
#   module is to provide a robust way of printing to a line printer
#   and provide immediate feedback as to if it were successfully
#   spooled or not. 
# 
# Please see the COPYRIGHT file for important information on
# distribution terms  
#
########################################################################

package Net::Printer;

use 5.005;
use strict;
use warnings;
use Carp;
use FileHandle;
use IO::Socket;
use POSIX qw (tmpnam);
use Sys::Hostname;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Net::Printer ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw( printfile );
our $VERSION = '0.30';

# Functions internal to Net::Printer

#-----------------------------------------------------------------------
#
# log_debug
#
# Purpose:
#
#   Displays informative messages ... meant for debugging.
#
# Parameter(s):
#
#   msg    - message to display
#
#   self   - self object
#

sub log_debug {

    # Parameter(s)
    my ($msg, $self) = @_;

    $msg =~ s/\n//;
    printf("DEBUG: %s\n",
	   $msg)
	if (uc($self->{debug}) eq "YES");

} # log_debug

# Preloaded methods go here.

#----------------------------------------------------------------------
#
# get_tmpfile
#
# Purpose:
#
#   Creates temporary file returning it's name.
#
# Parameter(s):
#
#   none
#

sub get_tmpfile {

    # Local Variable(s)
    my ($name, $fh);

    # try new temporary filenames until we get one that didn't already
    # exist 
    do { $name = tmpnam() } until $fh = IO::File->new($name,
						      O_RDWR|O_CREAT|O_EXCL); 

    $fh->close();
    
    return $name;

} # get_tmpfile

#----------------------------------------------------------------------
#
# nl_convert
#
# Purpose:
#
#   Given a filename, will convert newline's (\n) to
#   newline-carriage-return (\n\r), output to new file, returning name
#   of file.
#
# Parameter(s):
#
#   ofile - name of file to process
#

sub nl_convert {

    # Local Variable(s)
    my ($nfile, $ofh, $nfh);

    # Parameter(s)
    my $ofile = shift;

    # Open files
    $nfile = get_tmpfile();
    $ofh   = new FileHandle "$ofile"
	|| croak "Cannot open $ofile: $!\n";
    $nfh   = new FileHandle "> $nfile"
	|| croak "Cannot open $nfile: $!\n";

    while (<$ofh>) {

	s/\n/\n\r/;
	print $nfh $_;

    } # while ($ofh) 

    # Clean up
    $ofh->close();
    $nfh->close();

    return $nfile;

} # nl_convert

#-----------------------------------------------------------------------
#
# open_socket
#
# Purpose:
#
#   Opens a socket returning it
#
# Parameter(s):
#
#   self - self object
#

sub open_socket {

    # Local Variable(s)
    my ($sock);

    # Parameter(s)
    my $self = shift;

    $sock = IO::Socket::INET->new(Proto    => 'tcp',
				  PeerAddr => $self->{server},
				  PeerPort => $self->{port});

    return $sock;

} # open_socket

#-----------------------------------------------------------------------
#
# get_controlfile
#
# Purpose:
#
#   Creates control file
#
# Parameter(s):
#
#   self - self
#   

sub get_controlfile {

    # Local Variable(s)
    my ($snum,
	$cfile,
	$cfh,
	$key,
	$ccode,
	$myname,
	%chash);

    # Parameter(s)
    my $self = shift;

    $myname  = hostname();
    $snum    = int (rand 1000);

    # Fill up hash
    $chash{'1H'} = $myname;
    $chash{'2P'} = getpwent();
    $chash{'3J'} = $self->{filename};
    $chash{'4C'} = $myname;
    $chash{'5f'} = sprintf("dfA%03d%s",
			   $snum,
			   $myname);
    $chash{'6U'} = sprintf("cfA%03d%s",
			   $snum,
			   $myname);
    $chash{'7N'} = $self->{filename};

    $cfile = get_tmpfile();
    $cfh   = new FileHandle "> $cfile";

    unless ($cfh) {
	carp "Could not create file $cfile: $!\n";
	return undef;
    }

    foreach $key ( sort keys %chash ) {

	$_     = $key;
	s/(.)(.)/$2/g;
	$ccode = $_;

	printf $cfh ("%s%s\n",
		     $ccode,
		     $chash{$key});

    } # foreach $key ( sort keys %chash ) 

    return ($cfile, $chash{'5f'}, $chash{'6U'});

} # get_controlfile

#-----------------------------------------------------------------------
#
# lpd_command
#
# Purpose:
#
#   Sends command to remote lpd process, returning response if
#   asked.
#
# Parameter(s):
#
#   self - self
#
#   cmd  - command to send (should be pre-packed)
#
#   gans - do we get an answer?  (0 - no, 1 - yes)
#

sub lpd_command {

    # Local Variable(s)
    my ($response);

    # Parameter(s)
    my ($self, $cmd, $gans) = @_;

    log_debug(sprintf ("lpd_command:Sending %s", $cmd), $self);

    $self->{socket}->send($cmd);

    if ($gans) {

	# We wait for a response
	eval {

	    local $SIG{ALRM} = sub { die "timeout\n" };

	    alarm 5;
	    $self->{socket}->recv($response, 1024)
		or die "recv: $!\n";

	    1;

	};

	alarm 0;

	if ($@) {
	    
	    if ($@ =~ /timeout/) {
		carp "Timed out sending command\n";
		return undef;
	    }

	}

	log_debug(sprintf("lpd_command:Got back :%s:", $response), $self);

	return $response;

    } # if ($gans)

} # lpd_command

#-----------------------------------------------------------------------
#
# lpd_init
#
# Purpose:
#
#   Notify remote lpd server that we're going to print returning 1 on
#   okay, undef on fail.
#
# Parameter(s):
#
#   self - self
#

sub lpd_init {

    # Local Variable(s)
    my ($buf,
	$retcode);

    # Parameter(s)
    my ($self) = shift;

    # Create and send ready
    $buf = sprintf("%c%s\n", 2, $self->{printer});
    $buf = lpd_command($self, $buf, 1);
    
    $retcode = unpack("c", $buf);
    log_debug("lpd_init:Return code is $retcode", $self);

    if (($retcode =~ /\d/) &&
	($retcode == 0)) {

	log_debug(sprintf("lpd_init:Printer %s on Server %s is okay",
			  $self->{printer},
			  $self->{server}),
		  $self);
	return 1;

    }
    else {

	log_debug(sprintf("lpd_init:Printer %s on Server %s not okay",
			  $self->{printer},
			  $self->{server}),
		  $self);
	log_debug(sprintf("lpd_init:Printer said %s",
			  $buf),
		  $self);

	return undef;

    }

} # lpd_init

#-----------------------------------------------------------------------
#
# lpd_datasend
#
# Purpose:
#
#   Sends the control file and data file
#
# Parameter(s):
#
#   self   - self
#
# 

sub lpd_datasend {

    # Local Variable(s)
    my ($size,
	$type,
	$buf,
	$len,
	$offset,
	$blksize,
	$fh,
	$resp,
	$lpdhash);
    
    # Parameter(s)
    my ($self, $cfile, $dfile, $p_cfile, $p_dfile) = @_;
    
    log_debug("lpd_datasend:init", $self);

    # tie %{$lpdhash}, "Tie::IxHash";
    ($lpdhash) = { "3" => { "name" => $p_dfile,
			    "real" => $dfile },
		   "2" => { "name" => $p_cfile,
			    "real" => $cfile }};
    
    foreach $type (keys %{$lpdhash}) {

	log_debug(sprintf("lpd_datasend:TYPE:%d:FILE:%s:",
			  $type,
			  $lpdhash->{$type}->{"name"}),
		  $self);
	
	# Send msg to lpd
	($size) = (stat $lpdhash->{$type}->{"real"}) [7];
	$buf    = sprintf("%c%ld %s\n",
			  $type,                        # Xmit type
			  $size,                        # size
			  $lpdhash->{$type}->{"name"}); # name
	
	$buf    = lpd_command($self, $buf, 1);

	unless ($buf) {
	    
	    carp "Couldn't send data: $!\n";
	    return undef;

	}

	log_debug(sprintf("lpd_datasend:FILE:%s:RESULT:%s",
			  $lpdhash->{$type}->{"name"}),
		  $self);
       	
	$fh = new FileHandle $lpdhash->{$type}->{"real"};

	unless ($fh) {

	    carp (sprintf("Could not open %s: %s\n",
			  $lpdhash->{$type}->{"real"},
			  $!));
	    return undef;

	}

	$blksize = (stat $fh) [11] || 16384;
	while ($len = sysread $fh, $buf, $blksize) {

	    unless ($len) {

		next
		    if ($! =~ /^Interrupted/);
	
		carp "Error while reading\n";
		return undef;

	    }

	    $offset = 0;
	    while ($len) {

		undef $resp;

		$resp    = syswrite($self->{socket},
				    $buf,
				    $len,
				    $offset);
		
		$len    -= $resp;
		$offset += $resp;

	    }

	} # while ($len = sysread $fh, $buf, $blksize) 

	$fh->close();

	# Confirm server response
	$buf = lpd_command($self,
			   sprintf("%c",
				   0), 
			   1);
	
	log_debug(sprintf("lpd_datasend:Confirmation status: %s",
			  $buf),
		  $self);
	
    } # foreach $type (keys %lpdhash) 

    return 1;

} # lpd_datasend

#-----------------------------------------------------------------------
#
# queuestatus
#
# Purpose:
#
#   Retrieves status information from a specified printer returning
#   output in an array.
#
# Parameter(s):
#
#   None.
#

sub queuestatus {

    # Local Variable(s)
    my ($sock,
	@qstatus);

    # Parameter(s)
    my ($self) = shift;

    # Open Connection to remote printer
    $sock = open_socket($self);

    if ($sock) {
	$self->{socket} = $sock;
    }
    else {
	carp "Could not connect to printer: $!\n";
	return undef;
    }

    # Note that we want to handle remote lpd response ourselves
    lpd_command($self,
		sprintf("%c%s\n",
			4,
			$self->{printer}),
		0);

    # Read response from server and format
    eval {
	
	local $SIG{ALRM} = sub { die "timeout\n" };

	alarm 15;
	$sock = $self->{socket};
	while (<$sock>) {
	    s/($_)/$self->{printer}\@$self->{server}: $1/;
	    push (@qstatus, $_);
	}
	alarm 0;

	1;

    };

    if ($@) {

	carp "Warning: timed out getting status\n"
	    if ($@ =~ /timeout/);	

    }

    # Clean up
    $self->{socket}->shutdown(2);

    return @qstatus;

} # queuestatus

#-----------------------------------------------------------------------
#
# printfile
#
# Purpose:
#
#   Connects to a specified remote print process and transmits a print
#   job.
#
# Parameter(s):
#
#   self - self
#

sub printfile {

    # Local Variable(s)
    my ($cfile,
	$dfile,
	$p_cfile,
	$p_dfile,
	$resp,
	$pname,
	$sock);

    # Parameter(s)
    my $self  = shift;
    my $pfile = shift;

    log_debug("Function printfile", $self);

    # Are we being called with a file?
    $self->{filename} = $pfile
	if ($pfile);

    # File valid?
    if ( !($self->{filename}) ||
	 ( ! -e $self->{filename} )) {
	
	carp sprintf("Given %s not valid\n",
		     $self->{filename});
	return undef;

    } 
    elsif ( uc($self->{lineconvert}) eq "YES") {
	$dfile = nl_convert($self->{filename});
    } 
    else {
	$dfile = $self->{filename};
    } 

    log_debug(sprintf("printfile:Real Data File    %s", $dfile), $self);

    # Create Control File
    ($cfile, $p_dfile, $p_cfile) = get_controlfile($self);

    log_debug(sprintf("printfile:Real Control File %s", $cfile),   $self);
    log_debug(sprintf("printfile:Fake Control File %s", $p_cfile), $self);
    log_debug(sprintf("printfile:Fake Data    File %s", $p_dfile), $self);

    unless ($cfile) {
	carp "Could not create control file\n";
	return undef;
    }

    # Open Connection to remote printer
    $sock = open_socket($self);

    if ($sock) {
	$self->{socket} = $sock;
    }
    else {
	carp "Could not connect to printer: $!\n";
	return undef;
    }

    $resp = lpd_init($self);

    unless ($resp) {
	
	carp (sprintf("Printer %s on %s not ready!\n",
		      $self->{printer},
		      $self->{server}));

	return undef;

    }
    
    $resp = lpd_datasend($self,
			 $cfile,
			 $dfile,
			 $p_cfile,
			 $p_dfile);

    unless ($resp) {

	carp "Error Occured sending data to printer\n";
	return undef;

    }

    # Clean up
    $self->{socket}->shutdown(2);
    
    unlink $cfile;
    unlink $dfile
	if (uc($self->{lineconvert}) eq "YES");

    return 1;

} # printfile

#-----------------------------------------------------------------------

#
# called when module destroyed
#

sub DESTROY {

    # Parameter(s)
    my $self = shift;

    # Just in case :)
    $self->{socket}->shutdown(2)
	if ($self->{socket});

} # DESTROY

#
# called when module initialized
#

sub new {

    # Local variable(s)
    my ($var);

    my (%vars)   = ( "filename"    => "",
		     "lineconvert" => "No",
		     "printer"     => "lp",
		     "server"      => "localhost",
		     "port"        => 515,
		     "debug"       => "No" );
    
    # Parameter(s);
    my $type   = shift;
    my %params = @_;
    my $self   = {};

    foreach $var (keys %vars) {

	log_debug ("VAR:$var:", $self);

	if (exists $params{$var}) {
	    $self->{$var} = $params{$var};
	}
	else {
	    $self->{$var} = $vars{$var};
	}

    }

    foreach $var (keys %vars) {

	log_debug(sprintf("%-10s => %10s\n",
			  $var,
			  $self->{$var}),
		  $self);

    }

    return bless $self, $type;

} # new

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You better edit it!

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

  # Optionally print a file
  $result = $lineprinter->printfile("/home/jdoe/myfile.txt");

  # Print a string
  $result = 
    $lineprinter->printstring("Smoke me a kipper, I'll be back for breakfast.");

  # Get Queue Status
  @result = $lineprinter->queuestatus();

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

=head1 AUTHOR

C. M. Fuhrman, chris.fuhrman@tfcci.com

=head1 SEE ALSO

Socket, lpr(1), lp(1), perl(1).

=cut

