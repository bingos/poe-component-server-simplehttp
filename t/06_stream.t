use strict;
use Test::More;

plan skip_all => 'MSWin32 does not have a proper fork()' if $^O eq 'MSWin32';

plan tests => 3;

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
      $heap->{'count'} = 1;
      POE::Component::Client::HTTP->spawn(
         Agent     => 'TestAgent',
         Alias     => 'ua',
         Protocol  => 'HTTP/1.1', 
         From      => 'test@tester',
         Streaming => 100,
      );
   
      my $request = HTTP::Request->new(GET => "http://$IP:$PORT/");
      
      diag('Test a stream of 3 helloworlds ..');
      POE::Kernel->post('ua', 'request', 'response', $request);
   }
   
   sub response {
      my ( $kernel, $heap, $session, $request_packet, $response_packet ) 
         = @_[KERNEL, HEAP, SESSION, ARG0, ARG1];
   
      my $return;
   
      # HTTP::Request
      my $request  = $request_packet->[0];
      my $response = $response_packet->[0];
      
      # the PoCoClientHTTP sends the first chunk in the content
      # of the http response
      #if ($heap->{'count'} == 1) {
      #   my $data = $response->content;
      #   chomp($data);
#print $data."\n";
       #  ok($data =~ /Hello World 0/, "First one as response content received");
      #}
      
      # then all streamed data in the second element of the response
      # array ...
      my ($resp, $data) = @$response_packet;
      chomp($data);
      
      ok($data =~ /Hello World/, "Received a hello");
  
      if ($heap->{'count'} == 2) {
         is($heap->{'count'}, 2, "Got 3 streamed helloworlds ... all good :)");
         exit;
      }
      $heap->{'count'}++;
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
      session     => 'HTTP_GET',
      event       => 'GOT_STREAM'
   );   

   $heap->{'count'} ||= 0;
    
    # We are done!
   $kernel->yield('GOT_STREAM', $response);
}

sub GOT_STREAM {
   my ( $kernel, $heap, $response ) = @_[KERNEL, HEAP, ARG0];

   # lets go on streaming ...
   if ($heap->{'count'} <= 2) {
      my $text = "Hello World ".$heap->{'count'}." \n";
      #print "send ".$text."\n";
      $response->content($text);
      
      $heap->{'count'}++;
      POE::Kernel->post('HTTPD', 'STREAM', $response);
   }
   else {
      POE::Kernel->post('HTTPD', 'CLOSE', $response );
   }
}

sub keepalive { 
   my ( $heap ) = @_[HEAP];

   $_[KERNEL]->delay_set('keepalive', 1);
}

