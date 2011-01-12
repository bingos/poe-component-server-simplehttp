package POE::Component::Server::SimpleHTTP::State;

use strict;
use warnings;
use POE::Wheel::ReadWrite;

our $VERSION = '2.08';

use Moose;

has 'wheel' => ( 
  is => 'ro',
  isa => 'POE::Wheel::ReadWrite',
  clearer => 'clear_wheel',
  predicate => 'has_wheel',
  required => 1,
);

has 'response' => (
  is => 'ro',
  isa => 'POE::Component::Server::SimpleHTTP::Response',
  writer => 'set_response',
  clearer => 'clear_response',
);

has 'request' => (
  is => 'ro',
  isa => 'HTTP::Request',
  writer => 'set_request',
  clearer => 'clear_request',
);

has 'connection' => (
  is => 'ro',
  isa => 'POE::Component::Server::SimpleHTTP::Connection',
  writer => 'set_connection',
  clearer => 'clear_connection',
  init_arg => undef,
);

has 'done' => (
  is => 'ro',
  isa => 'Bool',
  init_arg => undef,
  default => sub { 0 },
  writer => 'set_done',
);

has 'streaming' => (
  is => 'ro',
  isa => 'Bool',
  init_arg => undef,
  default => sub { 0 },
  writer => 'set_streaming',
);

sub reset {
  my $self = shift;
  $self->clear_response;
  $self->clear_request;
  $self->set_streaming(0);
  $self->set_done(0);
  $self->wheel->set_output_filter( $self->wheel->get_input_filter ) if $self->has_wheel;
  return 1;
}

sub close_wheel {
  my $self = shift;
  return unless $self->has_wheel;
  $self->wheel->shutdown_input;
  $self->wheel->shutdown_output;
  $self->clear_wheel;
  return 1;
}

sub wheel_alive {
  my $self = shift;
  return unless $self->has_wheel;
  return unless defined $self->wheel;
  return unless $self->wheel->get_input_handle();
  return 1;
}

no Moose;

__PACKAGE__->meta->make_immutable();

'This monkey has gone to heaven';

__END__
