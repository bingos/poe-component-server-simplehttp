#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
#use Test::More tests => 11;

use HTTP::Request;
use POE;
use POE::Kernel;
use POE::Component::Server::SimpleHTTP;
use LWP;




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
    diag("$$: Sleep 2...");
    sleep 2;
    diag("continue");
    my $ua = LWP::UserAgent->new();
    my $request = HTTP::Request->new( GEt => "http://$IP:$PORT/hello.html");
    my $resp = $ua->request( $request );
    is( $resp->code, 400, 'Good, got back response with correct error code from bad request.' );
    diag( $resp->content );
}

####################################################################
else  # we are the child
{                          
    	POE::Component::Server::SimpleHTTP->new(
    	'ALIAS'    => 'SimpleHTTP',
    	'ADDRESS'  => "$IP",
    	'PORT'     => $PORT,
    	'HANDLERS' => [
        	{
            	'DIR'     => qr/^\/hello\.html$/,
            	'SESSION' => 'HTTPD',
            	'EVENT'   => 'hello',
        	},
    	],
	) or die 'Unable to create the HTTP Server';
	
	POE::Session->create(
    	inline_states => {
        	'_start'    => sub { $_[KERNEL]->alias_set('HTTPD') },
        	'hello'     => \&handle_hello,
        	'not_found' => \&handle_not_found,
    	},
	);
	
    $poe_kernel->run;
}

sub handle_hello 
{
   	my ( $request, $response, $dirmatch ) = @_[ ARG0 .. ARG2 ];
	
   	$response->code(200);
  	$response->content("Hello");
	
  	$_[KERNEL]->post('SimpleHTTP', 'DONE', $response );
}

