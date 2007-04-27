#!/usr/bin/perl -w

use strict;
use Test::More tests => 11;

use HTTP::Request;
use POE;
use POE::Kernel;
use POE::Component::Client::HTTP;
use POE::Component::Server::SimpleHTTP;


my $PORT = 2080;
my $IP = "localhost";

my $pid = fork;
die "Unable to fork: $!" unless defined $pid;

END {
    if ($pid) {
        kill 2, $pid or warn "Unable to kill $pid: $!";
    }
}

####################################################################
if ($pid)  # we are parent
{                      
    # stop kernel from griping
    ${$poe_kernel->[POE::Kernel::KR_RUN]} |=
      POE::Kernel::KR_RUN_CALLED;

    diag("$$: Sleep 2...");
    sleep 2;
    diag("continue");

	my $states = {
	  _start    => \&_start,
	  response  => \&response,
	};
		
   POE::Session->create( inline_states => $states );

   sub _start {
      my ( $kernel, $heap, $session ) = @_[KERNEL, HEAP, SESSION ];
      $kernel->alias_set('TestAgent');
      print "START \n";
      
      POE::Component::Client::HTTP->spawn(
         Agent     => 'TestAgent',
         Alias     => 'ua',
         Protocol  => 'HTTP/1.1', 
         From      => 'test@tester',
         Streaming => 12,
      );
   
      my $request = HTTP::Request->new(GET => "http://$IP:$PORT/");
      
      diag('Test a stream of 10 helloworlds ..');
      POE::Kernel->post('ua', 'request', 'response', $request);
      
   }
   
   sub response {
      my ( $kernel, $heap, $session, $request_packet, $response_packet ) 
         = @_[KERNEL, HEAP, SESSION, ARG0, ARG1];
   
      my $return;
   
      # HTTP::Request
      my $request  = $request_packet->[0];
      my $response = $response_packet->[0];
      
      $heap->{'count'}++;
      
      my ($resp, $data) = @$response_packet;
      chomp($data);
      print $data." ".$heap->{'count'}." \n";
      
       ok($data =~ /Hello World/, 'Hello World');
   
      if ($heap->{'count'} == 10) {
         
         is($heap->{'count'}, 10, "Got 10 chuncks ... all good :)");
         exit;
      }
   }

   POE::Kernel->run;
}

####################################################################
else  # we are the child
{                          
    POE::Component::Server::SimpleHTTP->new(
                'ALIAS'         =>      'HTTPD',
                'ADDRESS'       =>      "$IP",
                'PORT'          =>      $PORT,
                'HOSTNAME'      =>      'pocosimpletest.com',
                'HANDLERS'      =>      [
               		{
               			'DIR'		=>	'.*',
               			'SESSION'	=>	'HTTP_GET',
               			'EVENT'		=>	'GOT_MAIN',
               		},
                ],
    );
    # Create our own session to receive events from SimpleHTTP
    POE::Session->create(
                inline_states => {
                        '_start'        => sub {   
                           $_[KERNEL]->alias_set( 'HTTP_GET' );
                           $_[KERNEL]->yield('keepalive');
                        },
                  		'GOT_MAIN'	   =>	\&GOT_MAIN,
                  		'GOT_STREAM'	=>	\&GOT_STREAM,
		                  keepalive      => \&keepalive,
                },   
    );
    
    POE::Kernel->run;
}


sub GOT_MAIN {
	# ARG0 = HTTP::Request object, ARG1 = HTTP::Response object, ARG2 = the DIR that matched
	my( $kernel, $heap, $request, $response, $dirmatch ) = @_[KERNEL, HEAP, ARG0 .. ARG2 ];

	# Do our stuff to HTTP::Response
	$response->code( 200 );
   
   $response->content_type("text/plain");
   
   print "# GOT_MAIN \n";
   # sets the response as streamed within our session with the stream event
   $response->stream(
      session  => 'HTTP_GET',
      event    => 'GOT_STREAM'
   );   

   $heap->{'count'} ||= 10;
   
	# We are done!
	POE::Kernel->post( 'HTTPD', 'DONE', $response );
}

sub GOT_STREAM {
   my ( $kernel, $heap, $stream ) = @_[KERNEL, HEAP, ARG0];

   # lets go on streaming ...
   if ($heap->{'count'} >= 0) {
      
      $stream->{'wheel'}->put("Hello World\n");
      $heap->{'count'}--;
      
      POE::Kernel->delay('GOT_STREAM', 1, $stream );
   }
   else {
      POE::Kernel->post('HTTPD', 'CLOSE', $stream->{'response'} );
   }
}

sub keepalive { 
   my ( $heap ) = @_[HEAP];

   $_[KERNEL]->delay_set('keepalive',3);
}

