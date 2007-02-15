# Declare our package
package POE::Component::Server::SimpleHTTP::PreFork;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
# $Revision: 1181 $
our $VERSION = '0.01';

# Import what we need from the POE namespace
use POE;
use base qw( POE::Component::Server::SimpleHTTP );

# Other miscellaneous modules we need
use Carp qw( croak );

# HTTP-related modules
use HTTP::Date qw( time2str );

# IPC modules
use IPC::Shareable qw( :lock );

# Set some constants
BEGIN {
	# Interval at which to check spares
	if ( ! defined &CHECKSPARES_INTERVAL ) {
		eval "sub CHECKSPARES_INTERVAL () { 1 }";
	}

	# Interval at which to retry preforking
	if ( ! defined &PREFORK_INTERVAL ) {
		eval "sub PREFORK_INTERVAL () { 5 }";
	}

	# If true, show the scoreboard every second
	if ( ! defined &DEBUGSB ) {
		eval "sub DEBUGSB () { 0 }";
	}
}

# Set things in motion!
sub new {
	# Get the OOP's type
	my $type = shift;

	# Sanity checking
	if ( @_ & 1 ) {
		croak( 'POE::Component::Server::SimpleHTTP::PreFork->new needs even number of options' );
	}

	# The options hash
	my %opt = @_;

	# Our own options
	my ( $ALIAS, $ADDRESS, $PORT, $HOSTNAME, $HEADERS, $HANDLERS, $SSLKEYCERT );
	# options for pre-forking
	my ( $FORKHANDLERS, $STARTSERVERS, $MINSPARESERVERS, $MAXSPARESERVERS, $MAXCLIENTS );

	# You could say I should do this: $Stuff = delete $opt{'Stuff'}
	# But, that kind of behavior is not defined, so I would not trust it...

	# Get the SSL array
	if ( exists $opt{'SSLKEYCERT'} and defined $opt{'SSLKEYCERT'} ) {
		# Test if it is an array
		if ( ref( $opt{'SSLKEYCERT'} ) eq 'ARRAY' and scalar( @{ $opt{'SSLKEYCERT'} } ) == 2 ) {
			$SSLKEYCERT = $opt{'SSLKEYCERT'};
			delete $opt{'SSLKEYCERT'};

			# Okay, pull in what is necessary
			eval {
				use POE::Component::SSLify qw( SSLify_Options SSLify_GetSocket Server_SSLify SSLify_GetCipher );
				SSLify_Options( @$SSLKEYCERT );
			};
			if ( $@ ) {
				if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
					warn "Unable to load PoCo::SSLify -> $@";
				}

				# Force ourself to not use SSL
				$SSLKEYCERT = undef;
			}
		} else {
			if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
				warn 'The SSLKEYCERT option must be an array with exactly 2 elements in it!';
			}
		}
	} else {
		$SSLKEYCERT = undef;
	}

	# Get the session alias
	if ( exists $opt{'ALIAS'} and defined $opt{'ALIAS'} and length( $opt{'ALIAS'} ) ) {
		$ALIAS = $opt{'ALIAS'};
		delete $opt{'ALIAS'};
	} else {
		# Debugging info...
		if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
			warn 'Using default ALIAS = SimpleHTTP';
		}

		# Set the default
		$ALIAS = 'SimpleHTTP';

		# Get rid of any lingering ALIAS
		if ( exists $opt{'ALIAS'} ) {
			delete $opt{'ALIAS'};
		}
	}

	# Get the PORT
	if ( exists $opt{'PORT'} and defined $opt{'PORT'} and length( $opt{'PORT'} ) ) {
		$PORT = $opt{'PORT'};
		delete $opt{'PORT'};
	} else {
		croak( 'PORT is required to create a new POE::Component::Server::SimpleHTTP instance!' );
	}

	# Get the ADDRESS
	if ( exists $opt{'ADDRESS'} and defined $opt{'ADDRESS'} and length( $opt{'ADDRESS'} ) ) {
		$ADDRESS = $opt{'ADDRESS'};
		delete $opt{'ADDRESS'};
	} else {
		croak( 'ADDRESS is required to create a new POE::Component::Server::SimpleHTTP instance!' );
	}

	# Get the HOSTNAME
	if ( exists $opt{'HOSTNAME'} and defined $opt{'HOSTNAME'} and length( $opt{'HOSTNAME'} ) ) {
		$HOSTNAME = $opt{'HOSTNAME'};
		delete $opt{'HOSTNAME'};
	} else {
		if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
			warn 'Using Sys::Hostname for HOSTNAME';
		}

		# Figure out the hostname
		require Sys::Hostname;
		$HOSTNAME = Sys::Hostname::hostname();

		# Get rid of any lingering HOSTNAME
		if ( exists $opt{'HOSTNAME'} ) {
			delete $opt{'HOSTNAME'};
		}
	}

	# Get the HEADERS
	if ( exists $opt{'HEADERS'} and defined $opt{'HEADERS'} ) {
		# Make sure it is ref to hash
		if ( ref $opt{'HEADERS'} and ref( $opt{'HEADERS'} ) eq 'HASH' ) {
			$HEADERS = $opt{'HEADERS'};
			delete $opt{'HEADERS'};
		} else {
			croak( 'HEADERS must be a reference to a HASH!' );
		}
	} else {
		# Set to none
		$HEADERS = {};

		# Get rid of any lingering HEADERS
		if ( exists $opt{'HEADERS'} ) {
			delete $opt{'HEADERS'};
		}
	}

	# Get the HANDLERS
	if ( exists $opt{'HANDLERS'} and defined $opt{'HANDLERS'} ) {
		# Make sure it is ref to array
		if ( ref $opt{'HANDLERS'} and ref( $opt{'HANDLERS'} ) eq 'ARRAY' ) {
			$HANDLERS = $opt{'HANDLERS'};
			delete $opt{'HANDLERS'};
		} else {
			croak( 'HANDLERS must be a reference to an ARRAY!' );
		}
	} else {
		croak( 'HANDLERS is required to create a new POE::Component::Server::SimpleHTTP instance!' );
	}

	# Get the FORKHANDLERS
	if ( exists $opt{'FORKHANDLERS'} and defined $opt{'FORKHANDLERS'} ) {
		# Make sure it is ref to a hash
		if ( ref $opt{'FORKHANDLERS'} and ref( $opt{'FORKHANDLERS'} ) eq 'HASH' ) {
			$FORKHANDLERS = $opt{'FORKHANDLERS'};
			delete $opt{'FORKHANDLERS'};
		} else {
			croak( 'FORKHANDLERS must be a reference to a HASH!' );
		}
	} else {
		$FORKHANDLERS = {};

		# Get rid of any lingering FORKHANDLERS
		if ( exists $opt{'FORKHANDLERS'} ) {
			delete $opt{'FORKHANDLERS'};
		}
	}

	# Get the MINSPARESERVERS
	if ( exists $opt{'MINSPARESERVERS'} and defined $opt{'MINSPARESERVERS'} ) {
		$MINSPARESERVERS = int $opt{'MINSPARESERVERS'};
		delete $opt{'MINSPARESERVERS'};

		if ( $MINSPARESERVERS <= 0 ) {
			croak( 'MINSPARESERVERS must be greater than 0!' );
		}
	} else {
		$MINSPARESERVERS = 5;

		# Get rid of any lingering MINSPARESERVERS
		if ( exists $opt{'MINSPARESERVERS'} ) {
			delete $opt{'MINSPARESERVERS'};
		}
	}

	# Get the MAXSPARESERVERS
	if (exists $opt{'MAXSPARESERVERS'} and defined $opt{'MAXSPARESERVERS'} ) {
		$MAXSPARESERVERS = int $opt{'MAXSPARESERVERS'};
		delete $opt{'MAXSPARESERVERS'};
	} else {
		$MAXSPARESERVERS = 10;

		# Get rid of any lingering MAXSPARESERVERS
		if ( exists $opt{'MAXSPARESERVERS'} ) {
			delete $opt{'MAXSPARESERVERS'};
		}
	}
	# Adjust and make sure MAXSPARESERVERS makes sense
	if ( $MAXSPARESERVERS <= $MINSPARESERVERS ) {
		if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
			warn 'MAXSPARESERVERS is less than or equal to MINSPARESERVERS. Resetting.';
		}

		$MAXSPARESERVERS = $MINSPARESERVERS + 1;
	}

	# Get the MAXCLIENTS
	if (exists $opt{'MAXCLIENTS'} and defined $opt{'MAXCLIENTS'} ) {
		$MAXCLIENTS = int $opt{'MAXCLIENTS'};
		delete $opt{'MAXCLIENTS'};
	} else {
		$MAXCLIENTS = 256;

		# Get rid of any lingering MAXCLIENTS
		if ( exists $opt{'MAXCLIENTS'} ) {
			delete $opt{'MAXCLIENTS'};
		}
	}

	# Get the STARTSERVERS
	if (exists $opt{'STARTSERVERS'} and defined $opt{'STARTSERVERS'} ) {
		$STARTSERVERS = int $opt{'STARTSERVERS'};
		delete $opt{'STARTSERVERS'};

		if ( $STARTSERVERS <= 0 ) {
			croak( 'STARTSERVERS must be greater than or equal to 0!' );
		}
	} else {
		$STARTSERVERS = 10;

		# Get rid of any lingering STARTSERVERS
		if ( exists $opt{'STARTSERVERS'} ) {
			delete $opt{'STARTSERVERS'};
		}
	}
	# Adjust and make sure STARTSERVERS makes sense
	if ( $STARTSERVERS < $MINSPARESERVERS ) {
		if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
			warn 'STARTSERVERS is less than MINSPARESERVERS. Resetting.';
		}

		$STARTSERVERS = $MINSPARESERVERS;
	}

	# Anything left over is unrecognized
	if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
		if ( keys %opt > 0 ) {
			croak( 'Unrecognized options were present in POE::Component::Server::SimpleHTTP::PreFork->new -> ' . join( ', ', keys %opt ) );
		}
	}

	# Create a new session for ourself
	POE::Session->create(
		# Our subroutines
		'inline_states'	=>	{
			# Maintenance events
			'_start'		=>	\&StartServer,
			'_stop'			=>	\&POE::Component::Server::SimpleHTTP::FindRequestLeaks,
			'_child'		=>	sub {},

			# Pre-forking events
			'ISCHILD'		=>	\&IsChild,
			'GETFORKHANDLERS'	=>	\&GetForkHandlers,
			'SETFORKHANDLERS'	=>	\&SetForkHandlers,

			# Internal pre-forking events
			'SigCHLD'		=>	\&SigCHLD,
			'SigTERM'		=>	\&SigTERM,
			'PreFork'		=>	\&PreFork,
			'KillChildren'		=>	\&KillChildren,
			'CheckSpares'		=>	\&CheckSpares,
			'UpdateScoreboard'	=>	\&UpdateScoreboard,
			'AddScoreboard'		=>	\&AddScoreboard,
			'ShowScoreboard'	=>	\&ShowScoreboard,

			# HANDLER stuff
			'GETHANDLERS'		=>	\&POE::Component::Server::SimpleHTTP::GetHandlers,
			'SETHANDLERS'		=>	\&SetHandlers,

			# SocketFactory events
			'SHUTDOWN'		=>	\&StopServer,
			'STOPLISTEN'		=>	\&StopListen,
			'STARTLISTEN'		=>	\&StartListen,
			'SetupListener'		=>	\&SetupListener,
			'ListenerError'		=>	\&POE::Component::Server::SimpleHTTP::ListenerError,

			# Wheel::ReadWrite stuff
			'Got_Connection'	=>	\&Got_Connection,
			'Got_Input'		=>	\&Got_Input,
			'Got_Flush'		=>	\&Got_Flush,
			'Got_Error'		=>	\&Got_Error,

			# Send output to connection!
			'DONE'		=>	\&POE::Component::Server::SimpleHTTP::Request_Output,

			# Kill the connection!
			'CLOSE'		=>	\&Request_Close,
		},

		# Set up the heap for ourself
		'heap'		=>	{
			'ALIAS'			=>	$ALIAS,
			'ADDRESS'		=>	$ADDRESS,
			'PORT'			=>	$PORT,
			'HEADERS'		=>	$HEADERS,
			'HOSTNAME'		=>	$HOSTNAME,
			'HANDLERS'		=>	$HANDLERS,
			'REQUESTS'		=>	{},
			'RETRIES'		=>	0,
			'SSLKEYCERT'		=>	$SSLKEYCERT,
			'MINSPARESERVERS'	=>	$MINSPARESERVERS,
			'MAXSPARESERVERS'	=>	$MAXSPARESERVERS,
			'MAXCLIENTS'		=>	$MAXCLIENTS,
			'STARTSERVERS'		=>	$STARTSERVERS,
			'ISCHILD'		=>	0,
			'FORKHANDLERS'		=>	$FORKHANDLERS,
			'SCOREBOARD'		=>	undef
		},
	) or die 'Unable to create a new session!';

	# Return success
	return 1;
}

# Starts the server!
sub StartServer {
	# Settup our signal handlers
	$_[KERNEL]->sig( TERM => 'SigTERM' );
	$_[KERNEL]->sig( CHLD => 'SigCHLD' );

	# Call the super class method.
	return POE::Component::Server::SimpleHTTP::StartServer( @_ );
}

# Stops the server!
sub StopServer {
	my $children;

	# Shutdown the SocketFactory wheel
	if ( exists $_[HEAP]->{'SOCKETFACTORY'} ) {
		delete $_[HEAP]->{'SOCKETFACTORY'};
	}

	# Debug stuff
	if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
		warn 'Stopped listening for new connections!';
	}

	# Are we gracefully shutting down or not?
	if ( defined $_[ARG0] and $_[ARG0] eq 'GRACEFUL' ) {
		# Attempt to gracefully kill the children.
		$children = $_[KERNEL]->call( $_[SESSION], 'KillChildren', 'TERM' );

		# Check for number of requests, and children.
		if ( (keys( %{ $_[HEAP]->{'REQUESTS'} } ) == 0) && ($children == 0) ) {
			# Alright, shutdown anyway

			# Delete our alias
			$_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );

			# Destroy all memory segments created by this process.
			IPC::Shareable->clean_up;
			$_[HEAP]->{'SCOREBOARD'} = undef;

			# Debug stuff
			if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
				warn 'Stopped SimpleHTTP gracefully, no requests left';
			}
		}

		# All done!
		return 1;
	}

	# Forcefully kill all the children.
		$_[KERNEL]->call( $_[SESSION], 'KillChildren', 'KILL' );

		# Forcibly close all sockets that are open
		foreach my $conn ( keys %{ $_[HEAP]->{'REQUESTS'} } ) {
			# Can't call method "shutdown_input" on an undefined value at
			# /usr/lib/perl5/site_perl/5.8.2/POE/Component/Server/SimpleHTTP.pm line 323.
			if ( defined $_[HEAP]->{'REQUESTS'}->{ $conn }->[0] and defined $_[HEAP]->{'REQUESTS'}->{ $conn }->[0]->[ POE::Wheel::ReadWrite::HANDLE_INPUT ] ) {
				$_[HEAP]->{'REQUESTS'}->{ $conn }->[0]->shutdown_input;
				$_[HEAP]->{'REQUESTS'}->{ $conn }->[0]->shutdown_output;
			}

			# Delete this request
			delete $_[HEAP]->{'REQUESTS'}->{ $conn };
		}

		# Remove any shared memory segments.
		IPC::Shareable->clean_up;
		$_[HEAP]->{'SCOREBOARD'} = undef;

		# Delete our alias
		$_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );

	# Debug stuff
	if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
		warn 'Successfully stopped SimpleHTTP';
	}

	# Return success
	return 1;
}

# Kill all our children, and return the number we sent signals too.
sub KillChildren {
	my ( $heap, $sig ) = @_[ HEAP, ARG0 ];
	my ( $children, $scoreboard, $mem ) = 0;

	# By default, kill them nicely.
	$sig = 'TERM' unless defined $sig;

	# Make sure we are the parent AND preforked.
	if ( $heap->{'ISCHILD'} == 0 ) {
		if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
			warn "Killing children from $$ with signal $sig.";
		}

		$scoreboard = $heap->{'SCOREBOARD'};
		$mem = tied %$scoreboard;
		if ( not defined $mem ) {
			# There was an error, but there's nothing we can do,
			# so just exit.
			warn "Parent's SCOREBOARD is not tied!";
			$children = 0;
		} else {
			# Get a count of the number of children, and start killing them
			$mem->shlock( LOCK_SH );
			# The children haven't already received a signal, so send them one.
			foreach my $pid ( keys %$scoreboard ) {
				if ( ($pid ne 'actives') && ($pid ne 'spares') ) {
					++$children;
					kill $sig, $pid;
				}
			}
			$mem->shlock( LOCK_UN );

			# Check to make sure it is sane.
			if ( $children < 0 ) {
				warn "The child count is negative: $children.";
				$children = 0;
			}
		}
	}

	return $children;
}

# Sets up the SocketFactory wheel :)
sub SetupListener {
	# Debug stuff
	if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
		warn 'Creating SocketFactory wheel now';
	}

	# Only try to re-establish the listener if we are the parent
	if ( $_[HEAP]->{'ISCHILD'} ) {
			warn 'Inside the child. Aborting attempt to reestablish the listener.';
		return 0;
	}

	# Check if we should set up the wheel
	if ( $_[HEAP]->{'RETRIES'} == POE::Component::Server::SimpleHTTP::MAX_RETRIES ) {
		die 'POE::Component::Server::SimpleHTTP::PreFork tried ' . POE::Component::Server::SimpleHTTP::MAX_RETRIES . ' times to create a Wheel and is giving up...';
	} else {
		# Increment the retry count if we did not get 'NOINC' as an argument
		if ( ! defined $_[ARG0] ) {
			# Increment the retries count
			$_[HEAP]->{'RETRIES'}++;
		}

		# Create our own SocketFactory Wheel :)
		$_[HEAP]->{'SOCKETFACTORY'} = POE::Wheel::SocketFactory->new(
			'BindPort'	=>	$_[HEAP]->{'PORT'},
			'BindAddress'	=>	$_[HEAP]->{'ADDRESS'},
			'Reuse'		=>	'yes',
			'SuccessEvent'	=>	'Got_Connection',
			'FailureEvent'	=>	'ListenerError',
		);

		# Pre-fork if that is what was requested
		if ( $_[HEAP]->{'STARTSERVERS'} ) {
			# We don't want to accept socket connections in the parent process
			$_[HEAP]->{'SOCKETFACTORY'}->pause_accept();

			# Wait a bit and then do the actual forking
			$_[KERNEL]->yield( 'PreFork', $_[HEAP]->{'SOCKETFACTORY'} );
		}
	}

	# Success!
	return 1;
}

# PreFork the initial instances.
sub PreFork {
	# ARG0 = SocketFactory
	my ( $kernel, $heap, $sf ) = @_[ KERNEL, HEAP, ARG0 ];
	my ( $scoreboard, $mem );

	if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
		warn 'Trying to prefork.';
	}

	# Only the parent is allowed to fork
	if ( $heap->{'ISCHILD'} ) {
		warn "Cannot pre-fork from child $$.";
		return 0;
	}

	# Make that the current SF is the same as the one we were called for.
	# If not, then that means and error occured sometime inbetween.
	if ( (not defined $heap->{'SOCKETFACTORY'}) || ($sf != $heap->{'SOCKETFACTORY'}) ) {
		warn 'Aborting pre-fork because the SocketFactory is not the same.';
		return 0;
	}


	# Initialize the scoreboard the first time around.
	if ( not defined $heap->{'SCOREBOARD'} ) {
		my %temp;

		# In order to keep a pool of spare children we need to know how many spares there are.
		$mem = tie %temp, 'IPC::Shareable', 'scbd', { 'create' => 1, 'mode' => 0600 };
		$scoreboard = \%temp;
	} else {
		# We already have a scoreboard from a previous listen attempt.
		$scoreboard = $heap->{'SCOREBOARD'};
		$mem = tied %$scoreboard;
	}

	if ( not defined $mem ) {
		warn 'Cannot tie to the shared memory segment. Will try again in 5 seconds.';
		$kernel->delay_set( 'PreFork', PREFORK_INTERVAL, $sf );
		return 0;
	} else {
		# Clear the variable and store it for later use.
		%$scoreboard = ( 'spares' => 0, 'actives' => 0 );
		$heap->{'SCOREBOARD'} = $scoreboard;
	}

	for ( 1 .. $heap->{'STARTSERVERS'} ) {
		my $pid = fork();

		if ( not defined $pid ) {
			# Make sure this fork succeeded.
			warn "Server $$ fork failed: $!";
			next;
		} elsif ( $pid ) {
			# We are the parent.
			next;
		} else {
			if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
				warn "Forked child $$.";
			}

			# We are the child. Do something "childish".
			$heap->{'ISCHILD'} = 1;
			$kernel->call( $_[SESSION], 'AddScoreboard' );

			# Notify the other forked sessions that we have forked.
			foreach my $sess ( keys( %{$heap->{'FORKHANDLERS'}} ) ) {
				$_[KERNEL]->call( $sess, $heap->{'FORKHANDLERS'}->{$sess} );
			}


			# Get to work!
			$sf->resume_accept();
			return 1;
		}
	}

	# Pre-forking is done and our children are happily away!
	# We are the parent, so start monitoring the spare pool.
	$kernel->delay_set( 'CheckSpares', CHECKSPARES_INTERVAL );

	# Let the developer see the scoreboard if they want.
	if ( DEBUGSB ) {
		$kernel->delay_set( 'ShowScoreboard', 1 );
	}
}

# True if this is a child.
sub IsChild {
	return $_[HEAP]->{'ISCHILD'};
}

# Check to see if we need a new spare.
sub CheckSpares {
	my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	my ( $scoreboard, $mem );

	# Make sure that we are not a child.
	if ( $heap->{'ISCHILD'} ) {
		warn "Child $$ trying to check the spares!";
		return 0;
	}

	# Make sure there is still a socket factory. If not, then this server
	# is shutting down.
	if ( not defined $heap->{'SOCKETFACTORY'} ) {
		if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
			warn 'Ending CheckSpares on the parent.';
		}
		return 1;
	}

	# Retrieve the shared memory variable.
	$scoreboard = $heap->{'SCOREBOARD'};
	$mem = tied %$scoreboard if defined $scoreboard;
	if ( not defined $mem ) {
		warn 'SCOREBOARD is not tied! Aborting.';
		return 0;
	}

	# Check to see if we need another spare, and if so make sure we don't
	# already have more than enough clients.
	$mem->shlock( LOCK_SH );
	if ( ($scoreboard->{'spares'} < $heap->{'MINSPARESERVERS'}) &&
	     ((keys( %$scoreboard ) - 2) < $heap->{'MAXCLIENTS'}) ) {
	     	$mem->shlock( LOCK_UN );
		my $pid = fork();

		if ( not defined $pid ) {
			warn 'fork failed while creating a new spare.';
		} elsif ( $pid ) {
			# We are the parent.
		} else {
			if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
				warn "Created spare child $$.";
			}

			# We are the child. Do something "childish".
			$heap->{'ISCHILD'} = 1;
			$kernel->call( $_[SESSION], 'AddScoreboard' );

			# Notify the other forked sessions that we have forked.
			foreach my $sess ( keys( %{$heap->{'FORKHANDLERS'}} ) ) {
				$_[KERNEL]->call( $sess, $heap->{'FORKHANDLERS'}->{$sess} );
			}

			# Start accepting connections!
			$heap->{'SOCKETFACTORY'}->resume_accept();
		}
	} else {
		# No new spares were needed.
		$mem->shlock( LOCK_UN );
	}

	# If we are the parent, then reschedule another spare check.
	if ( $heap->{'ISCHILD'} == 0 ) {
		$kernel->delay_set( 'CheckSpares', CHECKSPARES_INTERVAL );
	}
}

# Debug routine so that we can watch what is happening on the scoreboard.
sub ShowScoreboard {
	my ( $heap ) = $_[ HEAP ];
	my ( $scoreboard, $mem, $hcount, $pid );

	# Check to make sure we are not a child.
	if ( $heap->{'ISCHILD'} ) {
		return 0;
	}

	# Check to make sure the scoreboard is still up.
	$scoreboard = $heap->{'SCOREBOARD'};
	if ( not defined $scoreboard ) {
		return 0;
	}

	# Retrieve the underlying class.
	$mem = tied %$scoreboard;
	if ( not defined $mem ) {
		warn 'SCOREBOARD is not tied! Aborting.';
		return 0;
	}

	# Lock the scoreboard and print out the entries.
	$mem->shlock( LOCK_SH );
	$hcount = 0;
	print STDERR "[$$] actives = ", $scoreboard->{'actives'}, "\tspares = ", $scoreboard->{'spares'}, "\n";
	foreach $pid ( keys %$scoreboard ) {
		next if ($pid eq 'actives') || ($pid eq 'spares');

		print STDERR $pid, " = ", $scoreboard->{$pid};
		if ( ++$hcount % 5 == 0 ) {
			print STDERR "\n";
		} else {
			print STDERR "\t";
		}
	}
	print STDERR "\n\n";
	$mem->shlock( LOCK_UN );

	# If the socketfactory still exists then we should continue looping.
	if ( exists $heap->{'SOCKETFACTORY'} ) {
		$_[KERNEL]->delay_set( 'ShowScoreboard', 1 );
	}
}

# A child died :(
sub SigCHLD {
	my ( $heap, $pid ) = @_[ HEAP, ARG1 ];
	my ( $scoreboard, $mem, $children );

	# Check to see if we are in preforked mode and the parent.
	if ( $heap->{'ISCHILD'} == 0 ) {
		# Retrieve our scoreboard.
		$scoreboard = $heap->{'SCOREBOARD'};
		$mem = tied %$scoreboard if defined $scoreboard;
		if ( not defined $mem ) {
			warn 'Cannot get the IPC::Shareable object for the SCOREBOARD!';
			return;
		}

		$mem->shlock( LOCK_EX );
		# Cleanup children here (they should never do it themselves).
			if ( exists $scoreboard->{$pid} ) {
				if ( $scoreboard->{$pid} eq 'S' ) {
					--$scoreboard->{'spares'};
				} elsif ( $scoreboard->{$pid} eq 'A' ) {
					--$scoreboard->{'actives'};
				}
				delete $scoreboard->{$pid};
			}

		# Get the number of children.
		$children = keys( %$scoreboard ) - 2;

		$mem->shlock( LOCK_UN );

		# If the children are dying and the SOCKETFACTORY no longer exists, then
		# we are probably in a graceful shutdown.
		if ( ($children <= 0) && (not exists $heap->{'SOCKETFACTORY'}) ) {
			$_[KERNEL]->yield( 'SHUTDOWN', 'GRACEFUL' );
		}
	}
}

# Someone is asking us to quit...
sub SigTERM {
	my ( $sig ) = $_[ ARG0 ];

	if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
		warn "Caught signal ", $sig, " inside $$. Initiating graceful shutdown.";
	}

	# Shutdown gracefully, and tell POE we handled the signal.
	$_[KERNEL]->yield( 'SHUTDOWN', 'GRACEFUL' );
	$_[KERNEL]->sig_handled();
}

# Add the scoreboard entry for this child.
sub AddScoreboard {
	my ( $heap ) = $_[ HEAP ];
	my ( $scoreboard, $mem );

	# Check to see if we are preforked.
	if ( $heap->{'ISCHILD'} ) {
		$scoreboard = $heap->{'SCOREBOARD'};
		$mem = tied %$scoreboard if defined $scoreboard;
		if ( not defined $mem ) {
			# Don't do anyting if we can't lock stuff.
			warn "SCOREBOARD is not tied to IPC::Shareable in child $$!";
		} else {
			# Lock the scoreboard and record ourself properly.
			$mem->shlock( LOCK_EX );
			if ( not exists $scoreboard->{$$} ) {
				$scoreboard->{$$} = 'S';
				++$scoreboard->{'spares'};
			}
			$mem->shlock( LOCK_UN );
		}
	}

	return 1;
}

# Set the scoreboard entry for this child.
sub UpdateScoreboard {
	my ( $heap ) = $_[ HEAP ];
	my ( $scoreboard, $mem );

	# Check to see if we are preforked.
	if ( $heap->{'ISCHILD'} ) {
		$scoreboard = $heap->{'SCOREBOARD'};
		$mem = tied %$scoreboard if defined $scoreboard;
		if ( not defined $mem ) {
			# Don't do anyting if we can't lock stuff.
			warn "SCOREBOARD is not tied to IPC::Shareable in child $$!";
		} else {
			# Lock the scoreboard and record ourself properly.
			$mem->shlock( LOCK_EX );
			if ( (keys( %{$heap->{'REQUESTS'}} ) == 0) && ($scoreboard->{$$} eq 'A') ) {
				$scoreboard->{$$} = 'S';
				++$scoreboard->{'spares'};
				--$scoreboard->{'actives'};

				# If we have too many spares then ask this one to shutdown.
				if ( $scoreboard->{'spares'} > $heap->{'MAXSPARESERVERS'} ) {
					if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
						warn "Shutting down $$ because of too many spares.";
					}

					$_[KERNEL]->yield( 'SHUTDOWN', 'GRACEFUL' );
				}
			} elsif ( (keys( %{$heap->{'REQUESTS'}} ) != 0) && ($scoreboard->{$$} eq 'S') ) {
				$scoreboard->{$$} = 'A';
				--$scoreboard->{'spares'};
				++$scoreboard->{'actives'};
			}
			$mem->shlock( LOCK_UN );
		}
	}

	return 1;
}

# Stops listening on the socket
sub StopListen {
	if ( $_[HEAP]->{'ISCHILD'} ) {
		# If we are the child then we shouldn't really stop listening.
		# Instead, pause accepting on our SocketFactory.
		if ( (not exists $_[HEAP]->{'SOCKETFACTORY'}) || (not defined $_[HEAP]->{'SOCKETFACTORY'} ) ) {
			warn "Cannot StopListen on a non-existant SOCKETFACTORY in child $$";
			return 0;
		} else {
			# Pause accepting.
			$_[HEAP]->{'SOCKETFACTORY'}->pause_accept();
			return 1;
		}
	} else {
		# We are in the parent, so truly stop listening.
		# Kill the children because they are still listenning.
		$_[KERNEL]->call( $_[SESSION], 'KillChildren', 'TERM' );

		# Call the super class method.
		return POE::Component::Server::SimpleHTTP::StopListen( @_ );
	}
}

sub StartListen {
	if ( $_[HEAP]->{'ISCHILD'} ) {
		# If we are the child then we can't really create a new SOCKETFACTORY.
		# Instead, we can resume accepting on our current SOCKETFACTORY.
		if ( (not exists $_[HEAP]->{'SOCKETFACTORY'}) || (not defined $_[HEAP]->{'SOCKETFACTORY'} ) ) {
			warn "Cannot StartListen on a non-existant SOCKETFACTORY in child $$";
			return 0;
		} else {
			# Resume accepting.
			$_[HEAP]->{'SOCKETFACTORY'}->resume_accept();
			return 1;
		}
	} else {
		# We are the parent. Truly start listening again.
		return POE::Component::Server::SimpleHTTP::StartListen( @_ );
	}
}

# Sets the HANDLERS
sub SetHandlers {
	# Setting handlers in a child makes little sense, so abort if this is the case
	if ( $_[HEAP]->{'ISCHILD'} ) {
		warn "Child $$ tried to set the handlers for SimpleHTTP.";
		return 0;
	}

	# Call the super class method.
	return POE::Component::Server::SimpleHTTP::SetHandlers( @_ );
}

# Sets the FORKHANDLERS
sub SetForkHandlers {
	# ARG0 = ref to handlers hash
	my $handlers = $_[ARG0];

	# Setting handlers in a child makes little sense, so abort if this is the case.
	if ( $_[HEAP]->{'ISCHILD'} ) {
		warn "Child $$ tried to set the handlers for SimpleHTTP.";
		return 0;
	}

	# Validate it...
	if ( (not defined $handlers) || (ref( $handlers ) ne 'HASH') ) {
		warn "FORKHANDLERS is not in the proper format.";
		return 0;
	}

	# If we got here, passed tests!
	$_[HEAP]->{'FORKHANDLERS'} = $handlers;

	# All done!
	return 1;
}

# Gets the FORKHANDLERS
sub GetForkHandlers {
	# ARG0 = session, ARG1 = event
	my( $session, $event ) = @_[ ARG0, ARG1 ];

	# Validation
	if ( ! defined $session or ! defined $event ) {
		return undef;
	}

	# Make a deep copy of the handlers
	require Storable;

	my $handlers = Storable::dclone( $_[HEAP]->{'FORKHANDLERS'} );

	# All done!
	$_[KERNEL]->post( $session, $event, $handlers );

	# All done!
	return 1;
}

# The actual manager of connections
sub Got_Connection {
	# ARG0 = Socket, ARG1 = Remote Address, ARG2 = Remote Port
	my ( $socket ) = $_[ ARG0 ];

	# Should we SSLify it?
	if ( defined $_[HEAP]->{'SSLKEYCERT'} ) {
		# SSLify it!
		eval { $socket = Server_SSLify( $socket ) };
		if ( $@ ) {
			warn "Unable to turn on SSL for connection from " . Socket::inet_ntoa( $_[ARG1] ) . " -> $@";
			close $socket;
			return 1;
		}
	}

	# Set up the Wheel to read from the socket
	my $wheel = POE::Wheel::ReadWrite->new(
		'Handle'	=>	$socket,
		'Driver'	=>	POE::Driver::SysRW->new(),
		'Filter'	=>	POE::Filter::HTTPD->new(),
		'InputEvent'	=>	'Got_Input',
		'FlushedEvent'	=>	'Got_Flush',
		'ErrorEvent'	=>	'Got_Error',
	);

	# Save this wheel!
	# 0 = wheel, 1 = Output done?, 2 = SimpleHTTP::Response object
	$_[HEAP]->{'REQUESTS'}->{ $wheel->ID } = [ $wheel, 0, undef ];

	# Update the scoreboard.
	$_[KERNEL]->call( $_[SESSION], 'UpdateScoreboard' );

	# Debug stuff
	if ( POE::Component::Server::SimpleHTTP::DEBUG ) {
		warn "Got_Connection completed creation of ReadWrite wheel ( " . $wheel->ID . " )";
	}

	# Success!
	return 1;
}

# Finally got input, set some stuff and send away!
sub Got_Input {
	# ARG0 = HTTP::Request object, ARG1 = Wheel ID
	my ( $request, $id ) = @_[ ARG0, ARG1 ];

	# Call the super class method.
	my $rv = POE::Component::Server::SimpleHTTP::Got_Input( @_ );

	# If the connection died/failed for some reason then the request is deleted.
	# In this case, we have to update the scoreboard.
	if ( not exists $_[HEAP]->{'REQUESTS'}->{ $id } ) {
		$_[KERNEL]->call( $_[SESSION], 'UpdateScoreboard' );
	}

	return $rv;
}

# Finished with a request!
sub Got_Flush {
	# ARG0 = wheel ID
	my ( $id ) = $_[ ARG0 ];

	# Call the super class method.
	my $rv = POE::Component::Server::SimpleHTTP::Got_Flush( @_ );

	# If the connection died/failed for some reason then the request is deleted.
	# In this case, we have to update the scoreboard.
	if ( not exists $_[HEAP]->{'REQUESTS'}->{ $id } ) {
		$_[KERNEL]->call( $_[SESSION], 'UpdateScoreboard' );
	}

	return $rv;
}

# Got some sort of error from ReadWrite
sub Got_Error {
	# Call the super class method.
	my $rv = POE::Component::Server::SimpleHTTP::Got_Error( @_ );

	# The connection was probably cleared, so update the scoreboard.
	$_[KERNEL]->call( $_[SESSION], 'UpdateScoreboard' );

	return $rv;
}

# Closes the connection
sub Request_Close {
	# Call the super class method.
	my $rv = POE::Component::Server::SimpleHTTP::Request_Close( @_ );

	# The connection was probably cleared, so update the scoreboard.
		$_[KERNEL]->call( $_[SESSION], 'UpdateScoreboard' );

	return $rv;
}

# End of module
1;

__END__
=head1 NAME

POE::Component::Server::SimpleHTTP::PreFork - PreForking support for SimpleHTTP

=head1 SYNOPSIS

	use POE;
	use POE::Component::Server::SimpleHTTP::PreFork;

	# Start the server!
	POE::Component::Server::SimpleHTTP::PreFork->new(
		'ALIAS'		=>	'HTTPD',
		'ADDRESS'	=>	'192.168.1.1',
		'PORT'		=>	11111,
		'HOSTNAME'	=>	'MySite.com',
		'HANDLERS'	=>	[
			{
				'DIR'		=>	'^/bar/.*',
				'SESSION'	=>	'HTTP_GET',
				'EVENT'		=>	'GOT_BAR',
			},
			{
				'DIR'		=>	'^/$',
				'SESSION'	=>	'HTTP_GET',
				'EVENT'		=>	'GOT_MAIN',
			},
			{
				'DIR'		=>	'^/foo/.*',
				'SESSION'	=>	'HTTP_GET',
				'EVENT'		=>	'GOT_NULL',
			},
			{
				'DIR'		=>	'.*',
				'SESSION'	=>	'HTTP_GET',
				'EVENT'		=>	'GOT_ERROR',
			},
		],

		# In the testing phase...
		'SSLKEYCERT'		=>	[ 'public-key.pem', 'public-cert.pem' ],

		# In the testing phase...
		'FORKHANDLERS'		=>	{ 'HTTP_GET' => 'FORKED' },
		'MINSPARESERVERS'	=>	5,
		'MAXSPARESERVERS'	=>	10,
		'MAXCLIENTS'		=>	256,
		'STARTSERVERS'		=>	10,
	) or die 'Unable to create the HTTP Server';

=head1 ABSTRACT

	Subclass of SimpleHTTP for PreForking support

=head1 New Constructor Options

=over 5

=item C<MINSPARESERVERS>

	An integer that tells the server how many spares should be in the pool at any given
	time. Processes are forked off at a rate of 1 a second until this limit is met.

=item C<MAXSPARESERVERS>

	An integer that tells the server the maximum number of spares that may be in the pool
	at any given time. It is possible for more than this number of spares to exist, but at the very
	least the parent will stop forking requests off and the children will start to die eventually.

	If this value is less than MINSPARESERVERS then it is set to MINSPARESERVERS + 1.

=item C<MAXCLIENTS>

	An integer that tells the server the maximum number of clients that will be
	created. After this limit is reached, no more spares will be forked, even if the number drops below
	MINSPARESERVERS.

=item C<STARTSERVERS>

	An integer that tells the server how many processes to prefork at startup.

=item C<FORKHANDLERS>

	A HASH where the keys are sessions and the values are events. When a child forks,
	before it begins accepting connections it will call these events on the specified
	sessions. This allows you to setup per-process resources (such as database
	connections, ldap connects, etc). These events will never be called for the
	parent.

=back

=head2 New Events

=over 4

=item C<ISCHILD>

	Returns true if you are inside a child, false if you are in the parent.

=item C<GETFORKHANDLERS>

	This event accepts 2 arguments: the session + event to send the response to.

	This even will send back the current FORKHANDLERS hash ( deep-closed via
	Storable::dclone ).

	The resulting hash can be played around to your tastes, then once you are done...

=item C<SETFORKHANDLERS>

	This event accepts only one argument: reference to FORKHANDLERS hash.

	BEWARE: this event is disabled in a forked child.

=back

=head1 Miscellaneous Notes

	BEWARE: HANDLERS munging is disabled in a forked child. Also, handlers changed in
	the parent will not appear in the already forked children.

	BEWARE: for a child, calling {STOP,START}LISTEN does not {destroy,recreate} the
	SOCKETFACTORY like it does in the parent. Instead, the child will {pause,resume}
	accepting connections on the current SOCKETFACTORY. Also, {STOP,START}LISTEN does
	not have any effect on the scoreboard calculations: this child will still
	be marked a spare if it finishes all its requests.

	The shutdown event is altered a little bit
		GRACEFUL -> sends a TERM signal to all remaining children and waits for their death
		NOARGS -> kills all remaining children with prejudice

	Keep in mind that being forked means any global data is not shared between processes and etc. Please see perlfork for all the implications on your platform.

=head1 New Compile-time constants

Checking spares every second may be a bit too much for you.
You can override this behavior by doing this:

	sub POE::Component::Server::SimpleHTTP::PreFork::CHECKSPARES_INTERVAL () { 10 }
	use POE::Component::Server::SimpleHTTP::PreFork;

If the prefork failed because it could not obtain shared memory for the scoreboard,
then if retries after 5 seconds. You can override this behavior by doing this:

	sub POE::Component::Server::SimpleHTTP::PreFork::PREFORK_INTERVAL () { 10 }
	use POE::Component::Server::SimpleHTTP::PreFork;

If you would like to see the contents of the scoreboard every second then do this:

	sub POE::Component::Server::SimpleHTTP::PreFork::DEBUGSB () { 1 }
	use POE::Component::Server::SimpleHTTP::PreFork;

=head2 EXPORT

Nothing.

=head1 SEE ALSO

	L<POE::Component::Server::SimpleHTTP>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>
Stephen Butler E<lt>stephen.butler@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Apocalypse + Stephen Butler

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
