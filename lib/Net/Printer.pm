########################################################################
# File: Net::Printer
#
# $Id$
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

use 5.006;
use strict;
use warnings;

use Carp;
use FileHandle;
use IO::Socket;
use POSIX qw ( tmpnam );
use Sys::Hostname;

require Exporter;
# use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Net::Printer ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
#our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw( printerror printfile printstring queuestatus );
our $VERSION = '0.40';

# ----------------------------------------------------------------------
# Public Methods
# ----------------------------------------------------------------------

# Method: printerror
#
# Prints contents of errstr
#
# Parameters:
#
#   self - self object
#

sub printerror {

    # Parameter(s)
    my $self = shift;

    return $self->{errstr};

} # printerror()

# Method: printfile
#
# Purpose:
#
#   Connects to a specified remote print process and transmits a print
#   job.
#
# Parameters:
#
#   self - self
#
# Returns:
#
#   1 on success, undef on fail

sub printfile {

    my $dfile;

    my $self  = shift;
    my $pfile = shift;

    $self->_logDebug( "invoked ... " );

    # Are we being called with a file?
    $self->{filename} = $pfile
	if ( $pfile );

    $self->_logDebug( sprintf( "Filename is %s",
			       $self->{filename} ) );

    # File valid?
    if ( !( $self->{filename} ) ||
	 ( ! -e $self->{filename} )) {

	$self->_lpdFatal( sprintf( "Given filename (%s) not valid",
				   $self->{filename} ) );
	
	return undef;

    } 
    elsif ( uc( $self->{lineconvert} ) eq "YES") {
	$dfile = $self->_nlConvert();
    } 
    else {
	$dfile = $self->{filename};
    } 

    $self->_logDebug( sprintf("Real Data File    %s", 
			      $dfile) );

    # Create Control File
    my @files = $self->_fileCreate();

    $self->_logDebug( sprintf( "Real Control File %s", 
			       $files[0]   ) );
    $self->_logDebug( sprintf( "Fake Data    File %s", 
			       $files[1] ) );
    $self->_logDebug( sprintf( "Fake Control File %s", 
			       $files[2] ) );

    unless ( -e $files[0] ) {
	$self->_lpdFatal( "Could not create control file\n" );
	return undef;
    }

    # Open Connection to remote printer
    my $sock = $self->_socketOpen();

    if ( $sock ) {
	$self->{socket} = $sock;
    }
    else {
	$self->_lpdFatal( "Could not connect to printer: $!\n" );
	return undef;
    }

    my $resp = $self->_lpdInit();

    unless ( $resp ) {
	
	$self->_lpdFatal( sprintf( "Printer %s on %s not ready!\n",
				   $self->{printer},
				   $self->{server} ) );
	
	return undef;

    }
    
    $resp = $self->_lpdSend( $files[0],
			     $dfile,
			     $files[2],
			     $files[1] );

    unless ( $resp ) {

	$self->_lpdFatal( "Error Occured sending data to printer\n" );
			  
	return undef;

    }

    # Clean up
    $self->{socket}->shutdown(2);
    
    unlink $files[0];
    unlink $dfile
	if ( uc( $self->{lineconvert} ) eq "YES" );

    return 1;

} # printfile()

# Method: printstring
#
# Takes a string and prints it.
#
# Parameters:
#
#   str  - string to print
#
# Returns:
#
#   1 on success, undef on fail

sub printstring {

    # Parameter(s)
    my $self = shift;
    my $str  = shift;

    # Create temporary file
    my $tmpfile = $self->_tmpfile();
    my $fh      = FileHandle->new( "> $tmpfile" );

    unless ($fh) {

	$self->_lpdFatal( "Could not open $tmpfile: $!\n" );

	return undef;

    }

    print $fh $str;
    $fh->close();

    if ( $self->printfile( $tmpfile ) ) {

	unlink $tmpfile;
	return 1;
	
    } 
    else {
	return undef;
    }

} # printstring()

# Method: queuestatus
#
# Retrieves status information from a specified printer returning
# output in an array.
#
# Parameters:
#
#   None.
#
# Returns:
#
#   Array containing queue status

sub queuestatus {

    my @qstatus;

    my $self = shift;

    # Open Connection to remote printer
    my $sock = $self->_socketOpen();

    if ($sock) {
	$self->{socket} = $sock;
    }
    else {
	
	push( @qstatus,
	      sprintf( "%s\@%s: Could not connect to printer: $!\n",
		       $self->{printer},
		       $self->{server} ) );

	return @qstatus;

    }

    # Note that we want to handle remote lpd response ourselves
    $self->_lpdCommand( sprintf("%c%s\n",
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
	    push ( @qstatus, $_ );

	}
	alarm 0;

	1;

    };

    if ($@) {

	push ( @qstatus,
	       sprintf( "%s\@%s: Timed out getting status from remote printer\n",
			$self->{printer},
			$self->{server} ) )
	    if ( $@ =~ /timeout/ );
	
    }
    
    # Clean up
    $self->{socket}->shutdown(2);

    return @qstatus;

} # queuestatus()

# ----------------------------------------------------------------------
# Private Methods
# ----------------------------------------------------------------------

# Method: _logDebug
#
# Displays informative messages ... meant for debugging.
#
# Parameters:
#
#   msg    - message to display
#
# Returns:
#
#   none

sub _logDebug {

    # Parameter(s)
    my $self = shift;
    my $msg  = shift;

    $msg  =~ s/\n//;

    my @a = caller(1);

    printf( "DEBUG-> %-32s: %s\n",
	    $a[3],
	    $msg )
	if ( uc( $self->{debug} ) eq "YES" );

} # _logDebug()

# Method: _lpdFatal
#
# Gets called when there is an unrecoverable error.  Sets error
# object for debugging purposes.
#
# Parameters:
#
#   msg - Error message to log
#
# Returns:
#
#   1

sub _lpdFatal {

    my $self = shift;
    my $msg  = shift;
    
    $msg            =~ s/\n//;
    
    my @a           = caller();

    my $errstr      =  sprintf( "ERROR:%s[%d]: %s",
				$a[0],
				$a[2],
				$msg );

    $self->{errstr} =  $errstr;   
 
    carp "$errstr\n";
    return 1;

} # _lpdFatal()

# Preloaded methods go here.

# Method: _tmpfile
#
# Creates temporary file returning it's name.
#
# Parameters:
#
#   none
#
# Returns:
#
#   name of temporary file

sub _tmpfile {

    my $name;
    my $fh;

    my $self = shift;

    # try new temporary filenames until we get one that didn't already
    # exist 
    do { $name = tmpnam() } until $fh = IO::File->new($name,
						      O_RDWR|O_CREAT|O_EXCL); 

    $fh->close();
    
    return $name;

} # _tmpfile()

# Method: _nlConvert
#
# Given a filename, will convert newline's (\n) to
# newline-carriage-return (\n\r), output to new file, returning name
# of file.
#
# Parameters:
#
#   none
#
# Returns:
#
#   name of file containing strip'd text, undef on fail

sub _nlConvert {

    my $self  = shift;
 
    $self->_logDebug( "invoked ... " );

    # Open files
    my $ofile = $self->{filename};
    my $nfile = $self->_tmpfile();
    my $ofh   = FileHandle->new( "$ofile"   );
    my $nfh   = FileHandle->new( "> $nfile" );


    unless ( $ofh ) {
	$self->_logDebug ( "Cannot open $ofile: $!\n" );
	return undef;
    }

    unless ( $nfh ) {
	$self->_logDebug ( "Cannot open $nfile: $!\n" );
	return undef;
    }

    while (<$ofh>) {

	s/\n/\n\r/;
	print $nfh $_;

    } # while ($ofh) 

    # Clean up
    $ofh->close();
    $nfh->close();

    return $nfile;

} # _nlConvert()

# Method: _socketOpen
#
# Opens a socket returning it
#
# Parameters:
#
#   none
#
# Returns:
#
#   socket

sub _socketOpen {

    my $sock;

    my $self = shift;

    # See if user wants rfc1179 compliance
    if ( uc( $self->{rfc1179} ) eq "NO" ) {

	$sock = IO::Socket::INET->new(Proto    => 'tcp',
				      PeerAddr => $self->{server},
				      PeerPort => $self->{port});
	
    } 
    else {

	# RFC 1179 says "source port be in the range 721-731"
	foreach my $p ( 721 .. 731 ) {

	    $sock = IO::Socket::INET->new( PeerAddr  => $self->{server},
					   PeerPort  => $self->{port},
					   Proto     => 'tcp',
					   LocalPort => $p ) 
		and last;

	} # Iterate through ports

    }
    
    return $sock;

} # _socketOpen()

# Method: _fileCreate
#
# Purpose:
#
#   Creates control file
#
# Parameters:
#
#   none
#   
# Returns:
#
#   *Array containing following elements:*
#
#    - control file
#    - name of data file
#    - name of control file

sub _fileCreate {

    my %chash;

    my $self = shift;

    my $myname  = hostname();
    my $snum    = int ( rand 1000 );

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

    my $cfile = $self->_tmpfile();
    my $cfh   = new FileHandle "> $cfile";

    unless ($cfh) {

	$self->_logDebug( "_fileCreate:Could not create file $cfile: $!" );
	return undef;

    } # if we didn't get a proper filehandle

    foreach my $key ( sort keys %chash ) {

	$_        = $key;

	s/(.)(.)/$2/g;

	my $ccode = $_;

	printf $cfh ( "%s%s\n",
		      $ccode,
		      $chash{$key} );

    } # foreach $key ( sort keys %chash ) 

    return ( $cfile, $chash{'5f'}, $chash{'6U'} );

} # _fileCreate()

# Method: _lpdCommand
#
# Sends command to remote lpd process, returning response if
# asked.
#
# Parameters:
#
#   self - self
#
#   cmd  - command to send (should be pre-packed)
#
#   gans - do we get an answer?  (0 - no, 1 - yes)
#
# Returns:
#
#   response of lpd command

sub _lpdCommand {

    my $response;

    my $self = shift;
    my $cmd  = shift;
    my $gans = shift;

    $self->_logDebug( sprintf ( "Sending %s", 
				$cmd ) );

    $self->{socket}->send( $cmd );

    if ( $gans ) {

	# We wait for a response
	eval {

	    local $SIG{ALRM} = sub { die "timeout\n" };

	    alarm 5;
	    $self->{socket}->recv( $response, 1024)
		or die "recv: $!\n";

	    1;

	};

	alarm 0;

	if ($@) {

	    if ($@ =~ /timeout/) {
		$self->_logDebug( "Timed out sending command" );
		return undef;
	    }

	}

	$self->_logDebug( sprintf( "Got back :%s:", 
				   $response) );

	return $response;

    } # if ($gans)

} # _lpdCommand()

# Method: _lpdInit
#
# Notify remote lpd server that we're going to print returning 1 on
# okay, undef on fail.
#
# Parameters:
#
#   none
#
# Returns:
#
#   1 on success, undef on fail

sub _lpdInit {

    my $buf;
    my $retcode;

    my $self = shift;

    $self->_logDebug( "invoked ... " );

    # Create and send ready
    $buf     = sprintf( "%c%s\n", 2, $self->{printer} );
    $buf     = $self->_lpdCommand( $buf, 1 );
    $retcode = unpack( "c", $buf );

    $self->_logDebug( "Return code is $retcode" );

    if ( ( $retcode =~ /\d/ ) &&
	 ( $retcode == 0 ) ) {

	$self->_logDebug( sprintf( "Printer %s on Server %s is okay",
				   $self->{printer},
				   $self->{server}) );

	return 1;

    } # remote printer ok
    else {

	$self->_lpdFatal( sprintf( "Printer %s on Server %s not okay",
				   $self->{printer},
				   $self->{server} ) );
	$self->_logDebug( sprintf("Printer said %s",
				  $buf ) );

	return undef;

    } # remote printer not ok

} # _lpdInit()

# Method: _lpdSend
#
# Sends the control file and data file
#
# Parameter(s):
#
#   cfile   - Real Control File
#   dfile   - Real Data File
#   p_cfile - Fake Control File
#   p_dfile - Fake Data File
#
# Returns:
#
#   1 on success, undef on fail

sub _lpdSend {

    my $self    = shift;
    my $cfile   = shift;
    my $dfile   = shift;
    my $p_cfile = shift;
    my $p_dfile = shift;

    $self->_logDebug( "invoked ... " );

    my $lpdhash = { "3" => { "name" => $p_dfile,
			     "real" => $dfile },
		    "2" => { "name" => $p_cfile,
			     "real" => $cfile } };
    
    foreach my $type ( keys %{$lpdhash} ) {

	$self->_logDebug( sprintf("TYPE:%d:FILE:%s:",
				  $type,
				  $lpdhash->{$type}->{"name"} ) );
	
	# Send msg to lpd
	my $size = ( stat $lpdhash->{$type}->{"real"} )[7];
	my $buf  = sprintf( "%c%ld %s\n",
			    $type,                         # Xmit type
			    $size,                         # size
			    $lpdhash->{$type}->{"name"} ); # name
	
	$buf     = $self->_lpdCommand( $buf, 1 );

	unless ($buf) {
	    
	    carp "Couldn't send data: $!\n";
	    return undef;

	}

	$self->_logDebug( sprintf( "FILE:%s:RESULT:%s",
				   $lpdhash->{$type}->{"name"} ) );
       	
	my $fh = FileHandle->new( $lpdhash->{$type}->{"real"} );

	unless ( $fh ) {

	    $self->_lpdFatal( sprintf("Could not open %s: %s\n",
				      $lpdhash->{$type}->{"real"},
				      $! ) );

	    return undef;
	    
	}

	my $blksize = ( stat $fh )[11] || 16384;
	
	while ( my $len = sysread $fh, $buf, $blksize ) {

	    unless ($len) {

		next
		    if ($! =~ /^Interrupted/);
	
		carp "Error while reading\n";
		return undef;

	    }
	    
	    my $offset = 0;

	    while ( $len ) {

		my $resp    = syswrite( $self->{socket},
					$buf,
					$len,
					$offset );
		
		$len    -= $resp;
		$offset += $resp;

	    }

	} # while ($len = sysread $fh, $buf, $blksize) 

	$fh->close();

	# Confirm server response
	$buf = $self->_lpdCommand( sprintf("%c",
					   0), 
				   1);
	
	$self->_logDebug( sprintf( "Confirmation status: %s",
				   $buf) );
	
    } # foreach $type (keys %lpdhash) 

    return 1;

} # _lpdSend()

# ----------------------------------------------------------------------
# Standard publically accessible method
# ----------------------------------------------------------------------

# Method: DESTROY
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

# Method: new
#
# called when module initialized
#

sub new {

    my (%vars)   = ( "filename"    => "",
		     "lineconvert" => "No",
		     "printer"     => "lp",
		     "server"      => "localhost",
		     "port"        => 515,
		     "rfc1179"     => "No",
		     "debug"       => "No",
		     "timeout"     => 15);
    
    # Parameter(s);
    my $type   = shift;
    my %params = @_;
    my $self   = {};

    foreach my $var (keys %vars) {

	if (exists $params{$var}) {
	    $self->{$var} = $params{$var};
	}
	else {
	    $self->{$var} = $vars{$var};
	}

    }

    $self->{errstr} = undef;

    return bless $self, $type;

} # new

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

  # Did I get an error?
  $errstr = $lineprinter->printerror();

  # Get Queue Status
  @result = $lineprinter->queuestatus();

=head1 DESCRIPTION

Perl module for directly printing to a print server/printer without
having to create a pipe to either lpr or lp.  This essentially mimics
what the BSD LPR program does by connecting directly to the line
printer printer port (almost always 515), and transmitting the data
and control information to the print server. 

Please note that this module only talks to print servers that speak
BSD.  It will not talk to printers using SMB or SysV unless they are
set up as BSD printers.  CUPS users will need to set up B<cups-lpd> to
provide legacy access. ( See L</"Using Net::Printer with CUPS"> ) 

=head2 Parameters


=over 10

=item filename

[optional] absolute path to the file you wish to print.

=item printer

[optional] Name of the printer you wish to print to.  
Default "lp".

=item server

[optional] Name of the server that is running /lpsched.  Default
"localhost".   

=item port

[optional] The port you wish to connect to.  Default "515".

=item lineconvert

[optional] Perform LF -> LF/CR translation.  Default "NO"

=item rfc1179

[optional] Use RFC 1179 compliant source address.  Default "NO".  See
below for security implications 

=back

=head2 Functions

I<printfile> prints a specified file to the printer.  Returns a 1 on
success, otherwise returns a string containing the error.

I<printstring> prints a specified string to the printer as if it were
a complete file Returns a 1 on success, otherwise returns a string
containing the error.

I<queuestatus> returns the current status of the print queue.  I
recommend waiting a short period of time between printing and issuing
a queuestatus to give your spooler a chance to do it's thing.  5
seconds tends to work for me.

I<printerror> returns the error for your own purposes.

=head1 TROUBLESHOOTING

=head2 Stair Stepping Problem


When printing text, if you have the infamous "stair-stepping" problem,
try setting lineconvert to "YES".  This should, in most cases, rectify
the problem.

=head2 RFC-1179 Compliance Mode and Security Implications

RFC 1179 specifies that any program connecting to a print service must
use a source port between 721 and 731, which are I<reserved ports>,
meaning you must have root (administrative) privileges to use them.
I<This is a security risk which should be avoided if at all
possible!>

=head2 Using Net::Printer with CUPS

Net::Printer, by itself, does not speak to printers running the CUPS
protocol.  In order to provide support for legacy clients, most modern CUPS
distributions include the B<cups-lpd> mini-server which can be set up
to run out of either B<inetd> or B<xinetd> depending on preference.
You will need to set up this functionality in order to use
Net::Printer with a CUPS server.

=head1 AUTHOR

C. M. Fuhrman, chris.fuhrman@tfcci.com

=head1 SEE ALSO

cups-lpd(8), lp(1), lpr(1), perl(1), socket(2)

RFC 1179 L<http://www.ietf.org/rfc/rfc1179.txt?number=1179>

=cut

