# Declare our package
package POE::Component::Server::SimpleHTTP::Response;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
# $Revision: 1181 $
our $VERSION = '1.04';

# Set our stuff to HTTP::Response
use base qw( HTTP::Response );

# Creates a new instance!
sub new {
	# Remove the tempclass
	my $tempclass = shift;

	# Get the Wheel ID
	my $wid = shift;

	# Get the Connection object
	my $conn = shift;

	# Make sure we got the wheel ID!
	if ( ! defined $wid ) {
		die 'Did not get a Wheel ID!';
	}

	# Create the instance!
	my $self = HTTP::Response->new();

	# Add the Wheel ID
	$self->{'WHEEL_ID'} = $wid;

	# Add the connection object
	$self->{'CONNECTION'} = $conn;

	# Bless it to ourself!
	bless( $self, 'POE::Component::Server::SimpleHTTP::Response' );

	# All done!
	return $self;
}

# Gets the Wheel ID
sub _WHEEL {
	return shift->{'WHEEL_ID'};
}

# Gets the connection object
sub connection {
	return shift->{'CONNECTION'};
}

sub stream {
   my $self = shift;
   my (%opt) = (@_);

   no strict 'refs';

   if ($opt{event} ne '') {
      $self->{'STREAM_SESSION'}     = $opt{'session'} || undef;
      $self->{'STREAM'}             = $opt{'event'};
      $self->{'DONT_FLUSH'}         = $opt{'dont_flush'};
   }
   else {
      $self->{'STREAM'} = shift;
   }
}

# End of module
1;

__END__
=head1 NAME

POE::Component::Server::SimpleHTTP::Response - Emulates a HTTP::Response object, used for SimpleHTTP

=head1 SYNOPSIS

	use POE::Component::Server::SimpleHTTP::Response;
	my $response = POE::Component::Server::SimpleHTTP::Response->new( $wheel_id, $connection );

	print $response->connection->remote_ip;

=head1 DESCRIPTION

	This module is used as a drop-in replacement, because we need to store the wheel ID + connection object for the response.

	Use $response->connection to get the SimpleHTTP::Connection object

=head2 EXPORT

Nothing.

=head1 SEE ALSO

	L<POE::Component::Server::SimpleHTTP>

	L<POE::Component::Server::SimpleHTTP::Connection>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
