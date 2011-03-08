# Declare our package
package POE::Component::Server::SimpleHTTP::Connection;

use strict;
use warnings;

our $VERSION = '2.10';

use Socket qw( inet_ntoa unpack_sockaddr_in );
use POE;

use Moose;

has dead => (
  is => 'rw',
  isa => 'Bool',
  default => 0,
);

has ssl => (
  is => 'rw',
  isa => 'Bool',
  default => 0,
);

has sslcipher => (
  is => 'rw',
  default => undef,
);

has remote_ip => (
  is => 'ro',
);

has remote_port => (
  is => 'ro',
);

has remote_addr => (
  is => 'ro',
);

has local_ip => (
  is => 'ro',
);

has local_port => (
  is => 'ro',
);

has local_addr => (
  is => 'ro',
);

has ID => (
  is => 'rw',
);

has OnClose => (
  is => 'ro',
  default => sub { { } },
);

sub BUILDARGS {
   my $class = shift;

   my $self = { };

   my $socket = shift;

   eval {
      ( $self->{'remote_port'}, $self->{'remote_addr'} ) =
        unpack_sockaddr_in( getpeername($socket) );
      $self->{'remote_ip'} = inet_ntoa( $self->{'remote_addr'} );

      ( $self->{'local_port'}, $self->{'local_addr'} ) =
        unpack_sockaddr_in( getsockname($socket) );
      $self->{'local_ip'} = inet_ntoa( $self->{'local_addr'} );
   };

   if ($@) {
      return undef;
   }

   return $self;
}

sub _on_close {
   my ( $self, $sessionID, $state, @args ) = @_;
   if ($state) {
      $self->OnClose->{$sessionID} = [ $state, @args ];
      $poe_kernel->refcount_increment( $sessionID, __PACKAGE__ );
   }
   else {
      my $data = delete $self->OnClose->{$sessionID};
      $poe_kernel->refcount_decrement( $sessionID, __PACKAGE__ ) if $data;
   }
}

sub DEMOLISH {
   my ($self) = @_;
   while ( my ( $sessionID, $data ) = each %{ $self->OnClose || {} } ) {
      $poe_kernel->call( $sessionID, @$data );
      $poe_kernel->refcount_decrement( $sessionID, __PACKAGE__ );
   }
}

no Moose;

__PACKAGE__->meta->make_immutable;

# End of module
1;

__END__

=head1 NAME

POE::Component::Server::SimpleHTTP::Connection - Stores connection information for SimpleHTTP

=head1 SYNOPSIS

	use POE::Component::Server::SimpleHTTP::Connection;
	my $connection = POE::Component::Server::SimpleHTTP::Connection->new( $socket );

	# Print some stuff
	print $connection->remote_port;

=head1 DESCRIPTION

	This module simply holds some information from a SimpleHTTP connection.

=head2 METHODS

	my $connection = POE::Component::Server::SimpleHTTP::Connection->new( $socket );

	$connection->remote_ip();	# Returns remote ip in dotted quad format ( 1.1.1.1 )
	$connection->remote_port();	# Returns remote port
	$connection->remote_addr();	# Returns true remote address, consult the L<Socket> POD
	$connection->local_addr();	# Returns true local address, same as above
	$connection->local_ip();	# Returns local ip in dotted quad format ( 1.1.1.1 )
	$connection->local_port();	# Returns local port
	$connection->dead();		# Returns a boolean value whether the socket is closed or not
	$connection->ssl();		# Returns a boolean value whether the socket is SSLified or not
	$connection->sslcipher();	# Returns the SSL Cipher type or undef if not SSL
	$connection->ID();          # unique ID of this connection

=head2 EXPORT

Nothing.

=head1 SEE ALSO

L<POE::Component::Server::SimpleHTTP>,
L<POE::Component::Server::SimpleHTTP::Response>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

Chris C<BinGOs> Williams <chris@bingosnet.co.uk>

=head1 COPYRIGHT AND LICENSE

Copyright E<copy> Apocalypse and Chris Williams

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
